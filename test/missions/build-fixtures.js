import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

const root = process.cwd();
const directory = path.join(root, 'temp/mission-runtime-fixtures');
fs.mkdirSync(directory, { recursive: true });
fs.cpSync(path.join(root, 'src'), path.join(directory, 'src'), { recursive: true });
for (const file of ['Scarb.toml', 'Scarb.lock']) fs.copyFileSync(path.join(root, file), path.join(directory, file));
if (!fs.existsSync(path.join(directory, 'vendor'))) fs.symlinkSync(path.join(root, 'vendor'), path.join(directory, 'vendor'));
fs.copyFileSync('src/test/mocks.cairo', path.join(directory, 'src/runtime_mocks.cairo'));
fs.copyFileSync('test/missions/runtime-fixtures.cairo', path.join(directory, 'src/mission_runtime_fixture.cairo'));
fs.appendFileSync(path.join(directory, 'src/lib.cairo'), '\nmod runtime_mocks;\nmod mission_runtime_fixture;\n');
execFileSync('scarb', ['build'], { cwd: directory, stdio: 'inherit' });
