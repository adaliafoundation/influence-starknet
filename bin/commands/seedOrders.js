import ibis from '@influenceth/ibis';
import { shortString } from 'starknet';

// Original seed orders
const toSeed = [
  [ 1598369, 1597382 ],
  [ 1598369, 1596395 ],
  [ 1598369, 1595408 ],
  [ 1597759, 1593434 ],
  [ 1597759, 1592447 ],
  [ 1597759, 1591460 ],
  [ 1615648, 1610713 ],
  [ 1615648, 1608129 ],
  [ 1615648, 1607142 ],
  [ 1616025, 1613962 ],
  [ 1616025, 1612742 ],
  [ 1614428, 1614805 ],
  [ 1614428, 1614195 ],
  [ 1614428, 1615182 ],
  [ 1592769, 1590706 ],
  [ 1592769, 1591083 ],
  [ 1593989, 1595586 ],
  [ 1593989, 1597183 ],
  [ 1593989, 1598780 ],
  [ 1594976, 1601974 ],
  [ 1594976, 1602961 ],
  [ 449470, 448860 ],
  [ 449470, 448250 ],
  [ 449470, 446653 ],
  [ 450080, 454871 ],
  [ 450080, 453274 ],
  [ 450080, 451677 ],
  [ 464830, 456468 ],
  [ 464830, 462246 ],
  [ 464830, 469998 ],
  [ 448949, 443781 ],
  [ 448949, 448572 ],
  [ 452143, 453363 ],
  [ 452143, 452376 ],
  [ 452143, 447585 ],
  [ 1089343, 1085539 ],
  [ 1089343, 1088733 ],
  [ 1089343, 1091927 ],
  [ 1092304, 1088500 ],
  [ 1092304, 1091694 ],
  [ 1092304, 1094888 ],
  [ 1104148, 1100344 ],
  [ 1104148, 1106732 ],
  [ 1104148, 1109926 ]
];

const seedOrders = async (network, account) => {
  const { contracts } = ibis(network);
  const dispatcher = contracts.deployed('Dispatcher');
  dispatcher.connect(account);

  // Seed the orders
  const systemName = shortString.encodeShortString('SeedOrders');

  for (let i = 1; i <= toSeed.length; i++) {
    const call = dispatcher.populate('run_system', [ systemName, toSeed[i - 1] ]);

    try {
      const { transaction_hash } = await dispatcher.run_system(call.calldata);
      await account.waitForTransaction(transaction_hash);
      console.log('Seeded orders set:', i, 'with txHash:', transaction_hash);
    } catch (e) {
      console.error('Error seeding orders, retrying:', i);
      console.log(e);
      process.abort();
      i--;
    }
  }
};

export default seedOrders;