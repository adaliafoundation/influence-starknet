import ibis from '@influenceth/ibis';
import { Entity, Asteroid } from '@influenceth/sdk';
import { expect } from 'chai';
import { hash, shortString, uint256, num, Contract } from 'starknet';
import { assertReverts, readComponent } from './utils/index.js';

const L1_ASTEROID_BRIDGE_ADDRESS = '0xc662c410C0ECf747543f5bA90660f6ABeBD9C8c4';
const L1_CREWMATE_BRIDGE_ADDRESS = '0xF167FF3b2F18985e49DB5082C6032A3769D9f0b0';
const ETHER_ADDRESS = '0x49D36570D4E46F48E99674BD3FCC84644DDD6B96F7C741B1562B82F9E004DC7';
const MERKLE_ROOT = '0x5f8f9e0056d7d7492db18584c67838fd0307ce288c6b63f80e6252b45d1f383';

describe('Limited Release functionality', function () {
  let admin, player1, player2, dispatcher, asteroid, crewmate, crew;
  const { accounts, contracts, provider } = ibis('devnet');

  before(async function() {
    admin = await accounts.predeployedAccount(0);
    player1 = await accounts.predeployedAccount(1);
    player2 = await accounts.predeployedAccount(2);

    dispatcher = contracts.deployed('Dispatcher');
    dispatcher.connect(admin);

    // Setup asteroids
    asteroid = contracts.deployed('Asteroid');
    asteroid.connect(admin);
    let res = await asteroid.compileAndInvoke('set_l1_bridge_address', { address: L1_ASTEROID_BRIDGE_ADDRESS });
    await admin.waitForTransaction(res.transaction_hash);
    res = await asteroid.compileAndInvoke('add_grant', { account: dispatcher.address, role: 2 });
    await admin.waitForTransaction(res.transaction_hash);

    // Setup crewmates
    crewmate = contracts.deployed('Crewmate');
    crewmate.connect(admin);
    res = await crewmate.compileAndInvoke('set_l1_bridge_address', { address: L1_CREWMATE_BRIDGE_ADDRESS });
    await admin.waitForTransaction(res.transaction_hash);
    res = await crewmate.compileAndInvoke('add_grant', { account: dispatcher.address, role: 2 });
    await admin.waitForTransaction(res.transaction_hash);

    // Setup crew
    crew = contracts.deployed('Crew');
    crew.connect(admin);
    res = await crew.compileAndInvoke('add_grant', { account: dispatcher.address, role: 2 });
    await admin.waitForTransaction(res.transaction_hash);

    // Run SeedHabitat script
    res = await dispatcher.compileAndInvoke('run_system', {
      name: shortString.encodeShortString('SeedHabitat'), calldata: []
    });

    await admin.waitForTransaction(res.transaction_hash);

    // Seed asteroids
    res = await dispatcher.compileAndInvoke('register_constant', {
      name: shortString.encodeShortString('ASTEROID_MERKLE_ROOT'), value: MERKLE_ROOT
    });

    await admin.waitForTransaction(res.transaction_hash);
    res = await dispatcher.compileAndInvoke('run_system', {
      name: shortString.encodeShortString('SeedAsteroids'),
      calldata: [
        3n,
        1n, shortString.encodeShortString('Adalia Prime'),
        104n, 0n,
        102406n, 0n // SWAY sale asteroid
      ]
    });

    await admin.waitForTransaction(res.transaction_hash);

    // Seed crewmates
    res = await dispatcher.compileAndInvoke('run_system', {
      name: shortString.encodeShortString('SeedCrewmates'),
      calldata: [
        3n,
        1n, shortString.encodeShortString('Crewmate 1'),
        2n, shortString.encodeShortString('Crewmate 2'),
        42n, 0n
      ]
    });

    await admin.waitForTransaction(res.transaction_hash);

    // Set Ether and receivables address
    res = await dispatcher.compileAndInvoke('register_contract', {
      name: shortString.encodeShortString('Ether'),
      address: ETHER_ADDRESS
    });

    await admin.waitForTransaction(res.transaction_hash);

    res = await dispatcher.compileAndInvoke('register_contract', {
      name: shortString.encodeShortString('ReceivablesAccount'),
      address: admin.address
    });

    await admin.waitForTransaction(res.transaction_hash);
  });

  it('should bridge an asteroid from L1', async function () {
    const message = {
      l2_contract_address: asteroid.address,
      entry_point_selector: hash.getSelectorFromName('bridge_from_l1'),
      l1_contract_address: L1_ASTEROID_BRIDGE_ADDRESS,
      payload: [ player1.address, num.toHexString(1), num.toHexString(104) ],
      nonce: num.toHexString(0),
      paid_fee_on_l1: num.toHexString(12345678)
    };

    const { data } = await provider.sendMessageToL2(message);
    await provider.waitForTransaction(data.transaction_hash);
    let owner = await asteroid.compileAndCall('ownerOf', { token_id: uint256.bnToUint256(104n) });
    expect(owner).to.eql(BigInt(player1.address));
  });

  it('should bridge a crewmate from L1', async function () {
    const message = {
      l2_contract_address: crewmate.address,
      entry_point_selector: hash.getSelectorFromName('bridge_from_l1'),
      l1_contract_address: L1_CREWMATE_BRIDGE_ADDRESS,
      payload: [
        player1.address,
        num.toHexString(2),
        num.toHexString(42),
        num.toHexString(82397293850685768012593140600065n)
      ],
      nonce: num.toHexString(1),
      paid_fee_on_l1: num.toHexString(12345678)
    };

    const { data } = await provider.sendMessageToL2(message);
    await provider.waitForTransaction(data.transaction_hash);
    let owner = await crewmate.compileAndCall('ownerOf', { token_id: uint256.bnToUint256(42n) });
    expect(owner).to.eql(BigInt(player1.address));
  });

  it('should allow initializing an Arvadian', async function () {
    dispatcher.connect(player1);
    let res = await dispatcher.compileAndInvoke('run_system', {
      name: shortString.encodeShortString('InitializeArvadian'),
      calldata: [
        Entity.IDS.CREWMATE, 42, // crewmate entity
        3, 30, 45, 47, // impactful traits
        5, 1, 6, 25, 33, 37, // cosmetic traits
        shortString.encodeShortString('Test Arvadian A'),
        Entity.IDS.BUILDING, 1, // habitat entity
        Entity.IDS.CREW, 0 // caller crew entity -> creates crew #2
      ]
    });

    await player1.waitForTransaction(res.transaction_hash);
    const crewmateData = await readComponent('Crewmate', [ { id: 42n, label: Entity.IDS.CREWMATE } ]);

    expect(crewmateData[2]).to.equal(1n, 'wrong collection');
    expect(crewmateData[3]).to.equal(2n, 'wrong class');
    expect(crewmateData[4]).to.equal(35n, 'wrong title');
    expect(crewmateData[7]).to.equal(1n, 'wrong cosmetic trait 1');
    expect(crewmateData[8]).to.equal(6n, 'wrong cosmetic trait 2');
    expect(crewmateData[9]).to.equal(25n, 'wrong cosmetic trait 3');
    expect(crewmateData[10]).to.equal(33n, 'wrong cosmetic trait 4');
    expect(crewmateData[11]).to.equal(37n, 'wrong cosmetic trait 5');
    expect(crewmateData[13]).to.equal(30n, 'wrong impactful trait 1');
    expect(crewmateData[14]).to.equal(45n, 'wrong impactful trait 2');
    expect(crewmateData[15]).to.equal(47n, 'wrong impactful trait 3');
  });

  it('should fail purchasing an Adalian without price set', async function () {
    dispatcher.connect(player2);
    await assertReverts(dispatcher.compileAndInvoke('run_system', {
      name: shortString.encodeShortString('PurchaseAdalian'),
      calldata: [
        4 // collection
      ]
    }), 'E6006: sale not active');
  });

  it('should fail purchasing an Adalian without approving enough ETH', async function () {
    // Add price for Adalians
    dispatcher.connect(admin);
    let res = await dispatcher.compileAndInvoke('register_constant', {
      name: shortString.encodeShortString('ADALIAN_PRICE_ETH'), value: 2500000000000000n
    });

    await admin.waitForTransaction(res.transaction_hash);

    // Try to purchase
    dispatcher.connect(player2);
    await assertReverts(dispatcher.compileAndInvoke('run_system', {
      name: shortString.encodeShortString('PurchaseAdalian'),
      calldata: [
        4 // collection
      ]
    }), 'ERC20: insufficient allowance');
  });

  it('should allow purchasing an Adalian', async function () {
    // Approve ETH
    const ether = new Contract(contracts.abi('Ether'), ETHER_ADDRESS, provider);
    ether.connect(player2);
    const call = ether.populate('approve', [ dispatcher.address, uint256.bnToUint256(2500000000000000n) ]);
    let res = await ether.approve(call.calldata);
    await player2.waitForTransaction(res.transaction_hash);

    // Purchase
    dispatcher.connect(player2);
    res = await dispatcher.compileAndInvoke('run_system', {
      name: shortString.encodeShortString('PurchaseAdalian'),
      calldata: [
        4 // collection
      ]
    });

    await player2.waitForTransaction(res.transaction_hash);

    // Check ownership
    const owner = await crewmate.compileAndCall('ownerOf', { token_id: uint256.bnToUint256(20000) });
    expect(owner).to.eql(BigInt(player2.address));
  });

  it('should allow recruiting an Adalian', async function () {
    dispatcher.connect(player2);
    const res = await dispatcher.compileAndInvoke('run_system', {
      name: shortString.encodeShortString('RecruitAdalian'),
      calldata: [
        Entity.IDS.CREWMATE, 20000, // crewmate entity
        1, // class
        1, 28,// impactful
        3, 4, 36, 5, // cosmetic
        1, // gender
        1, // body
        1, // face
        0, // hair
        3, // hair color
        33, // clothes
        shortString.encodeShortString('Test Adalian A'),
        Entity.IDS.BUILDING, 1, // building entity
        Entity.IDS.CREW, 0 // caller crew entity
      ]
    });

    await player2.waitForTransaction(res.transaction_hash);
    const crewmateData = await readComponent('Crewmate', [ { id: 20000, label: Entity.IDS.CREWMATE } ]);
    expect(crewmateData[2]).to.equal(4n, 'wrong collection');
    expect(crewmateData[3]).to.equal(1n, 'wrong class');
    expect(crewmateData[4]).to.equal(0n, 'wrong title');
    expect(crewmateData[7]).to.equal(4n, 'wrong cosmetic trait 1');
    expect(crewmateData[8]).to.equal(36n, 'wrong cosmetic trait 2');
    expect(crewmateData[9]).to.equal(5n, 'wrong cosmetic trait 3');
    expect(crewmateData[11]).to.equal(28n, 'wrong impactful trait 1');
  });

  it('should allow purchasing and recruiting an Adalian', async function () {
      // Approve ETH
      const ether = new Contract(contracts.abi('Ether'), ETHER_ADDRESS, provider);
      ether.connect(player2);
      const call = ether.populate('approve', [ dispatcher.address, uint256.bnToUint256(2500000000000000n) ]);
      let res = await ether.approve(call.calldata);
      await player2.waitForTransaction(res.transaction_hash);

      dispatcher.connect(player2);
      res = await dispatcher.compileAndInvoke('run_system', {
        name: shortString.encodeShortString('RecruitAdalian'),
        calldata: [
          Entity.IDS.CREWMATE, 0, // crewmate entity
          1, // class
          1, 28,// impactful
          3, 4, 36, 5, // cosmetic
          1, // gender
          1, // body
          1, // face
          0, // hair
          3, // hair color
          33, // clothes
          shortString.encodeShortString('Test Adalian B'),
          Entity.IDS.BUILDING, 1, // building entity
          Entity.IDS.CREW, 3 // caller crew entity
        ]
      });

      await player2.waitForTransaction(res.transaction_hash);
      const crewmateData = await readComponent('Crewmate', [ { id: 20001, label: Entity.IDS.CREWMATE } ]);
      expect(crewmateData[2]).to.equal(4n, 'wrong collection');
      expect(crewmateData[3]).to.equal(1n, 'wrong class');
      expect(crewmateData[4]).to.equal(0n, 'wrong title');
      expect(crewmateData[7]).to.equal(4n, 'wrong cosmetic trait 1');
      expect(crewmateData[8]).to.equal(36n, 'wrong cosmetic trait 2');
      expect(crewmateData[9]).to.equal(5n, 'wrong cosmetic trait 3');
      expect(crewmateData[11]).to.equal(28n, 'wrong impactful trait 1');
  });

  it('should allow managing an asteroid', async function () {
    dispatcher.connect(player1);
    const res = await dispatcher.compileAndInvoke('run_system', {
      name: shortString.encodeShortString('ManageAsteroid'),
      calldata: [
        Entity.IDS.ASTEROID, 104, // asteroid entity
        Entity.IDS.CREW, 2 // caller crew entity
      ]
    });

    await player1.waitForTransaction(res.transaction_hash);
    const controlData = await readComponent('Control', [ { id: 104n, label: Entity.IDS.ASTEROID } ]);
    expect(controlData[1]).to.equal(1n); // true
  });

  it('should fail naming an asteroid controlled by another', async function () {
    const message = {
      l2_contract_address: asteroid.address,
      entry_point_selector: hash.getSelectorFromName('bridge_from_l1'),
      l1_contract_address: L1_ASTEROID_BRIDGE_ADDRESS,
      payload: [ player2.address, num.toHexString(1), num.toHexString(102406) ],
      nonce: num.toHexString(0),
      paid_fee_on_l1: num.toHexString(12345678)
    };

    const { data } = await provider.sendMessageToL2(message);
    await provider.waitForTransaction(data.transaction_hash);

    // Try to change its name as player 1
    dispatcher.connect(player1);
    await assertReverts(dispatcher.compileAndInvoke('run_system', {
      name: shortString.encodeShortString('ChangeName'),
      calldata: [
        Entity.IDS.ASTEROID, 102406, // asteroid entity
        shortString.encodeShortString('New Name'),
        Entity.IDS.CREW, 2 // caller crew entity
      ]
    }), 'E2001: uncontrolled');
  });

  it('should fail renaming a crewmate', async function () {
    dispatcher.connect(player1);
    await assertReverts(dispatcher.compileAndInvoke('run_system', {
      name: shortString.encodeShortString('ChangeName'),
      calldata: [
        Entity.IDS.CREWMATE, 42, // crewmate entity
        shortString.encodeShortString('Newer Name'),
        Entity.IDS.CREW, 2 // caller crew entity
      ]
    }), 'E6007: name already set');
  });

  it('should allow initializing an asteroid', async function () {
    const message = {
      l2_contract_address: asteroid.address,
      entry_point_selector: hash.getSelectorFromName('bridge_from_l1'),
      l1_contract_address: L1_ASTEROID_BRIDGE_ADDRESS,
      payload: [ player1.address, num.toHexString(1), num.toHexString(104) ],
      nonce: num.toHexString(0),
      paid_fee_on_l1: num.toHexString(12345678)
    };

    const { data } = await provider.sendMessageToL2(message);
    await provider.waitForTransaction(data.transaction_hash);

    const proof = [
      '0x728208d3d819a8663540b8ad305f360666510a43c08ead4bd1b38199d46d6b6',
      '0x30595094eb9e9f5c3e02484b47b14d62888635e7190ffcbef1da0f0853da9ee',
      '0x1048d757880f85521176d0d680e6ab77b7481db79204420d6c2d55d78a5a244',
      '0x6da3b796a186d8f16a43c6960f5e8e504592a84029bab21252b0457429f0cef',
      '0x1c2cd3d348256803acbc0231a89ead1e2074e12c240d6d3b3f67c9c3be442e2',
      '0x4446f8d4d98e4e8bf8fc81a234cda60e274dfebb262da847bd86e901d874ef2',
      '0x3ba8cad8d36a95a136f5fd7333440a34eadfb8339254646bf5d0b276e959bef',
      '0x5aeda266598f5b6473b03ea9a1f0f1d1963c4e6c6c8d5fb5da4de4d0c6c2696',
      '0x6683adb23623732033ae95a4cb2bdd3764393254ddcf0ace40d6de9e2be8d03',
      '0x4f13cd52bf4d821fc534bbec7aaa74d5be1123583aaf0312c6782cdea3a434f',
      '0x3cef698b208a80898664445b48451c6c7f7b4cd3b9b138f9e5682113598090e',
      '0x170dc1abbd55932f56d8175f20e2009a8489ceb20cb03b43f9c0731a78baa52',
      '0x6e5ab602c6eaa28ed58f937e6422e55c28cd6615ba1c3ce820bc6ff4efd1351',
      '0x2698b4b71c8de15028124f807b8122d32d43cea67e61e5b362a533b77ca7157',
      '0x2112667b11334fca9b9e947f7c8874374313d86cc57283a3c0a53f5e252c8c9',
      '0x73c9ae2a721671b74b92bd111b632625f6eb5b2a61b766c46ba602afcdde91a',
      '0x56340c5df68ba09f36906c321f4ab6b3ec6ec4ce4406c9c5aa33a9d4bc71e3c',
      '0x2533a6ee08d7fd13f83aa86fec53969fc32411280c37947762995251694c5d0'
    ];

    dispatcher.connect(admin);
    const res = await dispatcher.compileAndInvoke('run_system', {
      name: shortString.encodeShortString('InitializeAsteroid'),
      calldata: [
        Entity.IDS.ASTEROID, 104, // asteroid entity
        5, // Cms-type
        17072875219490727398839123416449024n, // mass
        177442278866n, // radius
        5276343029689403780074217825n, // a
        2711671378835304087n, // ecc
        1101090957627722624n, // inc
        45595468251239202816n, // raan
        5936876391419651072n, // argp
        73740898519021518848n, // m
        365, // purchase order
        2, // scan status
        25, // bonuses
        proof.length,
        ...proof
      ]
    });

    await admin.waitForTransaction(res.transaction_hash);
  });

  it('should fail long-range scanning an asteroid owned by another', async function () {
    dispatcher.connect(player2);
    await assertReverts(dispatcher.compileAndInvoke('run_system', {
      name: shortString.encodeShortString('ScanSurfaceStart'),
      calldata: [
        Entity.IDS.ASTEROID, 104, // asteroid entity
        Entity.IDS.CREW, 2 // caller crew entity
      ]
    }), 'E2004: incorrect delegate');
  });

  it('should fail long-range scanning an already scanned asteroid', async function () {
    dispatcher.connect(player1);
    await assertReverts(dispatcher.compileAndInvoke('run_system', {
      name: shortString.encodeShortString('ScanSurfaceStart'),
      calldata: [
        Entity.IDS.ASTEROID, 104, // asteroid entity
        Entity.IDS.CREW, 2 // caller crew entity
      ]
    }), 'E6008: scan already started');
  });

  it('should allow managing an asteroid', async function () {
    dispatcher.connect(player2);
    const res = await dispatcher.compileAndInvoke('run_system', {
      name: shortString.encodeShortString('ManageAsteroid'),
      calldata: [
        Entity.IDS.ASTEROID, 102406, // asteroid entity
        Entity.IDS.CREW, 3 // caller crew entity
      ]
    });

    await player2.waitForTransaction(res.transaction_hash);
    const controlData = await readComponent('Control', [ { id: 102406, label: Entity.IDS.ASTEROID } ]);
    expect(controlData[1]).to.equal(1n); // crew entity type
    expect(controlData[2]).to.equal(3n); // crew #3
  });

  it('should fail scanning an uninitialized asteroid', async function () {
    dispatcher.connect(player2);
    await assertReverts(dispatcher.compileAndInvoke('run_system', {
      name: shortString.encodeShortString('ScanSurfaceStart'),
      calldata: [
        Entity.IDS.ASTEROID, 102406, // asteroid entity
        Entity.IDS.CREW, 3 // caller crew entity
      ]
    }), 'E1003: celestial not found');
  });

  it('should allow long-range scanning an asteroid', async function () {
    const proof = [
      '0x45dea61d344af5516352a5a1d6dbf80158e1600325ab8ce7a6a23b09b1cfa4',
      '0x3bdc563059557f2c256bd1481252c9829ef6a6d2d2a7a1f3bedc2e0017e04f9',
      '0x4188cf301aba074e41f4f0303a5b0d571aef855378c22a2906bfdc5237ecf2d',
      '0x5d47850295f8798602739ee2b3cdf02c834c731646c49ed18e75d53cf1c9621',
      '0xf833469df3bd363d2ffe70a62574fe61ebeada57059b417a059727089e2e69',
      '0xa8ae8e4760cfc8e63232c9be62b74157a6208e4cf8539f6b8ca48ec9fbaea4',
      '0x6a6f4597ce63e7bb8bba9ef59ef26be4ac7f987c1d5781b85f7bcd0085ca2e9',
      '0x48cf5de4edd77c7c84bd669e3dabacc27b3af4277f050d169097b2f76f2f8ff',
      '0x5355d4160b6e230b7ebd96d1e7756694fa018b60f18899d7b09a6ece876de27',
      '0x410375c28bb5d35a7c55eb6697da407701dd59230417316513d21d0cd39883f',
      '0x525c20b85b229148b5806fe3dc36f799ad8a617f3b07a0398d2577680fe44a5',
      '0x48cd8b1b86a606732320618566e6af8bf1734abbf41310d31e7c855878964a5',
      '0x477b0d878a36ceb522fc76f756ced2e9a471a3469e28e033d5b8014d772f1ae',
      '0x5dcefc8593d519de6a2f288541f6f47b6ce42e9bc2c210cb88c78a01b0fc442',
      '0x26d91110bfba0b7c0db54cd9ded161fd47147f9cc37c4e2a303aaeaa4f0ff4c',
      '0x1bc507a6782d60043dbb52d08e8bfa87eedfc802a7ac93b21050b888d2791',
      '0x63c6e4d716eea2aaf953216056c3f35c66f352d78c69fccb00124bb6789ec4',
      '0x2533a6ee08d7fd13f83aa86fec53969fc32411280c37947762995251694c5d0'
    ];

    dispatcher.connect(player2);
    let res = await dispatcher.compileAndInvoke('run_system', {
      name: shortString.encodeShortString('InitializeAsteroid'),
      calldata: [
        Entity.IDS.ASTEROID, 102406, // asteroid entity
        10n, // M-type
        1566731039420335281770973888512n, // mass
        6717328850n, // radius
        4627838525517327478652961973n, // a
        4703919738795935662n, // ecc
        2585310055482635264n, // inc
        48702347707703386112n, // raan
        49050060641691090944n, // argp
        11612968082348525568n, // m
        11464, // purchase order
        0, // scan status
        0, // bonuses
        proof.length,
        ...proof
      ]
    });

    await admin.waitForTransaction(res.transaction_hash);

    res = await dispatcher.compileAndInvoke('run_system', {
      name: shortString.encodeShortString('ScanSurfaceStart'),
      calldata: [
        Entity.IDS.ASTEROID, 102406, // asteroid entity
        Entity.IDS.CREW, 3 // caller crew entity
      ]
    });

    await player2.waitForTransaction(res.transaction_hash);

    await provider.advanceTime(5000);
    res = await dispatcher.compileAndInvoke('run_system', {
      name: shortString.encodeShortString('ScanSurfaceFinish'),
      calldata: [
        Entity.IDS.ASTEROID, 102406, // asteroid entity
        Entity.IDS.CREW, 3 // caller crew entity
      ]
    });

    await player2.waitForTransaction(res.transaction_hash);

    // Check surface
    const celestialData = await readComponent('Celestial', [ { id: 102406n, label: Entity.IDS.ASTEROID } ]);
    expect(celestialData[7]).to.equal(2n); // surface scanned status
  });

  it('should fail purchasing an asteroid when no price is set', async function () {
    // Init asteroid
    const proof = [
      '0x7ca048e246b9468cb05e9191a16ad805928f3c350fba12e556762ac325f0a04',
      '0x152552bbd5acf8ce1ff178a0677d4a93c850c982714fb68695aa9dd10aab30a',
      '0x62c3cbe52118bd77d641b5ffb43b5a6dd8eec377c9308ac07048231680e13f9',
      '0x65830fcf11ac826d01d93f7518ff391d32c8ec8093e6ee2c6627de3e39bbe6c',
      '0x5133f34c3cb6a84749239b871fe6fe11a0c4c3e077845e511ff7a19e30aa2d0',
      '0x17667e54a2a672a8da1cbfe9a7f86aaa1e503eef18d42dd787ac20b449727bd',
      '0x6fb036702049b159ec46295484f19a9263a5423d658e4cf09944fa692d43460',
      '0x3b9056774019aa17297d58651c86f7ceb4a172cfb01f9f7d4eabae38af05ef',
      '0x50aa2f251cffa348c28ed8ab0a90d865847138af0586f8beb72628d608ba161',
      '0x36a72f9582aad99c30e94514f93072011391815410e79dadb69b3a388497282',
      '0x368775efbeccbb3440dd5079456475dd8c994462fadb6684a4b4c7b9f8645fa',
      '0x3070e97aa1011dd6abf413c4e72bc778f59beab188a513d60eb4a330b0bf3',
      '0x6c7efd0cd16dadee278efaada47fad46b3b17ccf73b1f351a30765eaf839418',
      '0x0',
      '0x499ba178d0b45690d15723151ef12edebdb800aeaa827dece2d6d84bf07b47b',
      '0x781915a9da7514318c3893abe7f7b6fa7d0023670633c9477255b55a6425348',
      '0x75dc37761e2350c2a789ecfb48f283d9676e17074ec94dcf645690af57f5d9c',
      '0x37bd3e62b447da48d7722fb58099b984eae632142f3066e610b5e45abb48585'
    ];

    let res = await dispatcher.compileAndInvoke('run_system', {
      name: shortString.encodeShortString('InitializeAsteroid'),
      calldata: [
        Entity.IDS.ASTEROID, 249322, // asteroid entity
        7n, // M-type
        224669279274347431142247890944n, // mass
        4402341478n, // radius
        3902065399571556979615556488n, // a
        3523328118078524358n, // ecc
        1500316918872861952n, // inc
        19233676552245657600n, // raan
        8151936563489455104n, // argp
        11226620377917745152n, // m
        0, // purchase order
        0, // scan status
        0, // bonuses
        proof.length,
        ...proof
      ]
    });

    await admin.waitForTransaction(res.transaction_hash);

    dispatcher.connect(player2);
    await assertReverts(dispatcher.compileAndInvoke('run_system', {
      name: shortString.encodeShortString('PurchaseAsteroid'),
      calldata: [
        Entity.IDS.ASTEROID, 249322, // asteroid entity
        Entity.IDS.CREW, 3 // caller crew entity
      ]
    }), 'E6006: sale not active');
  });

  it('should allow purchasing an asteroid', async function () {
    // Set sale constants
    const basePrice = 30000000000000000n;
    const lotPrice = 1250000000000000n;
    dispatcher.connect(admin);
    let res = await dispatcher.compileAndInvoke('register_constant', {
      name: shortString.encodeShortString('ASTEROID_BASE_PRICE_ETH'), value: basePrice
    });

    await admin.waitForTransaction(res.transaction_hash);
    res = await dispatcher.compileAndInvoke('register_constant', {
      name: shortString.encodeShortString('ASTEROID_LOT_PRICE_ETH'), value: lotPrice
    });

    await admin.waitForTransaction(res.transaction_hash);
    res = await dispatcher.compileAndInvoke('register_constant', {
      name: shortString.encodeShortString('ASTEROID_SALE_LIMIT'), value: 1n
    });

    await admin.waitForTransaction(res.transaction_hash);

    // Approve ETH
    const price = BigInt(Asteroid.getSurfaceArea(249322)) * lotPrice + basePrice;
    const ether = new Contract(contracts.abi('Ether'), ETHER_ADDRESS, provider);
    ether.connect(player2);
    const call = ether.populate('approve', [ dispatcher.address, uint256.bnToUint256(price) ]);
    res = await ether.approve(call.calldata);
    await player2.waitForTransaction(res.transaction_hash);

    // Purchase
    dispatcher.connect(player2);
    res = await dispatcher.compileAndInvoke('run_system', {
      name: shortString.encodeShortString('PurchaseAsteroid'),
      calldata: [
        Entity.IDS.ASTEROID, 249322, // asteroid entity
        Entity.IDS.CREW, 3 // caller crew entity
      ]
    });

    await player2.waitForTransaction(res.transaction_hash);

    // Check ownership
    let owner = await asteroid.compileAndCall('ownerOf', { token_id: uint256.bnToUint256(249322n) });
    expect(owner).to.eql(BigInt(player2.address));

    owner = await crewmate.compileAndCall('ownerOf', { token_id: uint256.bnToUint256(20002n) });
    expect(owner).to.eql(BigInt(player2.address));
  });

  it('should fail purchasing an asteroid over limit', async function () {
    const proof = [
      '0x4bcfaf1a2eeae56c2d22f3a3efc1adc1ee043ac28f6d2f6f4e2eb3e3a0b34db',
      '0x6d6bd7bea2accf7b908df6ccd5445f6c9cd51e2542590ad08a6f496370e8dc5',
      '0x62c3cbe52118bd77d641b5ffb43b5a6dd8eec377c9308ac07048231680e13f9',
      '0x65830fcf11ac826d01d93f7518ff391d32c8ec8093e6ee2c6627de3e39bbe6c',
      '0x5133f34c3cb6a84749239b871fe6fe11a0c4c3e077845e511ff7a19e30aa2d0',
      '0x17667e54a2a672a8da1cbfe9a7f86aaa1e503eef18d42dd787ac20b449727bd',
      '0x6fb036702049b159ec46295484f19a9263a5423d658e4cf09944fa692d43460',
      '0x3b9056774019aa17297d58651c86f7ceb4a172cfb01f9f7d4eabae38af05ef',
      '0x50aa2f251cffa348c28ed8ab0a90d865847138af0586f8beb72628d608ba161',
      '0x36a72f9582aad99c30e94514f93072011391815410e79dadb69b3a388497282',
      '0x368775efbeccbb3440dd5079456475dd8c994462fadb6684a4b4c7b9f8645fa',
      '0x3070e97aa1011dd6abf413c4e72bc778f59beab188a513d60eb4a330b0bf3',
      '0x6c7efd0cd16dadee278efaada47fad46b3b17ccf73b1f351a30765eaf839418',
      '0x0',
      '0x499ba178d0b45690d15723151ef12edebdb800aeaa827dece2d6d84bf07b47b',
      '0x781915a9da7514318c3893abe7f7b6fa7d0023670633c9477255b55a6425348',
      '0x75dc37761e2350c2a789ecfb48f283d9676e17074ec94dcf645690af57f5d9c',
      '0x37bd3e62b447da48d7722fb58099b984eae632142f3066e610b5e45abb48585'
    ];

    let res = await dispatcher.compileAndInvoke('run_system', {
      name: shortString.encodeShortString('InitializeAsteroid'),
      calldata: [
        Entity.IDS.ASTEROID, 249323, // asteroid entity
        1n, // M-type
        116495181844591501772001902592n, // mass
        4402341478n, // radius
        5977279812922201144163575214n, // a
        3836922767331586736n, // ecc
        4217629106702680064n, // inc
        59990139805489348608n, // raan
        96197358839060594688n, // argp
        21738497502638546944n, // m
        0, // purchase order
        0, // scan status
        0, // bonuses
        proof.length,
        ...proof
      ]
    });

    await admin.waitForTransaction(res.transaction_hash);

    // Approve ETH
    const basePrice = 30000000000000000n;
    const lotPrice = 1250000000000000n;
    const price = BigInt(Asteroid.getSurfaceArea(249323)) * lotPrice + basePrice;
    const ether = new Contract(contracts.abi('Ether'), ETHER_ADDRESS, provider);
    ether.connect(player2);
    const call = ether.populate('approve', [ dispatcher.address, uint256.bnToUint256(price) ]);
    res = await ether.approve(call.calldata);
    await player2.waitForTransaction(res.transaction_hash);

    // Purchase
    dispatcher.connect(player2);
    await assertReverts(dispatcher.compileAndInvoke('run_system', {
      name: shortString.encodeShortString('PurchaseAsteroid'),
      calldata: [
        Entity.IDS.ASTEROID, 249323, // asteroid entity
        Entity.IDS.CREW, 3 // caller crew entity
      ]
    }), 'E6019: sale limit reached');
  });

  it('should fail claiming a reward with incorrect asteroid', async function () {
    dispatcher.connect(player2);
    await assertReverts(dispatcher.compileAndInvoke('run_system', {
      name: shortString.encodeShortString('ClaimPrepareForLaunchReward'),
      calldata: [
        Entity.IDS.ASTEROID, 249322, // asteroid entity
        Entity.IDS.CREW, 3 // caller crew entity
      ]
    }), 'E6015: reward not found');
  });

  it('should succeed claiming a reward', async function () {
    dispatcher.connect(player2);
    await dispatcher.compileAndInvoke('run_system', {
      name: shortString.encodeShortString('ClaimPrepareForLaunchReward'),
      calldata: [
        Entity.IDS.ASTEROID, 102406, // asteroid entity
        Entity.IDS.CREW, 3 // caller crew entity
      ]
    });

    // Check crewmate credit
    let owner = await crewmate.compileAndCall('ownerOf', { token_id: uint256.bnToUint256(20002n) });
    expect(owner).to.eql(BigInt(player2.address));
  });

  it('should fail moving a crewmate to an un-delegated crew', async function () {
    dispatcher.connect(player2);
    await assertReverts(dispatcher.compileAndInvoke('run_system', {
      name: shortString.encodeShortString('ExchangeCrew'),
      calldata: [
        Entity.IDS.CREW, 3, // crew 1
        1, 20000, // crew 1 new comp
        Entity.IDS.CREW, 2, // crew 2
        2, 42, 20001 // crew 2 new comp
      ]
    }), 'E2004: incorrect delegate');
  });

  it('should fail moving an unowned crewmate from an unowned crew', async function () {
    dispatcher.connect(player2);
    await assertReverts(dispatcher.compileAndInvoke('run_system', {
      name: shortString.encodeShortString('ExchangeCrew'),
      calldata: [
        Entity.IDS.CREW, 2, // crew 1
        0, // crew 1 new comp
        Entity.IDS.CREW, 3, // crew 2
        3, 20000, 20001, 42 // crew 2 new comp
      ]
    }), 'E2003: incorrect owner');
  });

  it('should allow moving crewmatews between delegated crews', async function () {
    dispatcher.connect(player2);
    await dispatcher.compileAndInvoke('run_system', {
      name: shortString.encodeShortString('ExchangeCrew'),
      calldata: [
        Entity.IDS.CREW, 3, // crew 1
        1, 20000, // crew 1 new comp
        Entity.IDS.CREW, 0, // crew 2
        1, 20001 // crew 2 new comp
      ]
    });

    // Check data
    const crew1Data = await readComponent('Crew', [ { id: 3n, label: Entity.IDS.CREW } ]);
    expect(crew1Data[2]).to.eql(1n);
    expect(crew1Data[3]).to.eql(20000n);
    const crew2Data = await readComponent('Crew', [ { id: 4n, label: Entity.IDS.CREW } ]);
    expect(crew2Data[2]).to.eql(1n);
    expect(crew2Data[3]).to.eql(20001n);

    const control1Data = await readComponent('Control', [ { id: 20000n, label: Entity.IDS.CREWMATE } ]);
    expect(control1Data[2]).to.eql(3n);
    const control2Data = await readComponent('Control', [ { id: 20001n, label: Entity.IDS.CREWMATE } ]);
    expect(control2Data[2]).to.eql(4n);
  });

  it('should allow moving owned crewmate from unowned crew', async function () {
    crewmate.connect(player1);
    await crewmate.compileAndInvoke('transferFrom', {
      from: player1.address,
      to: player2.address,
      token_id: uint256.bnToUint256(42n)
    });

    dispatcher.connect(player2);
    await dispatcher.compileAndInvoke('run_system', {
      name: shortString.encodeShortString('ExchangeCrew'),
      calldata: [
        Entity.IDS.CREW, 2, // crew 1
        0, // crew 1 new comp
        Entity.IDS.CREW, 3, // crew 2
        2, 20000, 42 // crew 2 new comp
      ]
    });

    // Check data
    const crew1Data = await readComponent('Crew', [ { id: 2n, label: Entity.IDS.CREW } ]);
    expect(crew1Data[2]).to.eql(0n);
    const crew2Data = await readComponent('Crew', [ { id: 3n, label: Entity.IDS.CREW } ]);
    expect(crew2Data[2]).to.eql(2n);
    expect(crew2Data[3]).to.eql(20000n);
    expect(crew2Data[4]).to.eql(42n);
  });

  it('should fail arranging an undelegated crew', async function () {
    dispatcher.connect(player1);
    await assertReverts(dispatcher.compileAndInvoke('run_system', {
      name: shortString.encodeShortString('ArrangeCrew'),
      calldata: [
        2, 42, 20000, // composition
        Entity.IDS.CREW, 3 // caller crew
      ]
    }), 'E2004: incorrect delegate');
  });

  it('should allow re-arranging a delegated crew', async function () {
    dispatcher.connect(player2);
    await dispatcher.compileAndInvoke('run_system', {
      name: shortString.encodeShortString('ArrangeCrew'),
      calldata: [
        2, 42, 20000, // composition
        Entity.IDS.CREW, 3 // caller crew
      ]
    });

    // Check data
    const crewData = await readComponent('Crew', [ { id: 3n, label: Entity.IDS.CREW } ]);
    expect(crewData[2]).to.eql(2n);
    expect(crewData[3]).to.eql(42n);
    expect(crewData[4]).to.eql(20000n);
  });
});