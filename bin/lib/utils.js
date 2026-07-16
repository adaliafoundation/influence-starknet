import ContractConfig from './ContractConfig.js';
import { estimateDeclare, isDryRun, txOptions } from './dryRun.js';
import { updateAcceptedBaseline } from './baseline.js';
import { hash } from 'starknet';

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
    if (isDryRun(options)) {
      const sierra = contracts.sierra(contractName);
      classHash = options.computedClassHash || hash.computeContractClassHash(sierra);
      await estimateDeclare({ contracts, contractName, account, options, classHash });
      console.log(`[dry-run] Contract ${contractName} is not deployed; would deploy after declaration`);
      return { classHash, contractAddress: null, contract: null, needsDeploy: true };
    }

    const res = await contracts.declareAndDeploy(
      contractName,
      { account, constructorArgs: parseConstructorArgs(contractName, account, networkName) },
      txOptions(options)
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
    updateAcceptedBaseline({ contracts, contractName, classHash });

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
  if (isDryRun(options)) {
    return await estimateDeclare({ contracts, contractName, account, options, classHash });
  }

  try {
    const res = await contracts.declare(contractName, { account }, txOptions(options));
    await account.waitForTransaction(res.transaction_hash);
    console.log(`Contract ${contractName} declared with hash: ${classHash}`);
  } catch (e) {
    console.log(`Contract ${contractName} already declared with hash: ${classHash}`);
  }
};
