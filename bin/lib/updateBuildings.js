import isEqual from 'lodash.isequal';
import { Building } from '@influenceth/sdk';

const updateBuildings = async (dispatcher, account) => {
  for await (const b of Object.values(Building.TYPES)) {
    if (b.i === 0) continue; // skip the empty lot
    let existing;

    try {
      existing = await dispatcher.compileAndCall('run_system', {
        name: 'ReadComponent',
        calldata: [ 'BuildingType', 1n, BigInt(b.i) ]
      });
    } catch (e) {
      existing = [];
    }

    const compData = [ 3n, BigInt(b.processType), BigInt(b.siteSlot), BigInt(b.siteType) ];

    if (!isEqual(existing, compData)) {
      try {
        const res = await dispatcher.compileAndInvoke('run_system', {
          name: 'WriteComponent',
          calldata: [ 'BuildingType', 1n, BigInt(b.i), ...compData ]
        });

        await account.waitForTransaction(res.transaction_hash);
        console.log(`Updated BuildingType #${b.i}:`, b.name);
      } catch (e) {
        console.log(e);
        console.error(`Error updating BuildingType #${b.i}:`, b.name);
      }
    } else {
      console.log(`BuildingType #${b.i} already up to date:`, b.name);
    }
  }
};

export default updateBuildings;