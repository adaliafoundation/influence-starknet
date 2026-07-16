import ibis from '@influenceth/ibis';
import { hash } from 'starknet';

import { declareIfNeeded, loadOrDeployContract } from './utils.js';
import { estimateInvoke, isDryRun, txOptions } from './dryRun.js';
import { isAcceptedBaseline, updateAcceptedBaseline } from './baseline.js';

const updateDispatcher = async (networkName, account, options = {}) => {
  const contractName = 'Dispatcher';
  const { contracts } = ibis(networkName);
  const { classHash, contract: dispatcher, needsDeploy } = await loadOrDeployContract({
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

    const declareResult = await declareIfNeeded({ contracts, contractName, account, options, classHash: computedHash });

    dispatcher.connect(account);
    const call = dispatcher.populate('upgrade', [ computedHash ]);
    if (isDryRun(options)) {
      if (!declareResult?.alreadyDeclared) {
        console.log(`[dry-run] ${contractName} upgrade: not estimated because class ${computedHash} is not declared yet`);
        console.log(`[dry-run] Contract ${contractName} would upgrade to hash: ${computedHash}`);
        return;
      }

      await estimateInvoke({ account, label: `${contractName} upgrade`, call, options });
      console.log(`[dry-run] Contract ${contractName} would upgrade to hash: ${computedHash}`);
      return;
    }

    const res = await dispatcher.upgrade(call.calldata, txOptions(options));
    await account.waitForTransaction(res.transaction_hash);
    updateAcceptedBaseline({ contracts, contractName, classHash: computedHash });
    console.log(`Contract ${contractName} upgraded to hash: ${computedHash}`);
  } else {
    console.log(`Contract ${contractName} already up to date`);
  }
};

export default updateDispatcher;
