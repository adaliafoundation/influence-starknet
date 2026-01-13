import isEqual from 'lodash.isequal';
import { DryDock } from '@influenceth/sdk';

const updateDryDocks = async (dispatcher, account) => {
  for await (const d of Object.values(DryDock.TYPES)) {
    let existing;

    try {
      existing = await dispatcher.compileAndCall('run_system', {
        name: 'ReadComponent',
        calldata: [ 'DryDockType', 1n, BigInt(d.i) ]
      });
    } catch (e) {
      existing = [];
    }

    const compData = [ 2n, BigInt(d.maxMass), BigInt(d.maxVolume) ];

    if (!isEqual(existing, compData)) {
      try {
        const res = await dispatcher.compileAndInvoke('run_system', {
          name: 'WriteComponent',
          calldata: [ 'DryDockType', 1n, BigInt(d.i), ...compData ]
        });

        await account.waitForTransaction(res.transaction_hash);
        console.log(`Updated DryDockType #${d.i}:`, d.name);
      } catch (e) {
        console.log(e);
        console.error(`Error updating DryDockType #${d.i}:`, d.name);
      }
    } else {
      console.log(`DryDockType #${d.i} already up to date:`, d.name);
    }
  }
};

export default updateDryDocks;