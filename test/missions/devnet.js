import fs from 'node:fs';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { setTimeout as delay } from 'node:timers/promises';
import { Account, RpcProvider, hash, config } from 'starknet';

export const call = (contractAddress, entrypoint, calldata = []) => ({ contractAddress, entrypoint, calldata: calldata.map(String) });

export async function startDevnet(t, port) {
  config.set('logLevel', 'FATAL');
  const node = spawn(process.env.STARKNET_DEVNET_BIN || 'starknet-devnet', [
    '--port', String(port), '--seed', '12345', '--initial-balance', '10000000000000000000000000'
  ]);
  let logs = '';
  node.stdout.on('data', data => { logs += data; });
  node.stderr.on('data', data => { logs += data; });
  t.after(() => node.kill());
  const url = `http://127.0.0.1:${port}/rpc`;
  const rpc = async (method, params) => {
    const response = await fetch(url, { method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ jsonrpc: '2.0', id: 1, method, params }) });
    const result = await response.json();
    if (result.error) throw new Error(JSON.stringify(result.error));
    return result.result;
  };
  let accounts;
  for (let attempt = 0; attempt < 100; attempt++) {
    if (node.exitCode !== null) throw new Error(`Devnet stopped: ${logs}`);
    try { accounts = await rpc('devnet_getPredeployedAccounts', {}); if (accounts) break; } catch { /* Wait for local startup. */ }
    await delay(250);
  }
  assert.ok(accounts, `Devnet did not start: ${logs}`);
  const provider = new RpcProvider({ nodeUrl: url, transactionRetryIntervalFallback: 100 });
  accounts = accounts.map(a => new Account({ provider, address: a.address, signer: a.private_key }));
  const admin = accounts[0];
  const invoke = async (account, calls) => {
    const tx = await account.execute(calls, { tip: 0 });
    return account.waitForTransaction(tx.transaction_hash, { retryInterval: 100 });
  };
  const classes = new Map();
  const declare = async (name, directory = 'target/dev') => {
    const key = `${directory}/${name}`;
    if (classes.has(key)) return classes.get(key);
    const artifact = suffix => JSON.parse(fs.readFileSync(`${directory}/contract_${name}.${suffix}.json`, 'utf8'));
    const contract = artifact('contract_class');
    const classHash = hash.computeContractClassHash(contract);
    const tx = await admin.declare({ contract, casm: artifact('compiled_contract_class') }, { tip: 0 });
    await admin.waitForTransaction(tx.transaction_hash, { retryInterval: 100 });
    classes.set(key, classHash);
    return classHash;
  };
  const deploy = async (name, args = [], directory) => {
    const result = await admin.deployContract({ classHash: await declare(name, directory), constructorCalldata: args.map(String) }, { tip: 0 });
    await admin.waitForTransaction(result.transaction_hash, { retryInterval: 100 });
    return result.contract_address;
  };
  const reverted = async (account, calls) => {
    const tx = await account.execute(calls, { tip: 0, resourceBounds: {
      l1_gas: { max_amount: 100000n, max_price_per_unit: 10n ** 15n },
      l1_data_gas: { max_amount: 100000n, max_price_per_unit: 10n ** 15n },
      l2_gas: { max_amount: 1000000000n, max_price_per_unit: 10n ** 12n }
    } });
    try { await account.waitForTransaction(tx.transaction_hash, { retryInterval: 100 }); } catch { /* Assert the submitted receipt. */ }
    const receipt = await provider.getTransactionReceipt(tx.transaction_hash);
    assert.equal(receipt.execution_status, 'REVERTED');
    return receipt;
  };
  return { accounts, provider, invoke, declare, deploy, reverted, rpc };
}
