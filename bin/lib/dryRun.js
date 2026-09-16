const FRI_PER_STRK = 10n ** 18n;

export const isDryRun = (options = {}) => {
  return Boolean(options.dryRun || options.estimate);
};

export const txOptions = (options = {}) => {
  const { dryRun, estimate, ignoreBaseline, force, dryRunSummary, ...rest } = options;
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

export const createDryRunSummary = () => ({
  systems: new Set(),
  estimates: [],
  unestimated: []
});

export const recordDryRunSystem = (options = {}, systemName) => {
  if (!options.dryRunSummary || !systemName) return;
  options.dryRunSummary.systems.add(systemName);
};

export const recordUnestimatedDryRunFee = (options = {}, label, reason) => {
  if (!options.dryRunSummary) return;
  options.dryRunSummary.unestimated.push({ label, reason });
};

export const printDryRunSummary = (summary) => {
  if (!summary) return;

  const totalFri = summary.estimates.reduce((sum, estimate) => sum + BigInt(estimate.amount), 0n);
  console.log('');
  console.log('[dry-run] Summary');
  console.log(`[dry-run] Systems with pending updates: ${summary.systems.size}`);
  console.log(`[dry-run] Estimated transactions: ${summary.estimates.length}`);
  console.log(`[dry-run] Estimated total fee: ${formatFriAsStrk(totalFri)} (${totalFri} fri)`);

  if (summary.unestimated.length > 0) {
    console.log(`[dry-run] Unestimated transactions: ${summary.unestimated.length}`);
    for (const { label, reason } of summary.unestimated) {
      console.log(`[dry-run] - ${label}: ${reason}`);
    }
  }
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

const recordFee = (options, label, fee) => {
  if (!options.dryRunSummary) return;
  options.dryRunSummary.estimates.push({ label, amount: BigInt(feeAmount(fee)) });
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
  recordFee(options, `${contractName} declare`, fee);
  return { alreadyDeclared: false, fee };
};

export const estimateInvoke = async ({ account, label, call, options = {} }) => {
  const fee = await account.estimateInvokeFee(call, txOptions(options));
  logFee(label, fee);
  recordFee(options, label, fee);
  return fee;
};
