import fs from 'fs';
import path from 'path';
import ibis from '@influenceth/ibis';
import ContractConfig from '../lib/ContractConfig.js';

const combineAbis = async ({ network }) => {
  const { contracts } = ibis(network);
  const config = new ContractConfig(network);
  const abis = {};

  abis['Dispatcher'] = contracts.abi('Dispatcher');

  [...config.getContracts(), ...config.getClasses()].forEach(name => {
    abis[name] = contracts.abi(name);
  });

  // Roll up the systems
  const systems = {};
  const events = {};
  const types = {};

  config.getSystems().forEach(system => {
    const abi = contracts.abi(system);
    if (config.config[system].isObservationPolicy) {
      for (const entrypoint of ['before', 'after']) {
        if (!abi.some(a => a.type === 'function' && a.name === entrypoint)) {
          throw new Error(`Observation policy ${system} is missing its ${entrypoint} ABI`);
        }
      }
      abis[system] = abi;
    } else {
      const runAbi = abi.find(a => a.name === 'run' && a.type === 'function');
      if (!runAbi) throw new Error(`System ${system} is missing its run ABI`);
      systems[system] = { ...runAbi, name: system, inputs: runAbi.inputs.slice(0, -1) };
    }

    abi.filter(a => a.type === 'event' && a.kind === 'struct').forEach(event => {
      const name = event.name.split('::').pop();
      events[name] = { ...event, name };
    });

    abi.filter(a => a.type === 'struct').forEach(type => {
      types[type.name] = type;
    });
  });

  // Process components
  const components = {};
  const componentsAbi = contracts.abi('TypeComponent');
  componentsAbi.filter(a => a.type === 'struct' && a.name.includes('influence::components')).forEach(c => {
    components[c.name] = c;
  });

  const tempPath = path.resolve(process.cwd(), 'temp');
  fs.mkdirSync(tempPath, { recursive: true });
  fs.writeFileSync(path.resolve(tempPath, 'starknet_abis.json'), JSON.stringify(abis, null, 2));
  fs.writeFileSync(path.resolve(tempPath, 'starknet_events.json'), JSON.stringify(events, null, 2));
  fs.writeFileSync(path.resolve(tempPath, 'starknet_systems.json'), JSON.stringify(systems, null, 2));
  fs.writeFileSync(path.resolve(tempPath, 'starknet_components.json'), JSON.stringify(components, null, 2));
  fs.writeFileSync(path.resolve(tempPath, 'starknet_types.json'), JSON.stringify(types, null, 2));
};

export default combineAbis;
