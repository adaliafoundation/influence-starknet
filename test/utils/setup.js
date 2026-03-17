import 'dotenv/config';
import fs from 'fs';
import path from 'path';
import { spawn } from 'child_process';
import * as starknet from 'starknet';

const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const waitForDevnetReady = async ({ timeoutMs = 15000 } = {}) => {
  const startedAt = Date.now();
  let lastError = '';

  while (Date.now() - startedAt < timeoutMs) {
    try {
      const response = await fetch('http://127.0.0.1:5050/rpc', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'starknet_blockNumber', params: [] })
      });
      const body = await response.json();
      if (response.ok && (body.result !== undefined || body.error !== undefined)) return;
    } catch (error) {
      lastError = error.message;
    }

    await wait(250);
  }

  throw new Error(`Timed out waiting for starknet-devnet readiness (${lastError || 'no response'})`);
};

export async function mochaGlobalSetup() {
  // Silence noisy, non-fatal starknet.js tip-stat analysis logs on fresh/devnet chains.
  starknet.config?.set?.('logLevel', process.env.STARKNET_LOG_LEVEL || 'FATAL');

  const devnetBin = process.env.STARKNET_DEVNET_BIN || 'starknet-devnet';
  const seed = process.env.STARKNET_DEVNET_SEED || '12345';
  const initialBalance = process.env.STARKNET_DEVNET_INITIAL_BALANCE || '10000000000000000000000000';

  // Spin up seeded devnet
  console.log('Starting seeded devnet...');
  const devnetArgs = [
    '--timeout', '5000',
    '--seed', seed,
    '--initial-balance', initialBalance,
    '--dump-path', './test/seeds/devnet.dump'
  ];

  const devnet = spawn(devnetBin, devnetArgs, { stdio: ['ignore', 'pipe', 'pipe'] });
  global.devnet = devnet;

  let devnetLogs = '';
  devnet.stdout.on('data', (chunk) => {
    devnetLogs += chunk.toString();
  });
  devnet.stderr.on('data', (chunk) => {
    devnetLogs += chunk.toString();
  });

  const exitPromise = new Promise((resolve) => {
    devnet.once('exit', (code, signal) => {
      resolve({ code, signal });
    });
  });

  const readinessResult = await Promise.race([
    waitForDevnetReady().then(() => ({ ready: true })),
    exitPromise.then(({ code, signal }) => ({ ready: false, code, signal }))
  ]);

  if (!readinessResult.ready) {
    const details = devnetLogs.trim() ? `\n\nstarknet-devnet logs:\n${devnetLogs.trim()}` : '';
    throw new Error(
      `starknet-devnet exited before becoming ready (code=${readinessResult.code}, signal=${readinessResult.signal})${details}`
    );
  }

  // Seed devnet contract cache
  console.log('Seeding devnet contract cache...');
  fs.copyFileSync(
    path.resolve('test/seeds/devnet.ibis.contracts.json'),
    path.resolve('cache/devnet.ibis.contracts.json')
  );
}

export function mochaGlobalTeardown() {
  console.log('Cleaning up cached contracts and devnet...');

  const cachePath = path.resolve('cache/devnet.ibis.contracts.json');
  if (fs.existsSync(cachePath)) {
    fs.unlinkSync(cachePath);
  }

  if (global.devnet?.pid && !global.devnet.killed) {
    process.kill(global.devnet.pid);
  }
}
