import ibis from '@influenceth/ibis';
import { shortString, hash } from 'starknet';
import { estimateDeclare, estimateInvoke, isDryRun, txOptions } from './dryRun.js';
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
    console.log(`System ${systemName} already declared with hash: ${registeredClassHash}`);
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

    console.log(`System ${systemName} class hash changed, registering...`);
    needsDeclare = true;
    needsRegister = true;
  }

  // If either the current class hash wasn't found or the new class hash is different, declare
  if (needsDeclare) {
    if (isDryRun(options)) {
      await estimateDeclare({
        contracts,
        contractName: systemName,
        account,
        options,
        classHash: computedClassHash
      });
    } else {
      try {
        const res = await contracts.declare(systemName, { account }, txOptions(options));
        if (res?.transaction_hash) {
          await account.waitForTransaction(res.transaction_hash);
        }
        console.log(`System ${systemName} declared with hash: ${computedClassHash}`);
        needsRegister = true;
      } catch (e) {
        if (e.message.includes('already declared')) {
          console.log(`System ${systemName} already declared`);
        } else {
          console.log(e);
          console.log(`Error declaring ${systemName} system`);
          return;
        }
      }
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
      await account.waitForTransaction(res.transaction_hash);
      updateAcceptedBaseline({ contracts, contractName: systemName, classHash: computedClassHash });
      console.log(`System ${systemName} registered with Dispatcher as: ${computedClassHash}`);
    } catch (e) {
      console.log(e);
      console.log(`Error registering ${systemName} system with Dispatcher`);
    }
  }
};

export default updateSystem;
