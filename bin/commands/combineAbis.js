import fs from 'fs';
import path from 'path';
import ibis from '@influenceth/ibis';
import ContractConfig from '../lib/ContractConfig.js';

const combineAbis = async ({ network }) => {
  const { contracts } = ibis(network);
  const config = new ContractConfig(network);
  const abis = {};

  abis['Dispatcher'] = contracts.abi('Dispatcher');

  config.getContracts().forEach(name => {
    abis[name] = contracts.abi(name);
  });

  // Write abi to json in temp folder
  const tempPath = path.resolve(process.cwd(), 'temp');
  if (!fs.existsSync(tempPath)) fs.mkdirSync(tempPath);
  fs.writeFileSync(path.resolve(tempPath, 'starknet_abis.json'), JSON.stringify(abis, null, 2));

  // Roll up the systems
  const systems = {};
  const events = {};
  const types = {};

  config.getSystems().forEach(system => {
    const runAbi = contracts.abi(system).find(a => a.name === 'run' && a.type === 'function');
    runAbi.name = system;
    runAbi.inputs.pop();
    systems[system] = runAbi;

    contracts.abi(system).filter(a => a.type === 'event' && a.kind === 'struct').forEach(event => {
      event.name = event.name.split('::').pop();
      events[event.name] = event;
    });

    contracts.abi(system).filter(a => a.type === 'struct').forEach(type => {
      types[type.name] = type;
    });
  });

  // Process components
  const components = {};
  const componentsAbi = contracts.abi('TypeComponent');
  componentsAbi.filter(a => a.type === 'struct' && a.name.includes('influence::components')).forEach(c => {
    components[c.name] = c;
  });

  fs.writeFileSync(path.resolve(tempPath, 'starknet_events.json'), JSON.stringify(events, null, 2));
  fs.writeFileSync(path.resolve(tempPath, 'starknet_systems.json'), JSON.stringify(systems, null, 2));
  fs.writeFileSync(path.resolve(tempPath, 'starknet_components.json'), JSON.stringify(components, null, 2));
  fs.writeFileSync(path.resolve(tempPath, 'starknet_types.json'), JSON.stringify(types, null, 2));
};

export default combineAbis;