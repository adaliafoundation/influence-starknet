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

export const loadOrDeployContract = async ({
  contracts,
  contractName,
  networkName,
  account,
  options = {}
}) => {
  let classHash;
  let contractAddress;
  let contract;

  try {
    classHash = contracts.classHash(contractName);
    contract = contracts.deployed(contractName);
    contractAddress = contract.address;
    console.log(`${contractName} already deployed`);
  } catch (e) {
    const res = await contracts.declareAndDeploy(
      contractName,
      { account, constructorArgs: parseConstructorArgs(contractName, account, networkName) },
      options
    );

    if (res.declare?.transaction_hash) {
      await account.waitForTransaction(res.declare.transaction_hash);
    }

    if (res.deploy?.transaction_hash && res.deploy.transaction_hash !== res.declare?.transaction_hash) {
      await account.waitForTransaction(res.deploy.transaction_hash);
    }

    classHash = res.declare.class_hash;
    contractAddress = res.deploy.address;
    contract = contracts.deployed(contractName);

    console.log(`Contract ${contractName} declared with hash: ${classHash}`);
    console.log(`Contract ${contractName} deployed at: ${contractAddress}`);
  }

  return { classHash, contractAddress, contract };
};

export const declareIfNeeded = async ({
  contracts,
  contractName,
  account,
  options = {},
  classHash
}) => {
  try {
    const res = await contracts.declare(contractName, { account }, options);
    await account.waitForTransaction(res.transaction_hash);
    console.log(`Contract ${contractName} declared with hash: ${classHash}`);
  } catch (e) {
    console.log(`Contract ${contractName} already declared with hash: ${classHash}`);
  }
};
