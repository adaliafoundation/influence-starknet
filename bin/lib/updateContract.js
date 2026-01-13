import ibis from '@influenceth/ibis';
import { shortString, hash } from 'starknet';

import { parseConstructorArgs } from './utils.js';

const updateContract = async (contractName, networkName, account, options = {}) => {
  let classHash, contractAddress, contract;
  const { contracts } = ibis(networkName);

  try {
    classHash = contracts.classHash(contractName);
    contract = contracts.deployed(contractName);
    contractAddress = contract.address;
    console.log(`${contractName} already deployed`);
  } catch (e) {
    // If no classHash, declare and deploy contract
    const res = await contracts.declareAndDeploy(
      contractName,
      { account, constructorArgs: parseConstructorArgs(contractName, account, networkName) }
    );

    classHash = res.declare.class_hash;
    contractAddress = res.deploy.address;
    contract = contracts.deployed(contractName);

    console.log(`Contract ${contractName} declared with hash: ${classHash}`);
    console.log(`Contract ${contractName} deployed at: ${contractAddress}`);
  }

  const sierra = contracts.sierra(contractName);
  const computedHash = hash.computeContractClassHash(sierra);

  // If the new classHash isn't the same as the old, upgrade the contract
  if (classHash !== computedHash) {
    try {
      const res = await contracts.declare(contractName, { account });
      await account.waitForTransaction(res.transaction_hash);
      console.log(`Contract ${contractName} declared with hash: ${computedHash}`);
    } catch (e) {
      console.log(`Contract ${contractName} already declared with hash: ${computedHash}`);
    }

    contract.connect(account);
    const call = contract.populate('upgrade', [ computedHash ]);
    const res = await contract.upgrade(call.calldata, options);
    await account.waitForTransaction(res.transaction_hash);
    console.log(`Contract ${contractName} upgraded to hash: ${computedHash}`);
  } else {
    console.log(`Contract ${contractName} already up to date`);
  }

  const dispatcher = contracts.deployed('Dispatcher');
  dispatcher.connect(account);
  let call = dispatcher.populate('contract', [ shortString.encodeShortString(contractName) ]);
  const registeredAddress = await dispatcher.contract(call.calldata);

  if (registeredAddress !== BigInt(contract.address)) {
    call = dispatcher.populate('register_contract', [ shortString.encodeShortString(contractName), contract.address ]);
    const res = await dispatcher.register_contract(call.calldata);
    await account.waitForTransaction(res.transaction_hash);
    console.log(`Contract ${contractName} registered with Dispatcher as: ${contractAddress}`);
  } else {
    console.log(`Contract ${contractName} already registered with Dispatcher`);
  }
};

export default updateContract;