import ibis from '@influenceth/ibis';
import rates from '../../temp/adjustedRates.json' assert { type: 'json' };

const fixFeatures = async (network, account) => {
  const { contracts } = ibis(network);
  const dispatcher = contracts.deployed('Dispatcher');
  dispatcher.connect(account);
  let count = 0;

  for (let i = 0; i < rates.length; i++) {
    const { entity, rate, permitted } = rates[i];
    const useLot = await dispatcher.compileAndCall('run_system', {
      name: 'ReadComponent',
      calldata: [ 'Unique', 2n, 'UseLot', BigInt(entity.uuid) ]
    });

    if (useLot[1] !== BigInt(permitted.uuid)) {
      useLot[1] = BigInt(permitted.uuid);

      try {
        const res = await dispatcher.compileAndInvoke('run_system', {
          name: 'WriteComponent',
          calldata: [ 'Unique', 2n, 'UseLot', BigInt(entity.uuid), ...useLot ]
        });

        await account.waitForTransaction(res.transaction_hash);
        console.log('Fixed UseLot for agreement:', entity.uuid);
        count++;
      } catch (e) {
        console.error('Error fixing UseLot for agreement:', entity.uuid);
        i--;
      }
    }
  }

  console.log('Fixed', count, 'UseLots');
};

export default fixFeatures;