import ibis from '@influenceth/ibis';
import { shortString, hash } from 'starknet';

import { declareIfNeeded, loadOrDeployContract } from './utils.js';
import { estimateInvoke, hasEntrypoint, isDryRun, txOptions } from './dryRun.js';
import { isAcceptedBaseline, updateAcceptedBaseline } from './baseline.js';

const updateContract = async (contractName, networkName, account, options = {}) => {
  const { contracts } = ibis(networkName);
  const { classHash, contractAddress, contract, needsDeploy } = await loadOrDeployContract({
    contracts,
    contractName,
    networkName,
    account,
    options
  });

  const sierra = contracts.sierra(contractName);
  const computedHash = hash.computeContractClassHash(sierra);

  if (needsDeploy) return;

  // If the new classHash isn't the same as the old, upgrade the contract
  if (classHash !== computedHash) {
    if (isAcceptedBaseline({
      contracts,
      contractName,
      actualClassHash: classHash,
      computedClassHash: computedHash,
      options
    })) {
      return;
    }

    if (!hasEntrypoint(contract, 'upgrade')) {
      const message = `Contract ${contractName} class hash changed, but the deployed contract has no upgrade entrypoint`;
      if (isDryRun(options)) {
        console.log(`[dry-run] ${message}; manual migration or redeploy would be required`);
      } else {
        throw new Error(message);
      }
    } else {
      const declareResult = await declareIfNeeded({ contracts, contractName, account, options, classHash: computedHash });

      contract.connect(account);
      const call = contract.populate('upgrade', [ computedHash ]);
      if (isDryRun(options)) {
        if (!declareResult?.alreadyDeclared) {
          console.log(`[dry-run] ${contractName} upgrade: not estimated because class ${computedHash} is not declared yet`);
          console.log(`[dry-run] Contract ${contractName} would upgrade to hash: ${computedHash}`);
        } else {
          await estimateInvoke({ account, label: `${contractName} upgrade`, call, options });
          console.log(`[dry-run] Contract ${contractName} would upgrade to hash: ${computedHash}`);
        }
      } else {
        const res = await contract.upgrade(call.calldata, txOptions(options));
        await account.waitForTransaction(res.transaction_hash);
        updateAcceptedBaseline({ contracts, contractName, classHash: computedHash });
        console.log(`Contract ${contractName} upgraded to hash: ${computedHash}`);
      }
    }
  } else {
    console.log(`Contract ${contractName} already up to date`);
  }

  const dispatcher = contracts.deployed('Dispatcher');
  dispatcher.connect(account);
  let call = dispatcher.populate('contract', [ shortString.encodeShortString(contractName) ]);
  const registeredAddress = await dispatcher.contract(call.calldata);

  if (registeredAddress !== BigInt(contract.address)) {
    call = dispatcher.populate('register_contract', [ shortString.encodeShortString(contractName), contract.address ]);
    if (isDryRun(options)) {
      await estimateInvoke({ account, label: `${contractName} register_contract`, call, options });
      console.log(`[dry-run] Contract ${contractName} would register with Dispatcher as: ${contractAddress}`);
    } else {
      const res = await dispatcher.register_contract(call.calldata, txOptions(options));
      await account.waitForTransaction(res.transaction_hash);
      console.log(`Contract ${contractName} registered with Dispatcher as: ${contractAddress}`);
    }
  } else {
    console.log(`Contract ${contractName} already registered with Dispatcher`);
  }
};

export default updateContract;
