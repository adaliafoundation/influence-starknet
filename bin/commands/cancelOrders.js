import ibis from '@influenceth/ibis';

const toCancel = [
  // Round 1
  // [ 1n, 1n, 5n, 1598369n, 24n, 15052n, 5n, 1596395n, 2n, 1n, 1n ],
  // [ 1n, 1n, 5n, 449470n, 24n, 15052n, 5n, 448250n, 2n, 1n, 1n ],
  // [ 1n, 1n, 5n, 1089343n, 24n, 15052n, 5n, 1088733n, 2n, 1n, 1n ],
  // [ 1n, 1n, 5n, 1614428n, 44n, 1042n, 5n, 1615182n, 2n, 1n, 1n ],
  // [ 1n, 1n, 5n, 452143n, 44n, 1042n, 5n, 447585n, 2n, 1n, 1n ],
  // [ 1n, 1n, 5n, 1598369n, 180n, 29121n, 5n, 1595408n, 2n, 1n, 1n ],
  // [ 1n, 1n, 5n, 449470n, 180n, 29121n, 5n, 446653n, 2n, 1n, 1n ],
  // [ 1n, 1n, 5n, 1089343n, 180n, 29121n, 5n, 1091927n, 2n, 1n, 1n ]

  // Round 2
  // [ 1n, 1n, 5n, 1614428n, 69n, 58957n, 5n, 1614805n, 2n, 1n, 1n ],
  // [ 1n, 1n, 5n, 452143n, 69n, 58957n, 5n, 453363n, 2n, 1n, 1n ],
  // [ 1n, 1n, 5n, 1616025n, 41n, 151768n, 5n, 1612742n, 2n, 1n, 1n ],
  // [ 1n, 1n, 5n, 448949n, 41n, 151768n, 5n, 448572n, 2n, 1n, 1n ],
  // [ 1n, 1n, 5n, 1615648n, 56n, 26452n, 5n, 1608129n, 2n, 1n, 1n ],
  // [ 1n, 1n, 5n, 464830n, 56n, 26452n, 5n, 462246n, 2n, 1n, 1n ],
  // [ 1n, 1n, 5n, 1104148n, 56n, 26452n, 5n, 1106732n, 2n, 1n, 1n ],
  // [ 1n, 1n, 5n, 1614428n, 70n, 58964n, 5n, 1614195n, 2n, 1n, 1n ],
  // [ 1n, 1n, 5n, 452143n, 70n, 58964n, 5n, 452376n, 2n, 1n, 1n ],
  // [ 1n, 1n, 5n, 1615648n, 74n, 75786n, 5n, 1607142n, 2n, 1n, 1n ],
  // [ 1n, 1n, 5n, 464830n, 74n, 75786n, 5n, 469998n, 2n, 1n, 1n ],
  // [ 1n, 1n, 5n, 1104148n, 74n, 75786n, 5n, 1109926n, 2n, 1n, 1n ],
  // [ 1n, 1n, 5n, 1614428n, 101n, 59521n, 5n, 1614195n, 2n, 1n, 1n ],
  // [ 1n, 1n, 5n, 452143n, 101n, 59521n, 5n, 452376n, 2n, 1n, 1n ],
  // [ 1n, 1n, 5n, 1616025n, 104n, 522736000n, 5n, 1613962n, 2n, 1n, 1n ],
  // [ 1n, 1n, 5n, 448949n, 104n, 522736000n, 5n, 443781n, 2n, 1n, 1n ],
  // [ 1n, 1n, 5n, 1592769n, 125n, 161738n, 5n, 1591083n, 2n, 1n, 1n ],
  // [ 1n, 1n, 5n, 1615648n, 175n, 45565800n, 5n, 1610713n, 2n, 1n, 1n ],
  // [ 1n, 1n, 5n, 1615648n, 170n, 95710n, 5n, 1610713n, 2n, 1n, 1n ],
  // [ 1n, 1n, 5n, 1615648n, 129n, 326556n, 5n, 1610713n, 2n, 1n, 1n ],
  // [ 1n, 1n, 5n, 464830n, 175n, 45565800n, 5n, 456468n, 2n, 1n, 1n ],
  // [ 1n, 1n, 5n, 464830n, 170n, 95710n, 5n, 456468n, 2n, 1n, 1n ],
  // [ 1n, 1n, 5n, 464830n, 129n, 326556n, 5n, 456468n, 2n, 1n, 1n ],
  // [ 1n, 1n, 5n, 1104148n, 175n, 45565800n, 5n, 1100344n, 2n, 1n, 1n ],
  // [ 1n, 1n, 5n, 1104148n, 170n, 95710n, 5n, 1100344n, 2n, 1n, 1n ],
  // [ 1n, 1n, 5n, 1104148n, 129n, 326556n, 5n, 1100344n, 2n, 1n, 1n ],
  // [ 1n, 1n, 5n, 1592769n, 133n, 118193000n, 5n, 1590706n, 2n, 1n, 1n ],
  // [ 1n, 1n, 5n, 1594976n, 145n, 130616000n, 5n, 1601974n, 2n, 1n, 1n ],
  // [ 1n, 1n, 5n, 1594976n, 146n, 2704620000n, 5n, 1601974n, 2n, 1n, 1n ],
  // [ 1n, 1n, 5n, 1594976n, 147n, 4499470000n, 5n, 1601974n, 2n, 1n, 1n ],
  // [ 1n, 1n, 5n, 1594976n, 148n, 22353300000n, 5n, 1601974n, 2n, 1n, 1n ],
  // [ 1n, 1n, 5n, 1594976n, 150n, 15669100000n, 5n, 1602961n, 2n, 1n, 1n ],
  // [ 1n, 1n, 5n, 1594976n, 167n, 35959300000n, 5n, 1602961n, 2n, 1n, 1n ],
  // [ 1n, 1n, 5n, 1593989n, 235n, 8420100000n, 5n, 1595586n, 2n, 1n, 1n ]

  // Round 3
  // [ 1n, 1n, 5n, 1593989n, 237n, 1251590000n, 5n, 1595586n, 2n, 1n, 1n, [ 0x5deaa3d2, 0x763be3ea, 0x94d90420, 0xbb635f7c, 0xebe8615e, 0x128fd8084, 0x175e378d1, 0x1d6b2a3b6, 0x25092cc87, 0x2ea017a60, 0x3ab2a6473, 0x49e56e4e9, 0x5d07a2679, 0x751e1b757, 0x93713c92b, 0xb99e6ffab, 0xe9ae2b10c, 0x1262fa5c33, 0x1725bbf234, 0x1d240ec7c0 ]],
  // [ 1n, 1n, 5n, 1593989n, 238n, 766412000n, 5n, 1595586n, 2n, 1n, 1n, [ 0x398286f3, 0x48669041, 0x5b25a206, 0x72bf4da8, 0x907550d6, 0xb5dcb7d0, 0xe4f36f6e, 0x1203b6ccf, 0x16adcdd3b, 0x1c8d130c0, 0x23f19446a, 0x2d401a132, 0x38f78528a, 0x47b79066a, 0x5a495259b, 0x71a9f2ac0, 0x8f18255f4, 0xb42523a9f, 0xe2ca09d8b, 0x11d82be780 ]],
  // [ 1n, 1n, 5n, 1593989n, 239n, 211647000n, 5n, 1595586n, 2n, 1n, 1n, [ 0xfe1aba9, 0x13fe603f, 0x192ba74f, 0x1fb01445, 0x27e480aa, 0x3238c76b, 0x3f39b9ca, 0x4f989f12, 0x6434a579, 0x7e26c4f0, 0x9ed0b454, 0xc7efc218, 0xfbb4889d, 0x13ce0ca1a, 0x18eed05e1, 0x1f637c947, 0x2784140b6, 0x31bf6353a, 0x3ea0e74e4, 0x4ed83b160 ]],
  // [ 1n, 1n, 5n, 1593989n, 240n, 798379000n, 5n, 1597183n, 2n, 1n, 1n,  [ 0x3be89a57, 0x4b6ba39a, 0x5ef2e09c, 0x77888ba9, 0x967bcde7, 0xbd729895, 0xee801d66, 0x12c411820, 0x179ff6b8f, 0x1dbdef7b0, 0x25716064c, 0x2f2346297, 0x3b57cc452, 0x4ab557259, 0x5e0d60822, 0x76679f24d, 0x951012172, 0xbba8aeb93, 0xec3fa2c8a, 0x1296b5ace0 ]],
  // [ 1n, 1n, 5n, 1593989n, 241n, 12421100000n, 5n, 1597183n, 2n, 1n, 1n, [ 0x3a40d526a, 0x495624d66, 0x5c533f2b5, 0x743b033f0, 0x9253576c4, 0xb8368449a, 0xe7e90e13b, 0x123f536345, 0x16f8d9c49c, 0x1ceb8d72c0, 0x2468852680, 0x2dd5d6efb5, 0x39b4075f43, 0x48a4e1e456, 0x5b741676c0, 0x7322127738, 0x90f1a885a6, 0xb679418812, 0xe5b881403b, 0x12133867b80 ]],
  // [ 1n, 1n, 5n, 1593989n, 242n, 3032330000n, 5n, 1597183n, 2n, 1n, 1n, [ 0xe38a14a0, 0x11e7481a8, 0x168a027d5, 0x1c600308a, 0x23b8d95dc, 0x2cf8aed00, 0x389d9be62, 0x47465f621, 0x59bad272b, 0x70f68d6a0, 0x8e364c9f8, 0xb308d0b22, 0xe16418789, 0x11bc01dcdb, 0x165387cfa6, 0x1c1b6d34a1, 0x2362815e9b, 0x2c8bfb87aa, 0x3814c36ce2, 0x469a186240 ]],
  // [ 1n, 1n, 5n, 1593989n, 243n, 1687590000n, 5n, 1597183n, 2n, 1n, 1n, [ 0x7ea20f28, 0x9f6beb1e, 0xc8b32939, 0xfcaa8803, 0x13e167b6e, 0x19072e724, 0x1f8229db7, 0x27aab2bba, 0x31f001ee9, 0x3ede1cc60, 0x4f254952d, 0x63a372c24, 0x7d6ff9878, 0x9dea94b60, 0xc6ce0cc33, 0xfa47cfffd, 0x13b15a1f8c, 0x18caafa93e, 0x1f36012634, 0x274ad1fbc0 ]],
  // [ 1n, 1n, 5n, 1593989n, 244n, 260269000n, 5n, 1597183n, 2n, 1n, 1n, [ 0x1387aef8, 0x18963a83, 0x1ef3f6da, 0x26f7ae11, 0x310ea310, 0x3dc2631c, 0x4dc0191e, 0x61e1c65b, 0x7b39de91, 0x9b21e5d0, 0xc34cd559, 0xf5de48ad, 0x13587a3f3, 0x185accbf5, 0x1ea925db1, 0x26997ddfa, 0x30980f9b5, 0x3d2d1bdb8, 0x4d042af66, 0x60f52fa20 ]],
  // [ 1n, 1n, 5n, 1593989n, 245n, 199090000000n, 5n, 1598780n, 2n, 1n, 1n, [ 0x3a5b46a424, 0x49776f1eef, 0x5c7d281694, 0x746fc627ab, 0x9295c39d0c, 0xb88a234b92, 0xe85253e717, 0x12479be065b, 0x1703474e21f, 0x1cf8ae32500, 0x24790c14e97, 0x2deaa55cfeb, 0x39ce38f23fd, 0x48c5dbb5aa6, 0x5b9d9a1528f, 0x735655d8528, 0x91337429a25, 0xb6cc166b286, 0xe620c89f3c4, 0x121b6cdf7200 ]]
];

const start = 1;
const end = 20;

const cancelSeeded = async (network, account) => {
  const { contracts } = ibis(network);
  const dispatcher = contracts.deployed('Dispatcher');
  dispatcher.connect(account);

  for await (const c of toCancel) {
    for (let i = start - 1; i < end; i++) {
      const calldata = c.slice(0, -1);

      const marketData = await dispatcher.compileAndCall('run_system', {
        name: 'ReadComponent', calldata: [ 'Unique', 2n, 'LotUse', (calldata[3] * 2n ** 32n + 1n) * 2n ** 16n + 4n ]}
      );

      const warehouseData = await dispatcher.compileAndCall('run_system', {
        name: 'ReadComponent', calldata: [ 'Unique', 2n, 'LotUse', (calldata[7] * 2n ** 32n + 1n) * 2n ** 16n + 4n ]}
      );

      calldata[3] = marketData[1] / 2n ** 16n;
      calldata[7] = warehouseData[1] / 2n ** 16n;

      // Update price
      calldata[5] = c[11][i];

      try {
        const res = await dispatcher.compileAndInvoke('run_system', { name: 'CancelSellOrder', calldata });
        await account.waitForTransaction(res.transaction_hash);
        console.log(`Canceled Seeded:`, calldata);
      } catch (e) {
        console.log(e);
        console.error(`Error canceling Seeded:`, calldata);
      }
    }
  }
};

export default cancelSeeded;