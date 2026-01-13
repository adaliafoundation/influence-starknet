import ibis from '@influenceth/ibis';

const updateConstant = async ({ network, account, name, value }) => {
  const { contracts } = ibis(network);
  const dispatcher = contracts.deployed('Dispatcher');
  dispatcher.connect(account);

  let existing;

  try {
    existing = await dispatcher.compileAndCall('constant', { name });
  } catch (e) {
    existing = 0n;
  }

  if (existing !== BigInt(value)) {
    try {
      const res = await dispatcher.compileAndInvoke('register_constant', { name, value: BigInt(value) });
      console.log('Waiting for transaction: ', res.transaction_hash);
      await account.waitForTransaction(res.transaction_hash);
      console.log(`Updated constant: ${name}`);
    } catch (e) {
      console.log(e);
      console.error(`Error updating constant: ${name}`);
    }
  } else {
    console.log(`Constant already up to date: ${name}`);
  }
};

export default updateConstant;