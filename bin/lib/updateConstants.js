import { Asteroid, Building, Crew, Delivery, Deposit, Permission, Process, Ship, Time } from '@influenceth/sdk';

const updateConstants = async (dispatcher, account) => {
  const constants = [
    { name: 'CONSTRUCTION_GRACE_PERIOD', value: BigInt(Building.CONSTRUCTION_GRACE_PERIOD) },
    { name: 'CORE_SAMPLING_TIME', value: BigInt(Deposit.CORE_SAMPLING_TIME) },
    { name: 'CREW_SCHEDULE_BUFFER', value: BigInt(Crew.CREW_SCHEDULE_BUFFER) },
    { name: 'CREWMATE_FOOD_PER_YEAR', value: BigInt(Crew.CREWMATE_FOOD_PER_YEAR) },
    { name: 'DECONSTRUCTION_PENALTY', value: BigInt(Math.round(Building.DECONSTRUCTION_PENALTY * 2 ** 32)) },
    { name: 'EMERGENCY_PROP_GEN_TIME', value: BigInt(Ship.EMERGENCY_PROP_GEN_TIME) },
    { name: 'HOPPER_SPEED', value: BigInt(Math.round(Asteroid.HOPPER_SPEED * 3600 * 2 ** 32)) },
    { name: 'INSTANT_TRANSPORT_DISTANCE', value: BigInt(Delivery.INSTANT_TRANSPORT_DISTANCE * 2 ** 32) },
    { name: 'MAX_POLICY_DURATION', value: BigInt(Permission.MAX_POLICY_DURATION) },
    { name: 'MAX_PROCESS_TIME', value: BigInt(Process.MAX_PROCESS_TIME)},
    { name: 'SCANNING_TIME', value: BigInt(Asteroid.SCANNING_TIME) },
    { name: 'TIME_ACCELERATION', value: BigInt(Time.DEFAULT_TIME_ACCELERATION) }
  ];

  for await (const c of constants) {
    let existing;

    try {
      existing = await dispatcher.compileAndCall('constant', { name: c.name });
    } catch (e) {
      existing = 0n;
    }

    if (existing !== c.value) {
      try {
        const res = await dispatcher.compileAndInvoke('register_constant', c);
        console.log('Waiting for transaction: ', res.transaction_hash);
        await account.waitForTransaction(res.transaction_hash);
        console.log(`Updated constant: ${c.name}`);
      } catch (e) {
        console.log(e);
        console.error(`Error updating constant: ${c.name}`);
      }
    } else {
      console.log(`Constant already up to date: ${c.name}`);
    }
  }
};

export default updateConstants;