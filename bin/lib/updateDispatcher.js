import ibis from '@influenceth/ibis';
import { hash } from 'starknet';

import { declareIfNeeded, loadOrDeployContract } from './utils.js';

const updateDispatcher = async (networkName, account, options = {}) => {
  const contractName = 'Dispatcher';
  const { contracts } = ibis(networkName);
  const { classHash, dispatcher } = await loadOrDeployContract({
    contracts,
    contractName,
    networkName,
    account,
    options
  });

  const sierra = contracts.sierra(contractName);
  const computedHash = hash.computeContractClassHash(sierra);

  // If the new classHash isn't the same as the old, upgrade the contract
  if (classHash !== computedHash) {
    await declareIfNeeded({ contracts, contractName, account, options, classHash: computedHash });

    dispatcher.connect(account);
    const call = dispatcher.populate('upgrade', [ computedHash ]);
    const res = await dispatcher.upgrade(call.calldata, options);
    await account.waitForTransaction(res.transaction_hash);
    console.log(`Contract ${contractName} upgraded to hash: ${computedHash}`);
  } else {
    console.log(`Contract ${contractName} already up to date`);
  }
};

export default updateDispatcher;
