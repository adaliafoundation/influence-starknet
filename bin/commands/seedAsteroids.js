import axios from 'axios';
import ibis from '@influenceth/ibis';
import { shortString } from 'starknet';

const SNAPSHOT_FILE = 'https://influence.infura-ipfs.io/ipfs/QmdJ7kY74efg8PvcbZ7AzuVdfZAksUiAVUL7koznvYWUq4';
const MERKLE_ROOT = '0x5f8f9e0056d7d7492db18584c67838fd0307ce288c6b63f80e6252b45d1f383';

const seedAsteroids = async (network, account) => {
  const { contracts } = ibis(network);
  const dispatcher = contracts.deployed('Dispatcher');
  dispatcher.connect(account);

  // Set minter role for Dispatcher
  const asteroid = contracts.deployed('Asteroid');
  asteroid.connect(account);
  const hasGrant = await asteroid.compileAndCall('has_grant', { account: dispatcher.address, role: 2 });

  if (!hasGrant) {
    const res = await asteroid.compileAndInvoke('add_grant', { account: dispatcher.address, role: 2 });
    await account.waitForTransaction(res.transaction_hash);
    console.log('Added minter role for Dispatcher');
  } else {
    console.log('Dispatcher already has minter role, skipping...');
  }

  // Set the asteroid merkle root
  const constantName = shortString.encodeShortString('ASTEROID_MERKLE_ROOT');
  const currentRoot = await dispatcher.compileAndCall('constant', { name: constantName });

  if (currentRoot !== BigInt(MERKLE_ROOT)) {
    const res = await dispatcher.compileAndInvoke('register_constant', { name: constantName, value: MERKLE_ROOT });
    console.log('Waiting for merkle transaction:', res.transaction_hash);
    await account.waitForTransaction(res.transaction_hash);
    console.log('Registered asteroid merkle root:', MERKLE_ROOT);
  } else {
    console.log('Asteroid merkle root already set, skipping...');
  }

  // Seed the asteroids
  const toSeed = await parseSnapshot();
  const systemName = shortString.encodeShortString('SeedAsteroids');

  for (let i = 0; i < toSeed.length; i++) {
    const call = dispatcher.populate('run_system', [ systemName, toSeed[i] ]);

    try {
      const res = await dispatcher.run_system(call.calldata);
      console.log('Waiting for seeding transaction:', res.transaction_hash);
      await account.waitForTransaction(res.transaction_hash);
      console.log('Seeded asteroids set:', i + 1);
    } catch (e) {
      console.error('Error seeding asteroids, retrying:', i + 1);
      i--;
    }
  }
};

const parseSnapshot = async () => {
  const { data } = await axios.get(SNAPSHOT_FILE);
  const owned = data.filter(a => !!a.owner);
  const chunkSize = 100;
  const toSeed = [];

  for (let i = 0; i < owned.length; i += chunkSize) {
    const toChunk = owned.slice(i, i + chunkSize);
    const chunk = [ toChunk.length ];
    toChunk.forEach(a => {
      chunk.push(a.i);
      chunk.push(a.name ? shortString.encodeShortString(a.name) : 0);
    });

    toSeed.push(chunk);
  }

  return toSeed;
};

export default seedAsteroids;