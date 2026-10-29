# Starter missions implementation

The reusable campaign framework and the eight agreed starter missions are implemented. Colonization now shares the mission observer; player-authored contract publishing remains deferred. See [mission observer integration](mission-observer-integration.md) for the current SDK/server API and deployment instructions. No live-network deployment or campaign activation was performed.

## Execution model

A campaign is an immutable, administrator-registered `(campaign ID, implementation class hash, mission count)`. An assignment is `(campaign ID, subject Entity, mission index)`. There is no global scan or per-action subscription list.

The public systems are:

- `RegisterMissionCampaign(campaign, implementation, mission_count)` — administrator only; an existing campaign cannot be redefined.
- `AcceptMission(assignment)` — implementation validates admission and prerequisites; the framework marks acceptance and evaluates preserved evidence.
- `MissionObserver` — records evidence before and after a native gameplay action. The account arms observation on the Dispatcher and finalizes it within the same multicall; no action-executing mission wrapper remains.
- `MissionValidate(assignment, arguments)` — evaluates preserved evidence. The starter template accepts either empty arguments or a bound, completed Delivery entity.
- `ClaimMissionReward(assignment)` — settles a completed entitlement once, paying the template-selected recipient.
- `ReadMissionState(assignment, slot)` — returns accepted/completed/paid and one template-defined evidence slot.
- `ConfigureStarterMissions(campaign, crew_cutoff)` — administrator-only, one-time activation of an eight-mission campaign.

Acceptance, validation, and claims run through `Dispatcher.run_system`. Native gameplay calls keep their original calldata, including the actual caller crew. `begin_observation` and `end_observation` surround those calls in the account multicall; the Dispatcher invokes the registered observer around the successful native execution. The shared observer selects the active starter assignment from the actual crew, rather than accepting a client-selected assignment. `FillSellOrder` tracks purchases for Warehouse storage only; colonization independently credits marketplace use.

The implementation interface is `evaluate(assignment, operation, action, arguments, context) -> (beneficiary, reward_micro_sway)`. Operations are accept (0), action (1), validate (2), and quote claim (3). The framework owns lifecycle, lock, and payment; the trusted implementation owns eligibility, action adapters, prerequisites, evidence, and reward policy. A separate asteroid-subject test implementation exercises the same framework without starter branches.

Campaign classes are privileged code executing in Dispatcher storage. Registration is administrator-only. Future player-created missions must instantiate approved templates with bounded parameters and escrowed funding; players will not register arbitrary Cairo. The current framework does not implement publishing, expiry, refunds, or user-funded rewards.

## Starter progression

| Step | Requirement | SWAY | Cumulative |
| --- | --- | ---: | ---: |
| Make Landfall | Plan the campaign Warehouse on a permitted lot | 5,000 | 5,000 |
| Prospect the Surface | Three distinct initial core samples, each ≥500,000 kg initial yield | 20,000 | 25,000 |
| Begin Extraction | Construct an Extractor and complete one ≥100,000 kg raw-resource extraction from a sampled deposit | 30,000 | 55,000 |
| Establish Storage | Construct the campaign Warehouse and have ≥100,000 kg actually stored following receipt | 20,000 | 75,000 |
| Refine the Yield | Construct a Refinery and complete ≥1 recipe-equivalent | 50,000 | 125,000 |
| Cultivate Life | Construct a Bioreactor and complete ≥1 full batch | 35,000 | 160,000 |
| Manufacture Goods | Construct a Factory and complete ≥1 recipe-equivalent | 40,000 | 200,000 |
| Close the Production Loop | Complete an approved ordered pair, then use or deliver a positive amount of its final output product | 25,000 | 225,000 |

All native supported processes for the three building types qualify. Fractions below one do not qualify, even when native biological scheduling rounds them up. Quantities use product mass in grams; 100,000 kg is 100,000,000 grams. Sample yields are already kilograms.

Approved route process IDs are `24 → 23`, `29 → 38`, `27 → 40`, `35 → 56`, and `89 → 33`. Each stage meets the one-recipe/full-batch threshold. The intermediate must be an actual positive stage-one output and a stage-two input. Stage one must have completed before stage two starts. The same building may perform both stages. Purchased inputs and replacement units count: there is no batch tracing or inventory custody requirement. Silica Fusing (35) uses a Factory in the current SDK data.

Storage counts actual mixed-product inventory mass, excluding reservations. Purchases count after delivery completes. Receipt by the campaign crew into its campaign Warehouse can qualify even when the sender did not participate. Extraction output can qualify directly. Merely constructing the Warehouse does not.

Capstone economic-use adapters currently cover `ProcessProductsStart`, material-funded `ConstructionStart`, `ResupplyFood`, and completed `SendDelivery`/`ReceiveDelivery`. Empty-allowance construction/food, stockholding, inflight deliveries, and unfilled listings do not qualify. Delivery to the same entity does not qualify as economic transfer. Sales do not qualify, including fills of standing buy orders. The `FillSellOrder` adapter only accepts the buyer's assignment and preserves native buyer authorization and seller/fee receipt checks. Purchased deliveries may satisfy Warehouse storage, but do not count as capstone economic use.

## Eligibility and entitlement

Crews qualify when their ID is strictly greater than the configured cutoff and they are manned and not invalidated. Set the cutoff to the actual existing-crew boundary at activation; this is a launch parameter, not hard-coded deployment data.

Acceptance alone does not invalidate either crew in a clean-to-clean exchange. First campaign participation is recorded when capturing action evidence. Once a participating crew changes membership through exchange, it becomes invalid, and outgoing members contaminate the recipient. Existing invalid and cutoff-excluded crews contaminate recipients too. Reciprocal swaps propagate invalidity in both directions in that same transaction. Emptying/refilling a crew never resets flags. Fresh Adalian recruitment and reorder are allowed; Arvadian initialization invalidates starter eligibility.

The hooks live in ordinary `ExchangeCrew` and `InitializeArvadian`, so omitting mission observation does not bypass contamination. They are inactive until starter missions are configured. Crew NFT ownership/delegation changes preserve the crew-bound assignment.

Completion and payout are separate. A completed entitlement survives later invalidation and pays the current crew delegate. Claims mark paid before token transfer, assert transfer success, and use a reentrancy lock; a revert rolls the transaction back. Treasury funding is required, but an empty treasury does not prevent gameplay completion. Clients may batch completion, acceptance, and claims where prerequisites allow.

## Compact evidence

`Mission` stores one felt per slot through the existing component framework. Writes skip unchanged values. There are no stored copies of gameplay events and no mandatory provenance array length.

| Data | Storage |
| --- | --- |
| Campaign definition | Two felts shared by all participants: class hash and mission count |
| Assignment lifecycle | One felt per 32 missions per campaign/subject; accepted/completed/paid use 96 bits. All eight starter steps fit one word |
| Starter earned evidence | One felt: eight requirement bits, two sample-count bits, five upstream-route bits |
| Campaign Warehouse | One entity ID felt |
| Participation / invalidation | At most one felt each per crew, permanently sticky |
| Construction attribution | One fingerprint per participating building |
| Pending initial sample | One fingerprint, cleared on consumption |
| Pending extraction | One fingerprint per extractor slot, cleared on consumption |
| Pending process | One fingerprint and, only for linked downstream processing, a route mask; cleared on consumption |
| Final products | Packed product-ID bitmaps, 128 IDs per felt |
| Pending delivery | One fingerprint plus an optional economic-use bit, cleared on consumption |
| Reentrancy guard | One shared lock slot, reset after execution |

### What a Mission component instance represents

`Mission { value: felt252 }` is a single storage cell. It is not a struct containing an entire mission, and there is not necessarily one component instance per mission. The existing component machinery derives each address from the component name `Mission` and a path. Different paths select independent cells; zero reads as unset, and the mission helpers return zero for those cells.

The framework reserves these path namespaces:

```text
['Definition', campaign]                         → implementation class hash
['DefinitionCount', campaign]                    → number of missions
['Lifecycle', campaign, packed_subject, page]    → accepted/completed/paid bits
['Evidence', campaign, packed_subject, slot]     → template-owned felt
['StarterParticipated', packed_crew]             → sticky participation flag
['StarterInvalid', packed_crew]                  → sticky invalidation flag
['ExecutionLock']                               → shared reentrancy guard
```

The two starter eligibility paths belong to the starter policy, not to generic campaign lifecycle logic. They deliberately survive crew membership changes. The generic framework only defines the first four namespaces and the execution lock.

For lifecycle, `page = mission_index / 32` and `offset = mission_index % 32`. Acceptance uses bit `offset`, completion uses bit `32 + offset`, and payout uses bit `64 + offset`. Thus all eight starter missions share one lifecycle cell. The starter evidence cell at slot 0 is separate: its bits record requirements already earned, even when their corresponding mission has not yet been accepted.

The evidence path deliberately omits the mission index. `state(assignment, slot)` selects shared evidence for the assignment's campaign and crew. A future campaign can choose an entirely different slot schema, or derive slots from its mission index when it needs separate evidence. No generic provenance fields or array length are imposed.

### Worked starter flow

1. The crew accepts Make Landfall. The framework sets its accepted bit after the starter policy checks the cutoff, roster validity, delegate, and prerequisites.
2. The client calls `run_system('MissionAction', ...)`, identifying that assignment and `ConstructionPlan`. The starter adapter checks the action and forwards it to the existing construction system with the original Context. Successful planning records the Warehouse ID in evidence slot 1 and Landfall's earned bit in slot 0. Validation marks the accepted mission completed.
3. While participating in that campaign, the crew can sample ahead of accepting Prospect the Surface. Each wrapped sampling start saves one fingerprint under an entity-derived evidence slot. At finish, the adapter matches current native deposit state against the fingerprint before running the native finish, checks the initial yield, increments the packed qualifying count, and clears the fingerprint. Three qualifying samples set Prospect's earned bit.
4. Accepting Prospect later reads that existing campaign evidence and immediately marks it completed if its predecessor is complete. The distinction between *earned evidence* and *completed entitlement* preserves early work without bypassing acceptance or prerequisites.
5. Extraction and processing follow the same start/finish pattern. The pending hash identifies the observed run; native components retain the full action data. Completion clears temporary evidence and retains compact results. Capstone progress records compatible ordered stages and eligible final-product bits, rather than tracking specific material batches.
6. Claiming checks accepted/completed/not-paid, asks the implementation for the reward and current delegate, marks paid, and transfers SWAY. A failed transfer reverts the paid marker and lock together. Later contamination prevents new progress but does not erase completed entitlements.

The starter template defines these layouts; the core does not interpret them. Evidence is campaign-scoped so earlier observed work can satisfy later accepted missions. Prerequisites govern completion/acceptance, not when useful evidence can be gathered. Work done before campaign acceptance or outside the wrapper is not retroactively inferred. Exceptions are the specifically verified receiving/reconciliation paths above.

Pending fingerprints commit the authoritative native action state instead of duplicating it. Positive-duration guards on ordinary construction, extraction, and processing starts prevent a later qualifying run from reproducing a completed run's finish-time identity. Zero-yield native extraction remains allowed but cannot meet mission thresholds. Process fingerprints also bind process configuration. Direct gameplay completion followed by an ordinary restart cannot reuse stale mission evidence. Administrative configuration changes can conservatively invalidate pending process evidence; avoid changing recipes during a live campaign without a migration policy.

Construction attribution is checked against the current construction's type, plan time, and finish time, plus current crew control at qualifying use. Completed evidence remains valid after buildings are transferred or demolished; unfinished action evidence cannot be finished using a different construction or another crew's building.

## Payments and launch integration

Native SWAY receipt flows work through the wrapper; no extra `run_system_with_missions_with_payment` entrypoint exists. The existing paid-Context Dispatcher boundary was tested, but this repository's Sway implementation has no verified producer for that callback. Starter actions therefore reject nonzero payment Context instead of inventing or trusting a sender.

`FillBuyOrder` uses Escrow-appended callback metadata and is not a wrapped capstone sale adapter in this release. Such purchases can still satisfy storage through a wrapped delivery receipt. Capstone completion requires a completed outgoing delivery or supported consumption; neither sale mechanism awards capstone credit. No mission adapter is added to Escrow or native trade execution.

Deployment tooling now distinguishes class-only campaign implementations (`isClass`) from gameplay systems (`isSystem`) and deployed contracts. Declare `StarterMissionCampaign`, register the generic systems and starter configurator, and upgrade `ExchangeCrew`, `InitializeArvadian`, `ConstructionStart`, `ExtractResourceStart`, and `ProcessProductsStart`. Register the chosen campaign with its declared implementation hash and eight missions, then configure the crew cutoff. Fund the Dispatcher reward balance. These activation calls are deliberately not automatic.

Clients must explicitly accept, submit qualifying actions via `MissionAction`, and claim rewards. Normal gameplay entrypoints remain available. Indexers receive existing gameplay and `ComponentUpdated` events; `TypeComponent` exposes the new state schema for ABI generation. No client or indexer repository was changed here.

## Validation

Final results (17 September 2026):

- `scarb test`: **446 passed, 0 failed**, including 34 starter/framework tests, 10 technical spikes, and 5 duration boundary tests.
- `scarb build`: production Sierra/CASM artifacts built successfully.
- Deployment-tool tests: **6 passed**.
- SDK duration-catalog checks: **3 passed** (238 process definitions and 10 construction recipes).
- Fresh-devnet transaction test: **passed**, deploying the actual framework, template, Dispatcher, gameplay, and SWAY classes.
- `git diff --check`: clean.

Commands:

```sh
scarb test
scarb build
node --test test/manager/*.test.js
node --test test/missions/duration-config.test.js
node --test test/missions/runtime.test.js
```

Cairo coverage includes all eight missions with real gameplay systems, all five SDK recipe pairs, exact payout totals, early evidence, sample/mass/batch boundaries, reversed routes, pending vs received goods, actual purchase receipts, rejection of seller assignments, exclusion of trade and purchased-delivery capstone credit, construction consumption, caller admission, immutable registration, claim replay, wrapper reentry, packed-page/subject/campaign isolation, ordinary crew exchange, contamination propagation, and unwrapped restart attacks.

The fresh-devnet test declares and deploys the real contracts and checks submitted reverting transactions, shared gameplay rollback, lock recovery, unfunded payout rollback, delegate payout, and claim replay. It uses its own local port and does not depend on the legacy devnet snapshot. The runtime checks use submitted reverted receipts, persisted state, and successful recovery transactions.

The repository's existing `npm run test-integration` was also attempted: its cached legacy contracts are absent on the devnet it starts, and its setup fails before the legacy assertions. This is separate from the fresh-deployment mission test.

## Duration guard review

The September 17 review audited all **238 installed SDK process definitions**, using the same setup/recipe conversion as `updateProcesses.js`. None serialized to an all-zero duration. All **225 processor-backed definitions** have positive setup time, and all **10 building construction recipes** have positive duration. This audits the repository's configured inputs; it is not a query of mutable live-network components.

Existing `ProcessType.is_set` already rejects a definition with both times zero as missing. Native processing also already requires a strictly positive recipe count. The timing helper rounds positive subsecond durations upward. The added guards are defensive checks on the calculated finish time and leave existing zero-yield extraction explicitly allowed.

Additional tests cover the existing empty-definition rejection, ordinary fractional processing, a co-located one-unit extraction, and subsecond rounding. The earlier spike continues to test that zero-yield extraction remains valid and can repeat its finish time; mission thresholds exclude that case.

### Explicit lifecycle events

In addition to `ComponentUpdated`, the framework emits these events from the Dispatcher address:

| Event | Data fields, in order |
| --- | --- |
| `MissionAccepted` | `campaign: felt252`, `subject: Entity`, `mission: u32` |
| `MissionCompleted` | `campaign: felt252`, `subject: Entity`, `mission: u32` |
| `MissionRewardClaimed` | `campaign: felt252`, `subject: Entity`, `mission: u32`, `recipient: ContractAddress`, `amount: u128` |

Their ABI definitions live in `ClaimMissionReward`. The event name selector is the sole event key; `Entity` serializes as its label and ID. Mission indices are zero-based, and reward amounts use SWAY's smallest units.

Acceptance and completion events are emitted only when their corresponding lifecycle bit changes. Acceptance can immediately emit completion when prior campaign evidence already satisfies the requirement. Claims emit after a successful SWAY transfer, recording the actual recipient. Reverted transactions retain none of these events. Existing component and native gameplay events remain available; no additional persistent storage is introduced.

The fresh-devnet runtime test checks receipt payloads and Dispatcher attribution, retained native gameplay events, duplicate-validation suppression, and absence of lifecycle events on reverted actions, repeated acceptance, failed payouts, and repeated claims.

### Activation constants and indexing

`ConfigureStarterMissions` emits the Dispatcher's existing `ConstantRegistered(name, value)` event for both `STARTER_MISSION_CUTOFF` and `STARTER_MISSION_CAMPAIGN`. The events originate from the Dispatcher and contain the values written by activation, so event replay can discover the active campaign and eligibility cutoff.

For a deployment activated before this fix, do not activate again. Either backfill the server from the two live constants, or have an administrator read those values and submit them unchanged through `Dispatcher.register_constant`. The latter emits new indexable events and preserves the existing campaign definition and progress. Updating the configurator alone does not retroactively emit events.


### Recipe changes during pending production

The pending production fingerprint is Poseidon over the serialized `Processor` component only. Its `running_process` field already identifies the process type. The recipe definition (`ProcessType`) is not included, so editing it does not by itself invalidate an existing mission-bound run. Native gameplay and mission output evaluation continue to use the applicable recipe configuration; this does not bypass native completion checks.

Construction, sampling, extraction, and delivery fingerprints likewise contain instance/run data, not entire type definitions. SDK/indexer fingerprint calculations must use the same serialized component fields as the deployed campaign implementation. This change requires a new campaign implementation hash; an already registered campaign remains pinned to its previous hash until explicitly updated. No pending fingerprint migration is needed when none exist.


### Explicit observer candidates

The current observer accepts explicit mission assignments from the SDK, grouped by campaign
and subject. Only selected missions are validated after shared evidence recording. Acceptance
and MissionValidate also validate the requested mission rather than scanning all eight.
Evidence keys, pending fingerprints, and lifecycle bits are unchanged. See
[mission-observer-integration.md](mission-observer-integration.md) for the candidate wire
format and the admin-only implementation upgrade procedure. No player progress migration
or re-enrollment is required.
