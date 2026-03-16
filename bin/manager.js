import { exec } from 'node:child_process';
import util from 'node:util';
import ibis from '@influenceth/ibis';
import Account from '@influenceth/ibis/src/lib/Account.js';
import yargs from 'yargs'
import { hideBin } from 'yargs/helpers'

import ContractConfig from './lib/ContractConfig.js';
import updateContract from './lib/updateContract.js';
import updateDispatcher from './lib/updateDispatcher.js';
import updateSystem from './lib/updateSystem.js';

import combineAbis from './commands/combineAbis.js';
import seedAsteroids from './commands/seedAsteroids.js';
import seedCrewmates from './commands/seedCrewmates.js';
import seedOrders from './commands/seedOrders.js';
import updateConfigs from './commands/updateConfigs.js';
import updateConstant from './commands/updateConstant.js';
import cancelOrders from './commands/cancelOrders.js';

const buildHelper = async () => {
  const execPromise = util.promisify(exec);

  try {
    console.log('Building contracts...');
    const {stdout, stderr} = await execPromise('scarb build');
    console.log(stdout);
  } catch (error) {
    console.log(error);
  }
};

const DEFAULT_TX_RETRY_INTERVAL_MS = 500;
const DEFAULT_TX_LIFECYCLE_RETRIES = 20;

const applyFastWaitDefaults = (account) => {
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

const getDevnetPredeployedAccount = async (provider, index = 0) => {
  const rpcUrl = `${provider.baseUrl}/rpc`;
  const body = { jsonrpc: '2.0', id: 1, method: 'devnet_getPredeployedAccounts', params: [] };
  const response = await fetch(rpcUrl, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  const payload = await response.json();
  const accountInfo = payload?.result?.[index];

  if (!accountInfo?.address || !accountInfo?.private_key) {
    throw new Error('Unable to resolve devnet predeployed account #0 via devnet_getPredeployedAccounts');
  }

  return new Account(provider, accountInfo.address, accountInfo.private_key, 1);
};

// Resolve account from name or use default devnet predeployed account
const getAccount = async (accountName, networkName) => {
  let account;
  const { accounts, provider } = ibis(networkName);

  // Default to predeployed account #0 on devnet
  if (!accountName && networkName === 'devnet') {
    account = await getDevnetPredeployedAccount(provider, 0);
  } else {
    account = await accounts.account(accountName);
    if (!account) throw new Error(`Account ${accountName} not found`);
  }

  return applyFastWaitDefaults(account);
}

const buildTxOptions = ({ maxFee, tip }) => {
  const options = {};
  if (maxFee != null) options.maxFee = BigInt(maxFee);
  if (tip != null) options.tip = BigInt(tip);
  return options;
};

export const update = async ({ name, network, account, skipBuild, maxFee, tip }) => {
  if (!skipBuild) await buildHelper();

  try {
    const resolvedAccount = await getAccount(account, network);
    const config = new ContractConfig(network);
    const options = buildTxOptions({ maxFee, tip });

    if (config.isDispatcher(name)) await updateDispatcher(network, resolvedAccount, options);
    if (config.isSystem(name)) await updateSystem(name, network, resolvedAccount, options);
    if (config.isContract(name)) await updateContract(name, network, resolvedAccount, options);
  } catch (error) {
    console.error(error);
  }
};

export const updateAll = async ({ network, account, skipBuild, maxFee, tip }) => {
  if (!skipBuild) await buildHelper();

  try {
    const resolvedAccount = await getAccount(account, network);
    const options = buildTxOptions({ maxFee, tip });
    await updateDispatcher(network, resolvedAccount, options);
    const config = new ContractConfig(network);
    const contracts = config.getContracts();
    const systems = config.getSystems();

    for (const name of contracts) {
      await updateContract(name, network, resolvedAccount, options);
    }

    for (const name of systems) {
      await updateSystem(name, network, resolvedAccount, options);
    }
  } catch (error) {
    console.error(error);
  }
};

yargs(hideBin(process.argv))
  .command({
    command: 'update',
    desc: 'Declares, deploys and ugrades contracts and systems by name',
    help: true,
    builder: (y) => {
      y.version(false);
      y.option('name', { describe: 'Contract or system name ', demand: true });
      y.option('network', { describe: 'Network config ', alias: 'n', demand: true });
      y.option('account', { describe: 'Account to use', alias: 'a' });
      y.option('skipBuild', { describe: 'Skip building contracts before updating', alias: 's', type: 'boolean' });
      y.option('maxFee', { describe: 'Max fee for transactions', alias: 'm' });
      y.option('tip', { describe: 'Tip for v3 transactions', alias: 't' });
    },
    handler: update
  })
  .command({
    command: 'updateAll',
    desc: 'Declares, deploys and ugrades all contracts and systems',
    help: true,
    builder: (y) => {
      y.version(false);
      y.option('network', { describe: 'Network config ', alias: 'n', demand: true });
      y.option('account', { describe: 'Account to use', alias: 'a' });
      y.option('skipBuild', { describe: 'Skip building contracts before updating', alias: 's', type: 'boolean' });
      y.option('maxFee', { describe: 'Max fee for transactions', alias: 'm' });
      y.option('tip', { describe: 'Tip for v3 transactions', alias: 't' });
    },
    handler: updateAll
  })
  .command({
    command: 'seedAsteroids',
    desc: 'Register merkle root, mint asteroids and seed names / uniqueness',
    help: true,
    builder: (y) => {
      y.version(false);
      y.option('network', { describe: 'Network config ', alias: 'n', demand: true });
      y.option('account', { describe: 'Account to use', alias: 'a' })
    },
    handler: async ({ network, account }) => {
      const resolvedAccount = await getAccount(account, network);
      await seedAsteroids(network, resolvedAccount);
    }
  })
  .command({
    command: 'seedCrewmates',
    desc: 'Seeds crewmate names / uniqueness',
    help: true,
    builder: (y) => {
      y.version(false);
      y.option('network', { describe: 'Network config ', alias: 'n', demand: true });
      y.option('account', { describe: 'Account to use', alias: 'a' })
    },
    handler: async ({ network, account }) => {
      const resolvedAccount = await getAccount(account, network);
      await seedCrewmates(network, resolvedAccount);
    }
  })
  .command({
    command: 'seedOrders',
    desc: 'Seeds Adalia Prime orders',
    help: true,
    builder: (y) => {
      y.version(false);
      y.option('network', { describe: 'Network config ', alias: 'n', demand: true });
      y.option('account', { describe: 'Account to use', alias: 'a' })
    },
    handler: async ({ network, account }) => {
      const resolvedAccount = await getAccount(account, network);
      await seedOrders(network, resolvedAccount);
    }
  })
  .command({
    command: 'combineAbis',
    desc: 'Combines all ABIs into a single file',
    help: true,
    builder: (y) => {
      y.version(false);
      y.option('network', { describe: 'Network config ', alias: 'n', demand: true });
    },
    handler: combineAbis
  })
  .command({
    command: 'updateConfigs',
    builder: (y) => {
      y.version(false);
      y.option('network', { describe: 'Network config ', alias: 'n', demand: true });
      y.option('account', { describe: 'Account to use', alias: 'a' });
      y.options('type', { describe: 'Config type to update', alias: 't' });
    },
    handler: async ({ network, account, type }) => {
      const resolvedAccount = await getAccount(account, network);
      await updateConfigs(network, resolvedAccount, type);
    }
  })
  .command({
    command: 'updateConstant',
    desc: 'Update a constant value by name',
    builder: (y) => {
      y.version(false);
      y.option('network', { describe: 'Network config ', alias: 'n', demand: true });
      y.option('account', { describe: 'Account to use', alias: 'a' });
      y.option('name', { describe: 'Constant name', demand: true });
      y.option('value', { describe: 'New constant value', string: true, demand: true });
    },
    handler: async ({ network, account, name, value }) => {
      const resolvedAccount = await getAccount(account, network);
      await updateConstant({ network, account: resolvedAccount, name, value });
    }
  })
  .command({
    command: 'cancelOrders',
    desc: 'Cancel seeded orders',
    builder: (y) => {
      y.version(false);
      y.option('network', { describe: 'Network config ', alias: 'n', demand: true });
      y.option('account', { describe: 'Account to use', alias: 'a' });
    },
    handler: async ({ network, account }) => {
      const resolvedAccount = await getAccount(account, network);
      await cancelOrders(network, resolvedAccount);
    }
  })
  .help()
  .parse();
