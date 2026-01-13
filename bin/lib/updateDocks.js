import isEqual from 'lodash.isequal';
import { Dock } from '@influenceth/sdk';

const updateDocks = async (dispatcher, account) => {
  for await (const d of Object.values(Dock.TYPES)) {
    let existing;

    try {
      existing = await dispatcher.compileAndCall('run_system', {
        name: 'ReadComponent',
        calldata: [ 'DockType', 1n, BigInt(d.i) ]
      });
    } catch (e) {
      existing = [];
    }

    const compData = [ 2n, BigInt(d.cap), BigInt(d.delayPerShip) ];

    if (!isEqual(existing, compData)) {
      try {
        const res = await dispatcher.compileAndInvoke('run_system', {
          name: 'WriteComponent',
          calldata: [ 'DockType', 1n, BigInt(d.i), ...compData ]
        });

        await account.waitForTransaction(res.transaction_hash);
        console.log(`Updated DockType #${d.i}:`, d.name);
      } catch (e) {
        console.log(e);
        console.error(`Error updating DockType #${d.i}:`, d.name);
      }
    } else {
      console.log(`DockType #${d.i} already up to date:`, d.name);
    }
  }
};

export default updateDocks;