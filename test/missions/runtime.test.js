import { observeMissionAction } from '../../bin/lib/missionObservation.js';
import { Entity, Building, Ship } from '@influenceth/sdk';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { shortString, hash } from 'starknet';
import { startDevnet, call } from './devnet.js';

// Fresh deployments: these tests do not depend on the legacy seeded devnet dump.
test('starter mission transactions preserve attribution and roll back failed actions and payouts', { timeout: 600000 }, async (t) => {
  const { accounts: [admin, player, recipientAccount], provider, declare, deploy, invoke, reverted: submitReverted } = await startDevnet(t, 5051);
  const recipient = recipientAccount.address;
  const felt = shortString.encodeShortString;
  const dispatcher = await deploy('Dispatcher', [admin.address]);
  const token = await deploy('Sway', [felt('SWAY'), felt('SWAY'), 6, admin.address]);

  const system = (name, data) => call(dispatcher, 'run_system', [felt(name), data.length, ...data]);
  for (const name of ['WriteComponent', 'ReadComponent', 'RegisterMissionCampaign', 'ConfigureStarterMissions',
    'AcceptMission', 'MissionObserver', 'MissionValidate', 'ReadMissionState', 'ClaimMissionReward', 'ConstructionPlan']) {
    await invoke(admin, call(dispatcher, 'register_system', [felt(name), await declare(name)]));
  }
  const template = await declare('StarterMissionCampaign');
  const campaign = felt('StarterRuntime');
  await invoke(admin, system('RegisterMissionCampaign', [campaign, template, 8]));
  const activation = await invoke(admin, system('ConfigureStarterMissions', [campaign, 100]));
  const constants = activation.events.filter((event) =>
    BigInt(event.from_address) === BigInt(dispatcher)
      && BigInt(event.keys[0]) === BigInt(hash.getSelectorFromName('ConstantRegistered')));
  assert.deepEqual(constants.map((event) => event.keys.map(BigInt)), [
    [BigInt(hash.getSelectorFromName('ConstantRegistered'))],
    [BigInt(hash.getSelectorFromName('ConstantRegistered'))]
  ]);
  assert.deepEqual(constants.map((event) => event.data.map(BigInt)), [
    [BigInt(felt('STARTER_MISSION_CUTOFF')), 100n],
    [BigInt(felt('STARTER_MISSION_CAMPAIGN')), BigInt(campaign)]
  ]);
  for (const event of constants) {
    const stored = await provider.callContract(call(dispatcher, 'constant', [event.data[0]]));
    assert.equal(BigInt(stored[0]), BigInt(event.data[1]));
  }
  await invoke(admin, call(dispatcher, 'register_contract', [felt('Sway'), token]));
  const packedCrew = BigInt(Entity.packEntity({ label: Entity.IDS.CREW, id: 101 }));
  const packedAsteroid = BigInt(Entity.packEntity({ label: Entity.IDS.ASTEROID, id: 1 }));
  const lotId = (1n << 32n) + 1n;

  const write = async (name, path, data) => invoke(admin, system('WriteComponent', [felt(name), path.length, ...path, data.length, ...data]));

  const crewData = (delegate) => [delegate, 1, 101, 0, 0, 0, 0, 0, 0, 0, 0];
  await write('Crew', [packedCrew], crewData(player.address));
  await write('Location', [packedCrew], [Entity.IDS.LOT, lotId]);
  await write('Ship', [packedCrew], [Ship.IDS.ESCAPE_MODULE, Ship.STATUSES.DISABLED, 0, Ship.VARIANTS.STANDARD, 0, 0, 0, 0, 0, 0, 0]);
  await write('Control', [packedAsteroid], [Entity.IDS.CREW, 101]);
  const warehouse = Building.TYPES[Building.IDS.WAREHOUSE];
  await write('BuildingType', [warehouse.i], [warehouse.processType, warehouse.siteSlot, warehouse.siteType]);
  const assignment = [campaign, Entity.IDS.CREW, 101, 0];
  const missionEvents = (receipt, name) => receipt.events
    .filter((event) => BigInt(event.from_address) === BigInt(dispatcher)
      && BigInt(event.keys[0]) === BigInt(hash.getSelectorFromName(name)))
    .map((event) => event.data.map(BigInt));

  const accepted = await invoke(player, system('AcceptMission', assignment));
  assert.deepEqual(missionEvents(accepted, 'MissionAccepted'), [assignment.map(BigInt)]);
  assert.deepEqual(missionEvents(accepted, 'MissionCompleted'), []);

  const read = async () => {
    const values = await provider.callContract(system('ReadMissionState', [...assignment, 0]));
    return values.slice(1).map(BigInt); // Dispatcher returns a Span.
  };
  assert.deepEqual(await read(), [1n, 0n, 0n, 0n]);

  const plan = (kind) => {
    const calldata = [kind, Entity.IDS.LOT, lotId, Entity.IDS.CREW, 101];
    return observeMissionAction({ dispatcher, account: player.address, system: 'ConstructionPlan', calldata,
      candidates: [{ campaign, subject: { label: Entity.IDS.CREW, id: 101 }, mission: 0 }],
      executionCalls: [system('ConstructionPlan', calldata)] });
  };
  const reverted = async (account, invocation) => {
    const receipt = await submitReverted(account, invocation);
    for (const name of ['MissionAccepted', 'MissionCompleted', 'MissionRewardClaimed', 'ConstantRegistered']) {
      assert.deepEqual(missionEvents(receipt, name), []);
    }
    // Assert persisted state and successful recovery, in addition to the receipt.
    return receipt;
  };
  await reverted(player, system('ConfigureStarterMissions', [campaign, 0]));
  await reverted(admin, system('ConfigureStarterMissions', [campaign, 0]));
  const cutoff = await provider.callContract(call(dispatcher, 'constant', [felt('STARTER_MISSION_CUTOFF')]));
  assert.equal(BigInt(cutoff[0]), 100n);
  // Missing refinery configuration fails after native gameplay has written the building and lot-use records.
  await reverted(player, plan(Building.IDS.REFINERY));
  assert.deepEqual(await read(), [1n, 0n, 0n, 0n]);
  // Same lot succeeds, proving gameplay writes and the execution lock rolled back.
  const completed = await invoke(player, plan(Building.IDS.WAREHOUSE));
  assert.deepEqual(missionEvents(completed, 'MissionCompleted'), [assignment.map(BigInt)]);
  assert.deepEqual(missionEvents(completed, 'MissionAccepted'), []);
  assert.ok(completed.events.some((event) =>
    BigInt(event.from_address) === BigInt(dispatcher)
      && BigInt(event.keys[0]) === BigInt(hash.getSelectorFromName('ConstructionPlanned'))));
  const validated = await invoke(player, system('MissionValidate', [...assignment, 0]));
  assert.deepEqual(missionEvents(validated, 'MissionCompleted'), []);
  await reverted(player, system('AcceptMission', assignment));
  assert.deepEqual(await read(), [1n, 1n, 0n, 1n]);
  await reverted(player, system('ClaimMissionReward', assignment)); // Treasury is empty.
  assert.deepEqual(await read(), [1n, 1n, 0n, 1n]);
  await write('Crew', [packedCrew], crewData(recipient));
  await invoke(admin, call(token, 'add_grant', [admin.address, 2]));
  await invoke(admin, call(token, 'mint', [dispatcher, 5000000000n, 0]));
  const claimed = await invoke(player, system('ClaimMissionReward', assignment));
  assert.deepEqual(missionEvents(claimed, 'MissionRewardClaimed'), [
    [...assignment.map(BigInt), BigInt(recipient), 5000000000n]
  ]);
  assert.deepEqual(missionEvents(claimed, 'MissionCompleted'), []);
  assert.deepEqual(await read(), [1n, 1n, 1n, 1n]);
  const balance = await provider.callContract(call(token, 'balance_of', [recipient]));
  assert.equal(BigInt(balance[0]), 5000000000n);
  await reverted(player, system('ClaimMissionReward', assignment));
  assert.deepEqual(await read(), [1n, 1n, 1n, 1n]);
});
