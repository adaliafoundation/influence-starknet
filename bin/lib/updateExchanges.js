import isEqual from 'lodash.isequal';
import { Exchange } from '@influenceth/sdk';

const updateExchanges = async (dispatcher, account) => {
  for await (const ex of Object.values(Exchange.TYPES)) {
    let existing;

    try {
      existing = await dispatcher.compileAndCall('run_system', {
        name: 'ReadComponent',
        calldata: [ 'ExchangeType', 1n, BigInt(ex.i) ]
      });
    } catch (e) {
      existing = [];
    }

    const compData = [ 1n, BigInt(ex.productCap) ];

    if (!isEqual(existing, compData)) {
      try {
        const res = await dispatcher.compileAndInvoke('run_system', {
          name: 'WriteComponent',
          calldata: [ 'ExchangeType', 1n, BigInt(ex.i), ...compData ]
        });

        await account.waitForTransaction(res.transaction_hash);
        console.log(`Updated ExchangeType #${ex.i}:`, ex.name);
      } catch (e) {
        console.log(e);
        console.error(`Error updating ExchangeType #${ex.i}:`, ex.name);
      }
    } else {
      console.log(`ExchangeType #${ex.i} already up to date:`, ex.name);
    }
  }
};

export default updateExchanges;