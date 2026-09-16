import ibis from '@influenceth/ibis';
import { shortString, hash } from 'starknet';
import { estimateDeclare, estimateInvoke, isDryRun, recordDryRunSystem, txOptions } from './dryRun.js';
import { declareClass } from './declareClass.js';
import { isAcceptedBaseline, updateAcceptedBaseline } from './baseline.js';

const updateSystem = async (systemName, networkName, account, options = {}) => {
  let registeredClassHash, computedClassHash, needsDeclare, needsRegister;
  const { contracts } = ibis(networkName);
  const dispatcher = contracts.deployed('Dispatcher');

  // Make sure the current class hash is declared
  try {
    let call = dispatcher.populate('system', [ shortString.encodeShortString(systemName) ]);
    registeredClassHash = '0x' + BigInt(await dispatcher.system(call.calldata)).toString(16).padStart(64, '0');
    await account.getClass(registeredClassHash);
    console.log(`System ${systemName} currently registered with hash: ${registeredClassHash}`);
  } catch (e) {
    // If it wasn't found, we need to declare
    console.log(`System ${systemName} not declared, declaring...`);
    needsDeclare = true;
  }

  // Calculate the new class hash
  const sierra = contracts.sierra(systemName);
  computedClassHash = hash.computeContractClassHash(sierra);

  // If the registered and computed hashes are unequal, need to register
  if (!registeredClassHash || BigInt(registeredClassHash) !== BigInt(computedClassHash)) {
    if (isAcceptedBaseline({
      contracts,
      contractName: systemName,
      actualClassHash: registeredClassHash,
      computedClassHash,
      options
    })) {
      return;
    }

    console.log(`System ${systemName} class hash changed; declaration and registration required`);
    needsDeclare = true;
    needsRegister = true;
  }

  // If either the current class hash wasn't found or the new class hash is different, declare
  if (needsDeclare) {
    recordDryRunSystem(options, systemName);

    if (isDryRun(options)) {
      await estimateDeclare({
        contracts,
        contractName: systemName,
        account,
        options,
        classHash: computedClassHash
      });
    } else {
      await declareClass({ contracts, contractName: systemName, account, options, classHash: computedClassHash });
      needsRegister = true;
    }
  }

  // If the system was declared or the class hash changed, register with the Dispatcher
  if (needsRegister) {
    dispatcher.connect(account);
    const call = dispatcher.populate('register_system', [ shortString.encodeShortString(systemName), computedClassHash ]);

    try {
      if (isDryRun(options)) {
        await estimateInvoke({ account, label: `${systemName} register_system`, call, options });
        console.log(`[dry-run] System ${systemName} would register with Dispatcher as: ${computedClassHash}`);
        return;
      }

      const res = await dispatcher.register_system(call.calldata, txOptions(options));
      console.log(`${systemName}: registration submitted: ${res.transaction_hash}`);
      const receipt = await account.waitForTransaction(res.transaction_hash);
      if (receipt.execution_status === 'REVERTED') throw new Error(receipt.revert_reason || 'Registration reverted');
      updateAcceptedBaseline({ contracts, contractName: systemName, classHash: computedClassHash });
      console.log(`System ${systemName} registered with Dispatcher as: ${computedClassHash}`);
    } catch (e) {
      throw new Error(`Error registering ${systemName} system with Dispatcher`, { cause: e });
    }
  }
};

export default updateSystem;
