import assert from 'node:assert/strict';
import { test } from 'node:test';
import { declareClass } from '../../bin/lib/declareClass.js';

const missing = () => Object.assign(new Error('Class not found'), { code: 28 });
const ttl = () => new Error('Transaction TTL, evicted from the mempool, try to increase the tip');

const fixture = () => {
  const calls = { declarations: 0, waits: [] };
  return {
    calls,
    contractName: 'Example',
    classHash: '0x123',
    contracts: {
      declare: async () => {
        calls.declarations += 1;
        return { transaction_hash: '0x456' };
      }
    },
    account: {
      getClass: async () => { throw missing(); },
      waitForTransaction: async (hash) => {
        calls.waits.push(hash);
        if (calls.waits.length === 1) throw ttl();
        return { execution_status: 'SUCCEEDED' };
      }
    }
  };
};

test('retries confirmation using the original hash without resubmitting', async () => {
  const args = fixture();
  await declareClass(args);
  assert.equal(args.calls.declarations, 1);
  assert.deepEqual(args.calls.waits, ['0x456', '0x456']);
});

test('stops after bounded confirmation attempts and retains the hash', async () => {
  const args = fixture();
  let waits = 0;
  args.account.waitForTransaction = async () => { waits += 1; throw ttl(); };
  await assert.rejects(declareClass(args), /0x456.*registration stopped/);
  assert.equal(waits, 3);
  assert.equal(args.calls.declarations, 1);
});

test('recognizes a class that landed despite the wait error', async () => {
  const args = fixture();
  let lookups = 0;
  args.account.getClass = async () => { if (++lookups === 1) throw missing(); return {}; };
  await declareClass(args);
  assert.equal(args.calls.waits.length, 1);
});

test('does not submit when the class is already declared', async () => {
  const args = fixture();
  args.account.getClass = async () => ({});
  await declareClass(args);
  assert.equal(args.calls.declarations, 0);
});

test('does not treat RPC failures as a missing class', async () => {
  const args = fixture();
  args.account.getClass = async () => { throw new Error('RPC unavailable'); };
  await assert.rejects(declareClass(args), /RPC unavailable/);
  assert.equal(args.calls.declarations, 0);
});

test('does not retry reverted declarations', async () => {
  const args = fixture();
  let waits = 0;
  args.account.waitForTransaction = async () => { waits += 1; return { execution_status: 'REVERTED', revert_reason: 'invalid' }; };
  await assert.rejects(declareClass(args), (error) => error.cause?.message === 'Declaration reverted: invalid');
  assert.equal(waits, 1);
});
