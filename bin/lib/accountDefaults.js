const DEFAULT_TX_RETRY_INTERVAL_MS = 500;
const DEFAULT_TX_LIFECYCLE_RETRIES = 20;
const DEFAULT_TIP_MAX_BLOCKS = 20;

export const applyAccountDefaults = (account) => {
  const originalGetNonce = account.getNonce.bind(account);
  // Include transactions in the block being built when choosing the next nonce.
  account.getNonce = (blockIdentifier = 'pre_confirmed') => originalGetNonce(blockIdentifier);

  const originalGetEstimateTip = account.getEstimateTip.bind(account);
  account.getEstimateTip = (blockIdentifier, options = {}) => originalGetEstimateTip(blockIdentifier, {
    maxBlocks: DEFAULT_TIP_MAX_BLOCKS,
    ...options
  });

  const originalWaitForTransaction = account.waitForTransaction.bind(account);
  account.waitForTransaction = (txHash, options = {}) => {
    return originalWaitForTransaction(txHash, {
      retryInterval: DEFAULT_TX_RETRY_INTERVAL_MS,
      lifeCycleRetries: DEFAULT_TX_LIFECYCLE_RETRIES,
      ...options
    });
  };
  return account;
};

