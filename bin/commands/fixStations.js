import ibis from '@influenceth/ibis';
import stations from '../../temp/stations.json' assert { type: 'json' };

const fixFeatures = async (network, account) => {
  const { contracts } = ibis(network);
  const dispatcher = contracts.deployed('Dispatcher');
  dispatcher.connect(account);
  let count = 0;

  for (let i = 0; i < stations.length; i++) {
    const { uuid, componentPop, actualPop } = stations[i];
    const station = await dispatcher.compileAndCall('run_system', {
      name: 'ReadComponent',
      calldata: [ 'Station', 1n, BigInt(uuid) ]
    });

    if (station[2] !== BigInt(componentPop)) {
      console.log('Skipping fixing station', uuid);
      continue;
    }

    if (station[2] !== BigInt(actualPop)) {
      station[2] = BigInt(actualPop);

      try {
        const res = await dispatcher.compileAndInvoke('run_system', {
          name: 'WriteComponent',
          calldata: [ 'Station', 1n, BigInt(uuid), ...station ]
        }, { maxFee: 10092904952012n });

        await account.waitForTransaction(res.transaction_hash);
        console.log('Fixed station for building:', uuid);
        count++;
      } catch (e) {
        console.error('Error fixing station for building:', uuid);
        i--;
      }
    }
  }

  console.log('Fixed', count, 'stations');
};

export default fixFeatures;