import isEqual from 'lodash.isequal';
import { Ship } from '@influenceth/sdk';

const updateShips = async (dispatcher, account) => {
  for await (const s of Object.values(Ship.TYPES)) {
    let existing;

    try {
      existing = await dispatcher.compileAndCall('run_system', {
        name: 'ReadComponent',
        calldata: [ 'ShipType', 1n, BigInt(s.i) ]
      });
    } catch (e) {
      existing = [];
    }

    const compData = [
      13n,
      BigInt(s.cargoInventoryType || 0),
      BigInt(s.cargoSlot || 0),
      s.docking ? 1n : 0n,
      BigInt(s.exhaustVelocity || 0) * 2n ** 64n / 1000n,
      0n,
      BigInt(s.hullMass || 0),
      s.landing ? 1n : 0n,
      BigInt(s.processType || 0),
      BigInt(Number(1 / s.emergencyPropellantCap)),
      BigInt(s.propellantInventoryType || 0),
      BigInt(s.propellantSlot || 0),
      BigInt(s.propellantType || 0),
      BigInt(s.stationType || 0)
    ];

    if (!isEqual(existing, compData)) {
      try {
        const res = await dispatcher.compileAndInvoke('run_system', {
          name: 'WriteComponent',
          calldata: [ 'ShipType', 1n, BigInt(s.i), ...compData ]
        });

        await account.waitForTransaction(res.transaction_hash);
        console.log(`Updated ShipType #${s.i}:`, s.name);
      } catch (e) {
        console.log(e);
        console.error(`Error updating ShipType #${s.i}:`, s.name);
      }
    } else {
      console.log(`ShipType #${s.i} already up to date:`, s.name);
    }
  }
};

export default updateShips;