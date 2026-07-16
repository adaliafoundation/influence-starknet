const FRI_PER_STRK = 10n ** 18n;

export const isDryRun = (options = {}) => {
  return Boolean(options.dryRun || options.estimate);
};

export const txOptions = (options = {}) => {
  const { dryRun, estimate, ignoreBaseline, force, ...rest } = options;
  return rest;
};

export const hasEntrypoint = (contract, name) => {
  return Boolean(contract?.abi?.some((item) => item.type === 'function' && item.name === name));
};

const feeAmount = (fee = {}) => {
  return fee.overall_fee
    || fee.overallFee
    || fee.suggestedMaxFee
    || fee.actual_fee?.amount
    || 0;
};

export const formatFriAsStrk = (value) => {
  const fri = BigInt(value);
  const whole = fri / FRI_PER_STRK;
  const fractional = (fri % FRI_PER_STRK).toString().padStart(18, '0').replace(/0+$/, '');

  if (!fractional) return `${whole} STRK`;
  return `${whole}.${fractional.slice(0, 6)} STRK`;
};

const logFee = (label, fee) => {
  const amount = feeAmount(fee);
  console.log(`[dry-run] ${label}: estimated fee ${formatFriAsStrk(amount)} (${amount} fri)`);
};

export const classExists = async (account, classHash) => {
  try {
    await account.getClass(classHash);
    return true;
  } catch (error) {
    return false;
  }
};

export const estimateDeclare = async ({ account, contracts, contractName, classHash, options = {} }) => {
  if (await classExists(account, classHash)) {
    console.log(`[dry-run] ${contractName}: class already declared with hash ${classHash}`);
    return { alreadyDeclared: true };
  }

  const fee = await account.estimateDeclareFee({
    contract: contracts.sierra(contractName),
    casm: contracts.casm(contractName)
  }, txOptions(options));

  logFee(`${contractName} declare`, fee);
  return { alreadyDeclared: false, fee };
};

export const estimateInvoke = async ({ account, label, call, options = {} }) => {
  const fee = await account.estimateInvokeFee(call, txOptions(options));
  logFee(label, fee);
};
