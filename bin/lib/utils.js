import ContractConfig from './ContractConfig.js';

export const parseConstructorArgs = (contractName, account, network) => {
  const config = new ContractConfig(network);
  const args = config.config[contractName].constructorArgs;

  if (!args) return {};

  for (const [key, value] of Object.entries(args)) {
    if (value === '{CALLER}') args[key] = account.address;
  }

  return args;
};
