import { estimateDeclare, isDryRun, txOptions } from './dryRun.js';

const MAX_WAIT_ATTEMPTS = 3;

export const declareClass = async ({ contracts, contractName, account, options = {}, classHash }) => {
  if (isDryRun(options)) {
    return estimateDeclare({ contracts, contractName, account, options, classHash });
  }

  try {
    await account.getClass(classHash);
    console.log(`${contractName}: class already declared: ${classHash}`);
    return { alreadyDeclared: true };
  } catch (error) {
    if (error.code !== 28 && !error.isType?.('CLASS_HASH_NOT_FOUND')) throw error;
  }

  const result = await contracts.declare(contractName, { account }, txOptions(options));
  const txHash = result.transaction_hash;
  if (!txHash) {
    // Ibis also handles a class declared between our lookup and submission.
    await account.getClass(classHash);
    return { alreadyDeclared: true };
  }

  console.log(`${contractName}: declaration submitted: ${txHash}`);
  for (let attempt = 1; attempt <= MAX_WAIT_ATTEMPTS; attempt += 1) {
    try {
      const receipt = await account.waitForTransaction(txHash);
      if (receipt.execution_status === 'REVERTED') {
        throw new Error(`Declaration reverted: ${receipt.revert_reason || 'unknown reason'}`);
      }
      console.log(`${contractName}: declaration confirmed: ${classHash}`);
      return result;
    } catch (error) {
      const uncertain = /Transaction TTL|waitForTransaction timed-out/.test(error.message);
      if (uncertain) {
        try {
          await account.getClass(classHash);
          console.log(`${contractName}: class confirmed on-chain after wait failure: ${classHash}`);
          return result;
        } catch (lookupError) {
          if (lookupError.code !== 28 && !lookupError.isType?.('CLASS_HASH_NOT_FOUND')) {
            throw new Error(`${contractName}: cannot verify declaration ${txHash}`, { cause: lookupError });
          }
        }
      }

      if (!uncertain || attempt === MAX_WAIT_ATTEMPTS) {
        throw new Error(`${contractName}: declaration ${txHash} failed or remains unconfirmed; registration stopped`, {
          cause: error
        });
      }
      console.warn(`${contractName}: retrying confirmation of ${txHash} (${attempt + 1}/${MAX_WAIT_ATTEMPTS}); not resubmitting`);
    }
  }
};
