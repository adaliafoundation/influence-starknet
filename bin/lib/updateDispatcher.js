import ibis from '@influenceth/ibis';
import { hash } from 'starknet';

import { parseConstructorArgs } from './utils.js';

const updateDispatcher = async (networkName, account, options = {}) => {
  let classHash, contractAddress, dispatcher;
  const { contracts } = ibis(networkName);

  try {
    classHash = contracts.classHash('Dispatcher');
    dispatcher = contracts.deployed('Dispatcher');
    contractAddress = dispatcher.address;
    console.log('Dispatcher already deployed');
  } catch (e) {
    // If no classHash, declare and deploy contract
    const res = await contracts.declareAndDeploy(
      'Dispatcher',
      { account, constructorArgs: parseConstructorArgs('Dispatcher', account, networkName) }
    );

    classHash = res.declare.class_hash;
    contractAddress = res.deploy.address;
    dispatcher = contracts.deployed('Dispatcher');

    console.log(`Contract ${'Dispatcher'} declared with hash: ${classHash}`);
    console.log(`Contract ${'Dispatcher'} deployed at: ${contractAddress}`);
  }

  const sierra = contracts.sierra('Dispatcher');
  const computedHash = hash.computeContractClassHash(sierra);

  // If the new classHash isn't the same as the old, upgrade the contract
  if (classHash !== computedHash) {
    let res = await contracts.declare('Dispatcher', { account });
    await account.waitForTransaction(res.transaction_hash);
    console.log(`Contract ${'Dispatcher'} declared with hash: ${computedHash}`);

    dispatcher.connect(account);
    const call = dispatcher.populate('upgrade', [ computedHash ]);
    res = await dispatcher.upgrade(call.calldata, options);
    await account.waitForTransaction(res.transaction_hash);
    console.log(`Contract ${'Dispatcher'} upgraded to hash: ${computedHash}`);
  } else {
    console.log(`Contract ${'Dispatcher'} already up to date`);
  }
};

export default updateDispatcher;