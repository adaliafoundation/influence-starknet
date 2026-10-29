# Mission observer and colonization integration

This replaces `MissionAction` with observation of the existing native gameplay calls. No signed validator or historical transaction submission is needed. The client/server selects explicit candidate assignments and schedules refreshes; on-chain observation establishes evidence and on-chain claims enforce entitlement.

## SDK/server deliverables

After `npm run build`, run `npm run export-missions`. The generated `target/missions/` directory contains:

- `manifest.json`: exact class hashes, ABI filenames, mission IDs, rewards in SWAY base units, observation targets, and evidence slots.
- Individual ABIs for Dispatcher, observer, campaign implementations, and mission systems.
- `missionObservation.js`: the transaction builder reference implementation (requires the project's `starknet` dependency).

Source definitions are in `bin/lib/missionDefinitions.js`; the SDK helper is `bin/lib/missionObservation.js`. Class hashes are build outputs, not deployed addresses. Sierra/CASM declaration artifacts remain under `target/dev/`.

## Deployment and starter cutover

1. Declare the new Dispatcher, MissionObserver, campaign implementations, and mission systems. Upgrade the existing Dispatcher at its existing address; its previous storage layout is retained.
2. Register `MissionObserver` as a system class. It exposes `before` and `after`, not a gameplay `run` entrypoint. Register the new mission systems and campaign class names through the existing administrator registry.
3. For an existing starter campaign, call `MigrateStarterObserver(expected_old, replacement)` through the Dispatcher. `replacement` must equal the registered `StarterMissionCampaign`. The migration checks the old pinned class and mission count, replaces the implementation once, preserves all lifecycle/evidence slots, and clears the obsolete `MissionAction` registry entry. The migration is for this repository's starter deployment; do not retire the global entrypoint while another deployed campaign still depends on it.
4. For a fresh starter campaign, use `RegisterMissionCampaign(id, StarterMissionCampaign class, 8)` and `ConfigureStarterMissions` as before. There is no wrapper to register.
5. Register a distinct colonization campaign with `RegisterMissionCampaign(id, ColonizationMissionCampaign class, 5)`, then call `ConfigureColonizationMissions(id)`. This initializes the agreed reward schedule in mission storage and sets `COLONIZATION_CAMPAIGN` once.
6. Fund the Dispatcher with SWAY. Claims revert atomically if the treasury cannot pay.

Coordinate client rollout with wrapper retirement. Old wrapper transactions fail after cutover. Existing pending starter work does not need to be restarted or re-enrolled; the new observer reads the same construction, sample, extraction, process, and delivery fingerprints. The historical declared class may still exist on-chain, but the active implementation has no action-execution compatibility path.

Registry/configuration changes can be submitted in one administrator multicall. The one-time migration modifies the definition and wrapper registry directly; refresh deployment metadata after it rather than relying on a `SystemRegistered` event for those two writes.

For a deployment already using observation, register the new campaign classes and call
`UpgradeMissionCampaign(campaign, expected_old_class, replacement_name)` for each pinned
campaign (`replacement_name` is `StarterMissionCampaign` or `ColonizationMissionCampaign`).
This admin-only compare-and-replace updates the definition pointer, leaving mission count,
IDs, lifecycle flags, pending fingerprints, and all player evidence unchanged. Do not rerun
configuration or enrollment. Initial registration remains immutable. The earlier
`MigrateStarterObserver` is only for the original wrapper cutover.

Candidate routing changes the observation ABI: roll out the updated SDK with the Dispatcher
and observer classes. Transactions built for the previous observation ABI must be rebuilt;
there is no legacy execution entrypoint. This is a client/contract upgrade, not a progress migration.

## Explicit mission candidates

Pass `candidates: [{ campaign, subject: { label, id }, mission }, ...]` to the SDK helper.
The helper groups candidates by campaign and subject and merges their mission bits.
Onchain policy data contains at most eight groups, with two felts per group:
`[campaign, packedSubject + missionMask * 2^80]`. `packedSubject = label + id * 65536`.
The Dispatcher treats this as opaque policy data; only MissionObserver interprets it.
Empty lists, invalid masks/campaigns, duplicate raw groups, unenrolled subjects, and wrong
native subjects are rejected. The SDK coalesces duplicate assignments before encoding.

Only nominated campaigns produce evidence and only nominated mission indices have their
completion checked. Existing evidence is shared within a campaign: recording a native
process or delivery may establish evidence useful to another mission, but that mission is
not automatically validated. Later acceptance or `MissionValidate` can use that shared
evidence. This preserves the original cross-mission provenance and mid-action upgrades.

Nominate missions that an action advances, including starts—not only immediate completions.
The campaign must be enrolled (mission 0 accepted), but individual later missions need not
yet be accepted. Do not filter candidate discovery to accepted mission indices only; doing
so could omit construction or production evidence gathered before those acceptances.
For colonization: scan start/finish nominate 0; Habitat construction/use nominate 1;
Spaceport construction/docking nominate 2; Marketplace construction/fills nominate 3.
Include 4 when a qualifying use may complete the capstone, or call `MissionValidate` for 4
later. ConstructionFinish observation is optional for colony-only work; current operational
state and the recorded construction-start fingerprint are checked on use and capstone claim.

For starter work, nominate the relevant building/production mission, storage mission 3 for
warehouse receipts, and mission 7 for production-chain/economic-use evidence. Include
multiple candidates when a receipt or production action advances multiple missions. Existing
shared producer logic is retained, so candidate lists do not erase prerequisite evidence.

## One transaction per observed action

The account submits:

1. `Dispatcher.begin_observation(policy, system, arguments_hash, expected_caller, policy_data)`.
2. Existing native execution calls, including payment receipts or Escrow.withdraw when applicable.
3. `Dispatcher.end_observation()`.

`policy` is the short-string felt `MissionObserver`. `arguments_hash` is Poseidon over the **exact native argument array received by run_system**, excluding its system-name/array-length header and excluding the four Context fields that Dispatcher appends. Include the caller crew and any callback fields appended by Escrow.

The Dispatcher matches the transaction hash, transaction account, system name, arguments hash, and immediate caller. It runs the policy's before/native/after sequence synchronously. The policy can credit both nominated starter and colonization targets from the same invocation. The candidate data is fixed by the account when arming and cannot be substituted by the native caller. An arm is consumed at most once. Pending arms do not apply to later transactions. Use sequential arm/action/end groups for multiple observed actions in one account multicall.

The final step is required in SDK-built transactions: a wrong hash or caller otherwise leaves the gameplay action unobserved. `end_observation` makes that mismatch revert the whole transaction. Any native, pre-hook, post-hook, or finalization failure rolls back gameplay, transfers, and evidence together.

For direct calls, `expected_caller` is the account. For Escrow.withdraw callbacks it is the Escrow contract. For `run_system_with_payment` it is the SWAY callback contract; use its existing native payment mechanism unchanged.

### Direct call

```js
const nativeArgs = [buildingLabel, buildingId, crewLabel, crewId];
const calls = observeMissionAction({
  dispatcher, account: account.address,
  system: 'ConstructionStart', calldata: nativeArgs,
  candidates: [{ campaign: colonyCampaign, subject: { label: asteroidLabel, id: asteroidId }, mission: 1 }],
  executionCalls: [{
    contractAddress: dispatcher, entrypoint: 'run_system',
    calldata: [shortString.encodeShortString('ConstructionStart'), nativeArgs.length, ...nativeArgs]
  }]
});
await account.execute(calls);
```

### Escrow buy fill

Keep the stored withdraw hook and Escrow.withdraw execution unchanged. Compute the observed calldata from the order's fixed native fields and the fill fields, followed by the data Escrow appends:

```text
buyer_crew, exchange, product, price, storage, storage_slot,
amount, origin, origin_slot, caller_crew,
escrow_caller, 2, escrow_token, withdrawal_count,
(recipient, amount_low, amount_high) ...
```

Use `escrowWithdrawalArguments` to append the callback fields, then `observeMissionAction` with `expectedCaller: escrowAddress` the normal withdraw call in `executionCalls`, and a colony commerce candidate for the exchange’s asteroid (plus any applicable starter candidates). The helper hashes these fields; it does not replace the Escrow hook or alter its order identity. Native payment and authorization checks remain authoritative.

A successful partial or full fill of a positive quantity qualifies. There is no value floor or account-identity restriction. Cancellation does not qualify, even though buy cancellation shares the FillBuyOrder entrypoint: the observer requires creation of a trade delivery. Commerce credit is earned at fill time, not delivery receipt time.

## Colonization gameplay

Assignment is `(campaign, Entity(ASTEROID, asteroid_id), mission_id)`. The original colonizer is stored immutably under that assignment's shared evidence namespace; it is not the crew that performs later work.

| ID | Mission | Reward (SWAY) | Completion |
|---|---|---:|---|
| 0 | Claim a New World | 150,000 | Enroll before starting the first surface scan; observe its start and successful finish |
| 1 | Build a Habitat | 250,000 | Qualifying construction, then a crew stations in it |
| 2 | Connect the Colony | 300,000 | Qualifying construction, then a ship successfully docks |
| 3 | Establish Commerce | 350,000 | Qualifying construction, then one successful positive-quantity fill |
| 4 | Found a Colony | 450,000 | All three qualifying used buildings are currently operational |

Total: 1,500,000 SWAY (1,500,000,000,000 base units).

`AcceptMission` for mission 0 checks actual NFT ownership and `UNSCANNED` status and permanently binds the colonizer. Started and legacy-scanned asteroids cannot enroll. Scan start and finish must be observed and performed by the colonizer while they own the NFT; native crew-control rules also apply. Enrollment alone earns nothing.

Construction must start after the observed scan completion has been recorded. Equal timestamps are allowed, including scan completion followed by construction start in the same multicall. Planning may predate enrollment or scan completion. Observe ConstructionStart to establish provenance. ConstructionFinish can be observed; subsequent operational use checks both current state and the original construction fingerprint. Pre-existing or previously started buildings cannot qualify.

Anyone may build or use qualifying buildings, regardless of crew ownership or starter eligibility. There are no earlier-campaign prerequisites. Branches may be completed in any order. After scan completion, the owner may accept missions 1–4 independently. Evidence can accumulate before those individual acceptances, and acceptance validates already-earned progress.

Claims are explicit. Every claim must be submitted by the original colonizer, who must currently own the NFT. Selling does not reset or transfer eligibility; buying it back permits outstanding claims again. Historical branch rewards survive building removal, but capstone claims recheck all three selected building fingerprints, locations, types, and operational states even if the capstone's completed flag was previously set. A valid selected building is retained when another qualifying building is used. A newly qualifying used building replaces the selection only when the existing selection no longer qualifies. A paid reward never becomes claimable again.

## Server/indexer state

Use the existing Dispatcher gameplay events to discover active campaign targets and arrange observation on relevant clients. Observe relevant native actions whenever their crew has an active starter campaign or their target asteroid has an active colonization campaign. Third-party actions must also supply the correct candidates to the observed transaction builder. Index enrollment by asteroid, resolve the exchange/building location, and provide that asteroid’s colony assignment even when the trader is not the colonizer. Candidate selection grants no authority: the contract verifies the actual target and existing provenance. Ordinary gameplay remains available without observation, but it does not retroactively earn evidence.

Lifecycle event names and payloads are unchanged:

- `MissionAccepted(campaign, subject, mission)`
- `MissionCompleted(campaign, subject, mission)`
- `MissionRewardClaimed(campaign, subject, mission, recipient, amount)`

Their ABI now lives on ClaimMissionReward instead of the retired MissionAction. Events are emitted at the Dispatcher address. The temporary ExecutionLock no longer emits component-update events. Decode the native events and persistent mission component updates from the same receipt, then read authoritative mission state. Do not count every native gameplay event as observed mission evidence. Reorg handling should follow the existing indexer's chain-finality policy.

`ReadMissionState(assignment, slot)` returns `(accepted, completed, paid, evidence)`, wrapped in the Dispatcher's returned Span. `MissionValidate(assignment, [])` refreshes completion from recorded evidence and current state; it never attests to unobserved history. A previously completed capstone can become temporarily unclaimable, so the server must also check the three selected buildings for claim readiness.

Colonization evidence is shared across all five mission IDs:

| Slot | Meaning |
|---|---|
| short string `Colonizer` | Original account address |
| `ScanStarted` | Pending native Celestial fingerprint, cleared on successful observed finish |
| `ScanFinished` | Observed surface scan completion timestamp |
| `Earned` | Historical bits: 0 scan, 1 habitat, 2 spaceport, 3 marketplace |
| numeric 1 / 2 / 3 | Selected used Habitat / Spaceport / Marketplace building ID |
| Poseidon(`[Built, packed_building, 0]`) | Construction fingerprint |
| Poseidon(`[Used, packed_building, 0]`) | Fingerprint of the construction that received qualifying use |

The underlying keys retain the framework's existing layout: `Evidence/campaign/packed_subject/slot` and `Lifecycle/campaign/packed_subject/(mission_id / 32)`. Reward amounts are stored under `ColonyReward/campaign/mission_id` in base units. No server signing key, nonce format, or validation expiry is required.

## Reproducing validation

```sh
npm run build
npm run build-mission-fixtures
scarb cairo-test
STARKNET_DEVNET_BIN=/path/to/starknet-devnet npm run test-missions-runtime
npm run export-missions
```

The devnet tests use fresh isolated instances on ports 5051 and 5052 (tested with devnet 0.10.1). Fixture contracts are built only under the repository's ignored `temp/mission-runtime-fixtures` directory. They are not part of production deployment or exported artifacts. The native tests cover scanning, third-party construction/stationing, docking, combined starter/colony sell evidence, buy fills/cancellations through real Escrow/SWAY, and reward ownership/replay checks. Policy-level fixtures separately exercise candidate replacement and capstone revalidation.
