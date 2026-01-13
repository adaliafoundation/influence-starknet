import 'dotenv/config';
import fs from 'fs';
import path from 'path';
import { exec } from 'child_process';
import { shortString } from 'starknet';

export async function mochaGlobalSetup() {
  const sierraPath = process.env.SIERRA_COMPILER_PATH;

  if (!sierraPath) {
    throw new Error('SIERRA_COMPILER_PATH not set in .env');
  }

  // Spin up seeded devnet
  console.log('Starting seeded devnet...');
  global.devnet = exec(
    'starknet-devnet ' +
    '--timeout 5000 ' +
    `--sierra-compiler-path ${sierraPath} ` +
    '--load-path ./test/seeds/devnet.dump'
  );

  await new Promise(resolve => setTimeout(resolve, 5000));

  // Delete current contracts cache
  console.log('Seeding devnet contract cache...');
  fs.copyFileSync(
    path.resolve('test/seeds/devnet.ibis.contracts.json'),
    path.resolve('cache/devnet.ibis.contracts.json')
  );
};

export function mochaGlobalTeardown() {
  console.log('Cleaning up cached contracts and devnet...');
  fs.unlinkSync(path.resolve('cache/devnet.ibis.contracts.json'));
  process.kill(global.devnet.pid);
  process.exit();
};
