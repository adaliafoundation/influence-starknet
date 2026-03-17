import ibis from '@influenceth/ibis';
import { shortString, hash } from 'starknet';

import { declareIfNeeded, loadOrDeployContract } from './utils.js';

const updateContract = async (contractName, networkName, account, options = {}) => {
  const { contracts } = ibis(networkName);
  const { classHash, contractAddress, contract } = await loadOrDeployContract({
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
    const res = await dispatcher.register_contract(call.calldata, options);
    await account.waitForTransaction(res.transaction_hash);
    console.log(`Contract ${contractName} registered with Dispatcher as: ${contractAddress}`);
  } else {
    console.log(`Contract ${contractName} already registered with Dispatcher`);
  }
};

export default updateContract;
