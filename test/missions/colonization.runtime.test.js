import assert from 'node:assert/strict';
import { test } from 'node:test';
import { Entity, Product } from '@influenceth/sdk';
import { hash, shortString } from 'starknet';
import { observeMissionAction, escrowWithdrawalArguments } from '../../bin/lib/missionObservation.js';
import { startDevnet, call } from './devnet.js';

const felt = shortString.encodeShortString;
const B = Entity.IDS.BUILDING, C = Entity.IDS.CREW, WATER = Product.IDS.WATER;

for (const sameTransaction of [false, true]) {
  test(`colonization native flow${sameTransaction ? ' with scan finish and construction start in one transaction' : ' with third-party construction'}`, { timeout: 600000 }, async t => {
    const { accounts: [admin, seller, buyer, marketAccount], provider, invoke, declare, deploy, reverted, rpc } = await startDevnet(t, sameTransaction ? 5053 : 5052);
    const market = sameTransaction ? seller : marketAccount;
    const dispatcher = await deploy('Dispatcher', [admin.address]);
    const token = await deploy('Sway', [felt('SWAY'), felt('SWAY'), 6, admin.address]);
    const escrow = await deploy('Escrow');
    const asteroid = await deploy('Asteroid', [felt('Asteroid'), felt('AST'), admin.address]);
    const campaign = felt('ColonyRuntime');
    const candidate = mission => ({ campaign, subject: { label: Entity.IDS.ASTEROID, id: 104 }, mission });
    const system = (name, data = []) => call(dispatcher, 'run_system', [felt(name), data.length, ...data]);
    const observed = (account, name, calldata, executionCalls = [system(name, calldata)], expectedCaller = account.address) =>
      observeMissionAction({ dispatcher, account: account.address, system: name, calldata, executionCalls, expectedCaller,
        candidates: [candidate(name.startsWith('Scan') ? 0 : 3)] });
    const names = ['MissionObserver', 'RegisterMissionCampaign', 'ConfigureColonizationMissions', 'AcceptMission',
      'ReadMissionState', 'ClaimMissionReward', 'ScanSurfaceStart', 'ScanSurfaceFinish', 'ConstructionStart',
      'ConstructionFinish', 'ConfigureExchange', 'CreateBuyOrder', 'FillBuyOrder', 'CreateSellOrder', 'FillSellOrder'];
    const registrations = [];
    for (const name of names) registrations.push(call(dispatcher, 'register_system', [felt(name), await declare(name)]));
    for (const name of ['MissionRuntimeSeed', 'RevertingMissionPolicy', 'ReentrantMissionAction']) {
      registrations.push(call(dispatcher, 'register_system', [felt(name), await declare(name, 'temp/mission-runtime-fixtures/target/dev')]));
    }
    await invoke(admin, registrations);
    await invoke(admin, [
      call(dispatcher, 'register_contract', [felt('Sway'), token]), call(dispatcher, 'register_contract', [felt('Escrow'), escrow]),
      call(dispatcher, 'register_contract', [felt('Asteroid'), asteroid]),
      call(asteroid, 'add_grant', [admin.address, 2]), call(asteroid, 'mint_with_id', [seller.address, 104, 0]),
      call(token, 'add_grant', [admin.address, 2]), call(token, 'mint', [dispatcher, 1500000000000n, 0]),
      call(token, 'mint', [seller.address, 1000000000, 0]), call(token, 'mint', [buyer.address, 1000000000, 0])
    ]);
    await invoke(admin, system('MissionRuntimeSeed', [seller.address, buyer.address, market.address]));
    const assignment = [campaign, Entity.IDS.ASTEROID, 104, 0];
    await invoke(admin, [system('RegisterMissionCampaign', [campaign, await declare('ColonizationMissionCampaign'), 5]),
      system('ConfigureColonizationMissions', [campaign])]);
    const read = async (mission = 0, slot = 'Earned') => (await provider.callContract(system('ReadMissionState',
      [campaign, Entity.IDS.ASTEROID, 104, mission, typeof slot === 'string' ? felt(slot) : slot]))).slice(1).map(BigInt);
    const balance = async account => BigInt((await provider.callContract(call(token, 'balance_of', [account])))[0]);
    const events = (r, name) => r.events.filter(e => BigInt(e.from_address) === BigInt(dispatcher) && BigInt(e.keys[0]) === BigInt(hash.getSelectorFromName(name)));
    await invoke(seller, system('AcceptMission', assignment));
    const reentry = await reverted(seller, observed(seller, 'ReentrantMissionAction', []));
    assert.match(reentry.revert_reason, /observer reentry/);

    await invoke(seller, observed(seller, 'ScanSurfaceStart', [Entity.IDS.ASTEROID, 104, C, 1]));
    await rpc('devnet_increaseTime', { time: 7200 });
    const finishScan = observed(seller, 'ScanSurfaceFinish', [Entity.IDS.ASTEROID, 104, C, 1]);
    const startConstruction = observed(market, 'ConstructionStart', [B, 2, C, 3]);
    await invoke(seller, sameTransaction ? [...finishScan, ...startConstruction] : finishScan);
    assert.deepEqual(await read(), [1n, 1n, 0n, 1n]);
    await invoke(seller, system('ClaimMissionReward', assignment));
    assert.equal((await read())[2], 1n);
    if (!sameTransaction) {
      await rpc('devnet_increaseTime', { time: 1 });
      await invoke(market, startConstruction);
    }
    await rpc('devnet_increaseTime', { time: 7200 });
    await invoke(market, observed(market, 'ConstructionFinish', [B, 2, C, 3]));
    await invoke(market, system('ConfigureExchange', [B, 2, 0, 0, 1, WATER, C, 3]));
    assert.equal((await read())[3], 1n, 'construction alone must not count');

    const hook = (name, data) => [dispatcher, hash.getSelectorFromName('run_system'), data.length, ...data];
    const makeBuy = async price => {
      const fixed = [C, 2, B, 2, WATER, price, B, 4, 2];
      const withdrawHook = hook('FillBuyOrder', [felt('FillBuyOrder'), 25, ...fixed]);
      const create = [B, 2, WATER, 10, price, B, 4, 2, C, 2];
      const depositHook = hook('CreateBuyOrder', [felt('CreateBuyOrder'), create.length + 5, ...create]);
      await invoke(buyer, [call(token, 'approve', [escrow, 10 * price, 0]),
        call(escrow, 'deposit', [token, 10 * price, 0, ...withdrawHook, ...depositHook])]);
      return { fixed, withdrawHook, price };
    };
    const buyFill = (order, amount, cancel = false) => {
      const actor = cancel ? buyer : seller;
      // Deliberately supply a positive amount even on cancellation: the native
      // cancellation branch ignores it, so amount alone is insufficient evidence.
      const extra = cancel ? [amount, 0, 0, 0, C, 2] : [amount, B, 3, 2, C, 1];
      const withdrawals = [{ recipient: actor.address, amount: cancel ? 10 * order.price : amount * order.price }, { recipient: market.address, amount: 0 }];
      const calldata = escrowWithdrawalArguments({ nativeArguments: [...order.fixed, ...extra], caller: actor.address, token, withdrawals });
      const serialized = [2, actor.address, withdrawals[0].amount, 0, market.address, 0, 0];
      const execution = call(escrow, 'withdraw', [buyer.address, token, ...order.withdrawHook, extra.length, ...extra, ...serialized]);
      return observed(actor, 'FillBuyOrder', calldata, [execution], escrow);
    };
    const cancelled = await invoke(buyer, buyFill(await makeBuy(2), 1, true));
    assert.equal(events(cancelled, 'BuyOrderCancelled').length, 1);
    assert.equal((await read())[3], 1n, 'cancellation credited commerce');
    const order = await makeBuy(1);
    await invoke(seller, buyFill(order, 1).slice(1, -1));
    assert.equal((await read())[3], 1n, 'ordinary fill discovered a mission');
    const before = await balance(seller.address);
    const wrongCandidate = buyFill(order, 1);
    wrongCandidate[0].calldata[6] = String(BigInt(wrongCandidate[0].calldata[6]) + 65536n);
    await reverted(seller, wrongCandidate);
    assert.equal(await balance(seller.address), before, 'wrong candidate leaked payment');
    const mismatched = buyFill(order, 1); mismatched[0].calldata[2] = '0';
    await reverted(seller, mismatched);
    assert.equal(await balance(seller.address), before, 'unmatched observation leaked payment');
    assert.equal((await read())[3], 1n);
    const fault = buyFill(order, 1); fault[0].calldata[0] = felt('RevertingMissionPolicy');
    await reverted(seller, fault);
    assert.equal(await balance(seller.address), before, 'failed post hook leaked payment');
    const filled = await invoke(seller, buyFill(order, 1));
    assert.equal(events(filled, 'BuyOrderFilled').length, 1);
    assert.equal(await balance(seller.address), before + 1n, 'tiny trade did not settle');
    assert.equal((await read())[3], 9n, 'positive quantity fill not credited');
    await invoke(seller, system('AcceptMission', [campaign, Entity.IDS.ASTEROID, 104, 3]));
    await invoke(seller, call(asteroid, 'transfer_from', [seller.address, buyer.address, 104, 0]));
    const claim = system('ClaimMissionReward', [campaign, Entity.IDS.ASTEROID, 104, 3]);
    await reverted(seller, claim); await reverted(buyer, claim);
    await invoke(buyer, call(asteroid, 'transfer_from', [buyer.address, seller.address, 104, 0]));
    const rewardBefore = await balance(seller.address);
    const paid = await invoke(seller, claim);
    assert.equal(events(paid, 'MissionRewardClaimed').length, 1);
    assert.equal(await balance(seller.address) - rewardBefore, 350000000000n);
    await reverted(seller, claim);
    assert.equal((await read(3))[2], 1n);
  });

}
