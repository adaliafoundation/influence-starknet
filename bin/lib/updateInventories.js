import isEqual from 'lodash.isequal';
import { Inventory } from '@influenceth/sdk';

const updateInventory = async (dispatcher, account) => {
  for await (const i of Object.values(Inventory.TYPES)) {
    let existing;

    try {
      existing = await dispatcher.compileAndCall('run_system', {
        name: 'ReadComponent',
        calldata: [ 'InventoryType', 1n, BigInt(i.i) ]
      });
    } catch (e) {
      existing = [];
    }

    const products = i.productConstraints ? Object.entries(i.productConstraints).map(([k, v]) => {
      return [BigInt(k), v ? BigInt(v) : 4294967295n ]
    }) : [];

    const compData = [
      i.massConstraint === Infinity ? 1125899906842623n : BigInt(i.massConstraint),
      i.volumeConstraint === Infinity ? 1125899906842623n : BigInt(i.volumeConstraint),
      i.modifiable ? 1n : 0n,
      BigInt(products.length),
      ...products
    ].flat();
    compData.unshift(BigInt(compData.length));

    if (!isEqual(existing, compData)) {
      try {
        const res = await dispatcher.compileAndInvoke('run_system', {
          name: 'WriteComponent',
          calldata: [ 'InventoryType', 1n, BigInt(i.i), ...compData ]
        });

        await account.waitForTransaction(res.transaction_hash);
        console.log(`Updated InventoryType #${i.i}:`, i.name);
      } catch (e) {
        console.log(e);
        console.error(`Error updating InventoryType #${i.i}:`, i.name);
      }
    } else {
      console.log(`InventoryType #${i.i} already up to date:`, i.name);
    }
  }
};

export default updateInventory;