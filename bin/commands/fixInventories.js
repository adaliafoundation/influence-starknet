import ibis from '@influenceth/ibis';
import orders from '../../temp/orders.json' assert { type: 'json' };

const fixInventories = async (network, account) => {
  const { contracts } = ibis(network);
  const dispatcher = contracts.deployed('Dispatcher');
  dispatcher.connect(account);
  let count = 0;

  for (let i = 0; i < orders.length; i++) {
    const { storageEntity, storageSlot, mass, volume } = orders[i];
    const inventory = await dispatcher.compileAndCall('run_system', {
      name: 'ReadComponent',
      calldata: [ 'Inventory', 2n, BigInt(storageEntity.uuid), BigInt(storageSlot) ]
    });

    inventory[5] -= BigInt(mass); // mass
    inventory[6] -= BigInt(volume); // volume

    try {
      console.log(inventory);
      const res = await dispatcher.compileAndInvoke('run_system', {
        name: 'WriteComponent',
        calldata: [ 'Inventory', 2n, BigInt(storageEntity.uuid), BigInt(storageSlot), ...inventory ]
      });

      await account.waitForTransaction(res.transaction_hash);
      console.log('Fixed Inventory for:', storageEntity.uuid);
      count++;
    } catch (e) {
      console.error('Error fixing inventory for:', storageEntity.uuid);
      console.log(e);
      process.exit();
      i--;
    }
  }

  console.log('Fixed', count, 'inventories');
};

export default fixInventories;