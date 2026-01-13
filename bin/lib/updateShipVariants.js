import isEqual from 'lodash.isequal';
import { Ship } from '@influenceth/sdk';

const updateShipVariants = async (dispatcher, account) => {
  for await (const s of Object.values(Ship.VARIANT_TYPES)) {
    let existing;

    try {
      existing = await dispatcher.compileAndCall('run_system', {
        name: 'ReadComponent',
        calldata: [ 'ShipVariantType', 1n, BigInt(s.i) ]
      });
    } catch (e) {
      existing = [];
    }

    const shipType = BigInt(s.shipType ? s.shipType : 1);
    const evModifier = s.exhaustVelocityModifier ? s.exhaustVelocityModifier : 0;
    const compData = [ 3n, shipType, BigInt(Math.round(evModifier * 2 ** 32)), 0n ];

    if (!isEqual(existing, compData)) {
      try {
        const res = await dispatcher.compileAndInvoke('run_system', {
          name: 'WriteComponent',
          calldata: [ 'ShipVariantType', 1n, BigInt(s.i), ...compData ]
        });

        await account.waitForTransaction(res.transaction_hash);
        console.log(`Updated ShipVariantType #${s.i}:`, s.name);
      } catch (e) {
        console.log(e);
        console.error(`Error updating ShipVariantType #${s.i}:`, s.name);
      }
    } else {
      console.log(`ShipVariantType #${s.i} already up to date:`, s.name);
    }
  }
};

export default updateShipVariants;