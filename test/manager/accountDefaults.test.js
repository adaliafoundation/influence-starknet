import assert from 'node:assert/strict';
import { test } from 'node:test';
import { Account, RpcProvider } from 'starknet';
import { applyAccountDefaults } from '../../bin/lib/accountDefaults.js';

const fixture = () => {
  const account = new Account({
    provider: new RpcProvider({ nodeUrl: 'http://localhost:5050/rpc', specVersion: '0.9.0' }),
    address: '0x123',
    signer: '0x456',
    cairoVersion: '1'
  });
  return applyAccountDefaults(account);
};

test('uses the advanced nonce even when latest state lags after declaration', async () => {
  const account = fixture();
  let currentNonce = '0x9b';
  account.channel.getNonceForAddress = async (address, block) => {
    assert.equal(address, account.address);
    return block === 'pre_confirmed' ? currentNonce : '0x9b';
  };

  assert.equal(await account.getNonceSafe(), 155n);
  currentNonce = '0x9c';
  assert.equal(await account.getNonceSafe(), 156n);
  assert.equal(await account.getNonce('latest'), '0x9b');
});

test('preserves explicit transaction nonces without querying the provider', async () => {
  const account = fixture();
  account.channel.getNonceForAddress = async () => assert.fail('unexpected nonce lookup');
  assert.equal(await account.getNonceSafe('0x42'), 66n);
});

test('preserves explicit block identifiers for nonce queries', async () => {
  const account = fixture();
  account.channel.getNonceForAddress = async (address, block) => {
    assert.equal(block, 1234);
    return '0x12';
  };
  assert.equal(await account.getNonce(1234), '0x12');
});
