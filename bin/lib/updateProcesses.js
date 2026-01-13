import isEqual from 'lodash.isequal';
import { Process } from '@influenceth/sdk';

const updateProcesses = async (dispatcher, account) => {
  for await (const p of Object.values(Process.TYPES)) {
    let existing;

    try {
      existing = await dispatcher.compileAndCall('run_system', {
        name: 'ReadComponent',
        calldata: [ 'ProcessType', 1n, BigInt(p.i) ]
      });
    } catch (e) {
      existing = [];
    }

    const inputs = p.inputs ? Object.entries(p.inputs).map(([k, v]) => [BigInt(k), BigInt(v)]) : [];
    const outputs = p.outputs ? Object.entries(p.outputs).map(([k, v]) => [BigInt(k), BigInt(v)]) : [];
    const compData = [
      BigInt(Math.round(p.setupTime)),
      BigInt(Math.round(p.recipeTime * 1000)),
      p.batched ? 1n: 0n,
      p.processorType ? BigInt(p.processorType) : 0n,
      BigInt(inputs.length),
      ...inputs,
      BigInt(outputs.length),
      ...outputs
    ].flat();
    compData.unshift(BigInt(compData.length));

    if (!isEqual(existing, compData)) {
      try {
        const res = await dispatcher.compileAndInvoke('run_system', {
          name: 'WriteComponent',
          calldata: [ 'ProcessType', 1n, BigInt(p.i), ...compData ]
        });

        await account.waitForTransaction(res.transaction_hash);
        console.log(`Updated ProcessType #${p.i}:`, p.name);
      } catch (e) {
        console.log(e);
        console.error(`Error updating ProcessType #${p.i}:`, p.name);
      }
    } else {
      console.log(`ProcessType #${p.i} already up to date:`, p.name);
    }
  }
};

export default updateProcesses;