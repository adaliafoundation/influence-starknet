import { test } from 'node:test';
import assert from 'node:assert/strict';
import { hash, shortString } from 'starknet';
import { observeMissionAction, escrowWithdrawalArguments, encodeMissionTargets } from '../../bin/lib/missionObservation.js';
import { missionDefinitions } from '../../bin/lib/missionDefinitions.js';

test('observation commits to the complete Escrow callback, not its partial hook', () => {
  const nativeArguments = [1, 2, 3, 4, 5];
  const calldata = escrowWithdrawalArguments({ nativeArguments, caller: '0x123', token: '0x456',
    withdrawals: [{ recipient: '0x789', amount: (1n << 128n) + 7n }, { recipient: '0xabc', amount: 0n }] });
  assert.deepEqual(calldata.map(BigInt), [1n,2n,3n,4n,5n,0x123n,2n,0x456n,2n,0x789n,7n,1n,0xabcn,0n,0n]);
  const executionCalls = [{ contractAddress: '0x999', entrypoint: 'withdraw', calldata: ['1'] }];
  const calls = observeMissionAction({ dispatcher: '0x100', account: '0x123', system: 'FillBuyOrder',
    calldata, executionCalls, expectedCaller: '0x999', candidates: [{ campaign: 'Colony', subject: { label: 1, id: 104 }, mission: 3 }] });
  assert.equal(calls[0].calldata[1], shortString.encodeShortString('FillBuyOrder'));
  assert.equal(calls[0].calldata[2], hash.computePoseidonHashOnElements(calldata));
  assert.equal(calls[0].calldata[3], '0x999');
  assert.equal(calls[1], executionCalls[0]);
  assert.equal(calls[2].entrypoint, 'end_observation');
  assert.notEqual(hash.computePoseidonHashOnElements(nativeArguments), calls[0].calldata[2]);
});

test('reward manifest has five ordered rewards totaling 1,500,000 SWAY', () => {
  assert.deepEqual(missionDefinitions.colonization.missions.map(({ id }) => id), [0,1,2,3,4]);
  assert.equal(missionDefinitions.colonization.missions.reduce((sum, { reward }) => sum + BigInt(reward), 0n), 1500000000000n);
});


test('mission candidates are grouped and deduplicated without changing native calls', () => {
  const assignment = { campaign: 'Colony', subject: { label: 1, id: 104 } };
  const targets = encodeMissionTargets([3, 4, 3].map(mission => ({ ...assignment, mission })));
  assert.deepEqual(targets.map(BigInt), [BigInt(shortString.encodeShortString('Colony')), 1n + 104n * 65536n + 24n * (1n << 80n)]);
  assert.throws(() => encodeMissionTargets([]), /required/);
  assert.throws(() => encodeMissionTargets([{ ...assignment, mission: 32 }]), /index/);
  assert.throws(() => encodeMissionTargets(Array.from({ length: 9 }, (_, i) => ({ ...assignment, subject: { label: 1, id: i + 1 }, mission: 0 }))), /Too many/);
});
