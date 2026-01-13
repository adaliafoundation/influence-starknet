import axios from 'axios';
import ibis from '@influenceth/ibis';
import { shortString } from 'starknet';

const SNAPSHOT_FILE = 'https://influence.infura-ipfs.io/ipfs/QmPjtFx2b8gx4kBEX3xZmCafmyWdfDj8UkNqfQGmFvtg4U';

const seedCrewmates = async (network, account) => {
  const { contracts } = ibis(network);
  const dispatcher = contracts.deployed('Dispatcher');
  dispatcher.connect(account);

  // Set minter role for Dispatcher
  const crewmate = contracts.deployed('Crewmate');
  crewmate.connect(account);
  const hasGrant = await crewmate.compileAndCall('has_grant', { account: dispatcher.address, role: 2 });

  if (!hasGrant) {
    const res = await crewmate.compileAndInvoke('add_grant', { account: dispatcher.address, role: 2 });
    await account.waitForTransaction(res.transaction_hash);
    console.log('Added minter role for Dispatcher');
  } else {
    console.log('Dispatcher already has minter role, skipping...');
  }

  // Seed the crewmates
  const toSeed = await parseSnapshot();
  const systemName = shortString.encodeShortString('SeedCrewmates');

  for (let i = 0; i < toSeed.length; i++) {
    const call = dispatcher.populate('run_system', [ systemName, toSeed[i] ]);

    try {
      const res = await dispatcher.run_system(call.calldata);
      await account.waitForTransaction(res.transaction_hash);
      console.log('Seeded crewmates set:', i + 1);
    } catch (e) {
      console.error('Error seeding crewmates, retrying:', i + 1);
      i--;
    }
  }
};

const parseSnapshot = async () => {
  const { data } = await axios.get(SNAPSHOT_FILE);
  const owned = data.filter(a => !!a.name);
  const chunkSize = 100;
  const toSeed = [];

  for (let i = 0; i < owned.length; i += chunkSize) {
    const toChunk = owned.slice(i, i + chunkSize);
    const chunk = [ toChunk.length ];
    toChunk.forEach(c => {
      chunk.push(c.i);
      chunk.push(c.name ? shortString.encodeShortString(c.name) : 0);
    });

    toSeed.push(chunk);
  }

  return toSeed;
};

export default seedCrewmates;