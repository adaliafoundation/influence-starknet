import isEqual from 'lodash.isequal';
import { Crewmate } from '@influenceth/sdk';

const updateModifiers = async (dispatcher, account) => {
  for await (const m of Object.values(Crewmate.ABILITY_TYPES)) {
    let existing;

    try {
      existing = await dispatcher.compileAndCall('run_system', {
        name: 'ReadComponent',
        calldata: [ 'ModifierType', 1n, BigInt(m.i) ]
      });
    } catch (e) {
      existing = [];
    }

    const compData = [ 7n, m.class ? BigInt(m.class) : 0n, 0n, 0n, 0n, 0n, 0n, m.notFurtherModified ? 0n : 1n ];

    // Departments
    Object.entries(m.departments || {}).forEach(([k, v]) => {
      if (Number(k) === Number(Crewmate.DEPARTMENT_IDS.MANAGEMENT)) {
        compData[4] = BigInt(Math.round(v * 10000));
      } else {
        compData[2] = BigInt(k);
        compData[3] = BigInt(Math.round(v * 10000));
      }
    });

    // Traits
    Object.entries(m.traits || {}).forEach(([k, v]) => {
      compData[5] = BigInt(k);
      compData[6] = BigInt(Math.round(v * 10000));
    });

    if (!isEqual(existing, compData)) {
      try {
        const res = await dispatcher.compileAndInvoke('run_system', {
          name: 'WriteComponent',
          calldata: [ 'ModifierType', 1n, BigInt(m.i), ...compData ]
        });

        await account.waitForTransaction(res.transaction_hash);
        console.log(`Updated ModifierType #${m.i}:`, m.name);
      } catch (e) {
        console.log(e);
        console.error(`Error updating ModifierType #${m.i}:`, m.name);
      }
    } else {
      console.log(`ModifierType #${m.i} already up to date:`, m.name);
    }
  }
};

export default updateModifiers;