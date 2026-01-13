import isEqual from 'lodash.isequal';
import { Station } from '@influenceth/sdk';

const updateStations = async (dispatcher, account) => {
  for await (const s of Object.values(Station.TYPES)) {
    let existing;

    try {
      existing = await dispatcher.compileAndCall('run_system', {
        name: 'ReadComponent',
        calldata: [ 'StationType', 1n, BigInt(s.i) ]
      });
    } catch (e) {
      existing = [];
    }

    const compData = [ 4n, BigInt(s.cap), s.recruitment ? 1n : 0n, BigInt(Math.round(s.efficiency * 2 ** 32)), 0n ];

    if (!isEqual(existing, compData)) {
      try {
        const res = await dispatcher.compileAndInvoke('run_system', {
          name: 'WriteComponent',
          calldata: [ 'StationType', 1n, BigInt(s.i), ...compData ]
        });

        await account.waitForTransaction(res.transaction_hash);
        console.log(`Updated StationType #${s.i}:`, s.name);
      } catch (e) {
        console.log(e);
        console.error(`Error updating StationType #${s.i}:`, s.name);
      }
    } else {
      console.log(`StationType #${s.i} already up to date:`, s.name);
    }
  }
};

export default updateStations;