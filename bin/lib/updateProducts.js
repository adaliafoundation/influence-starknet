import isEqual from 'lodash.isequal';
import { Product } from '@influenceth/sdk';

const updateProducts = async (dispatcher, account) => {
  for await (const p of Object.values(Product.TYPES)) {
    let existing;

    try {
      existing = await dispatcher.compileAndCall('run_system', {
        name: 'ReadComponent',
        calldata: [ 'ProductType', 1n, BigInt(p.i) ]
      });
    } catch (e) {
      existing = [];
    }

    const compData = [ 2n, BigInt(p.massPerUnit), BigInt(p.volumePerUnit) ];

    if (!isEqual(existing, compData)) {
      try {
        const res = await dispatcher.compileAndInvoke('run_system', {
          name: 'WriteComponent',
          calldata: [ 'ProductType', 1n, BigInt(p.i), ...compData ]
        });

        console.log('Waiting for transaction: ', res.transaction_hash);
        await account.waitForTransaction(res.transaction_hash);
        console.log(`Updated ProductType #${p.i}:`, p.name);
      } catch (e) {
        console.log(e);
        console.error(`Error updating ProductType #${p.i}:`, p.name);
      }
    } else {
      console.log(`ProductType #${p.i} already up to date:`, p.name);
    }
  }
};

export default updateProducts;