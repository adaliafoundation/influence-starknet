import fs from 'node:fs';
import path from 'node:path';
import { hash } from 'starknet';
import { missionDefinitions } from './lib/missionDefinitions.js';

const destination = path.resolve('target/missions');
fs.mkdirSync(destination, { recursive: true });
const contracts = {};
for (const name of missionDefinitions.contracts) {
  const file = `target/dev/contract_${name}.contract_class.json`;
  const contract = JSON.parse(fs.readFileSync(file, 'utf8'));
  fs.writeFileSync(path.join(destination, `${name}.abi.json`), JSON.stringify(contract.abi, null, 2) + '\n');
  contracts[name] = { classHash: hash.computeContractClassHash(contract), abi: `${name}.abi.json` };
}
fs.writeFileSync(path.join(destination, 'manifest.json'), JSON.stringify({ ...missionDefinitions, contracts }, null, 2) + '\n');
fs.copyFileSync('docs/mission-observer-integration.md', path.join(destination, 'README.md'));
fs.copyFileSync('bin/lib/missionObservation.js', path.join(destination, 'missionObservation.js'));
console.log(`Wrote SDK/server mission artifacts to ${destination}`);
