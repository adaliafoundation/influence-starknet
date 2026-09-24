import { exec } from 'node:child_process';
import util from 'node:util';
import ibis from '@influenceth/ibis';
import Account from '@influenceth/ibis/src/lib/Account.js';
import { logger } from 'starknet';
import yargs from 'yargs'
import { hideBin } from 'yargs/helpers'

import ContractConfig from './lib/ContractConfig.js';
import { applyAccountDefaults } from './lib/accountDefaults.js';
import updateContract from './lib/updateContract.js';
import updateDispatcher from './lib/updateDispatcher.js';
import updateSystem from './lib/updateSystem.js';
import updateClass from './lib/updateClass.js';
import { createDryRunSummary, printDryRunSummary } from './lib/dryRun.js';

import combineAbis from './commands/combineAbis.js';
import seedAsteroids from './commands/seedAsteroids.js';
import seedCrewmates from './commands/seedCrewmates.js';
import seedOrders from './commands/seedOrders.js';
import updateConfigs from './commands/updateConfigs.js';
import updateConstant from './commands/updateConstant.js';
import cancelOrders from './commands/cancelOrders.js';
import cleanupLotTenancy from './commands/cleanupLotTenancy.js';
import { TENANCY_SYSTEMS } from './lib/staleLotTenancy.js';

logger.setLogLevel('WARN');

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

  return applyAccountDefaults(account);
}

const buildTxOptions = ({ maxFee, tip, dryRun, ignoreBaseline }) => {
  const options = {};
  if (maxFee != null) options.maxFee = BigInt(maxFee);
  if (tip != null) options.tip = BigInt(tip);
  if (dryRun) {
    options.dryRun = true;
    options.dryRunSummary = createDryRunSummary();
  }
  if (ignoreBaseline) options.ignoreBaseline = true;
  return options;
};

const normalizeNames = ({ name, names }) => {
  return [name, names]
    .flat()
    .filter(Boolean)
    .flatMap((value) => String(value).split(','))
    .map((value) => value.trim())
    .filter(Boolean);
};

const updateByName = async (name, network, account, options) => {
  const config = new ContractConfig(network);

  if (!config.config[name]) throw new Error(`Unknown contract or system ${name} on ${network}`);

  if (config.isDispatcher(name)) await updateDispatcher(network, account, options);
  if (config.isSystem(name)) await updateSystem(name, network, account, options);
  if (config.isContract(name)) await updateContract(name, network, account, options);
  if (config.isClass(name)) await updateClass(name, network, account, options);
};

export const update = async ({ name, names, network, account, skipBuild, maxFee, tip, dryRun, ignoreBaseline }) => {
  if (!skipBuild) await buildHelper();

  let options;
  try {
    const resolvedAccount = await getAccount(account, network);
    options = buildTxOptions({ maxFee, tip, dryRun, ignoreBaseline });
    const updateNames = normalizeNames({ name, names });

    for (const updateName of updateNames) {
      await updateByName(updateName, network, resolvedAccount, options);
    }
  } catch (error) {
    console.error(error);
    process.exitCode = 1;
  } finally {
    printDryRunSummary(options?.dryRunSummary);
  }
};

export const updateAll = async ({ network, account, skipBuild, maxFee, tip, dryRun, ignoreBaseline }) => {
  if (!skipBuild) await buildHelper();

  let options;
  try {
    const resolvedAccount = await getAccount(account, network);
    options = buildTxOptions({ maxFee, tip, dryRun, ignoreBaseline });
    await updateDispatcher(network, resolvedAccount, options);
    const config = new ContractConfig(network);
    const contracts = config.getContracts();
    const systems = config.getSystems();

    for (const name of config.getClasses()) {
      await updateClass(name, network, resolvedAccount, options);
    }

    for (const name of contracts) {
      await updateContract(name, network, resolvedAccount, options);
    }

    for (const name of systems) {
      if (config.config[name].skipUpdateAll) {
        console.log(`System ${name} excluded from updateAll; use update --name ${name} to update explicitly`);
        continue;
      }
      await updateSystem(name, network, resolvedAccount, options);
    }
  } catch (error) {
    console.error(error);
    process.exitCode = 1;
  } finally {
    printDryRunSummary(options?.dryRunSummary);
  }
};

yargs(hideBin(process.argv))
  .command({
    command: 'cleanupLotTenancy',
    desc: 'Clear verified stale UseLot records left by owner construction (dry run by default)',
    builder: (y) => y.version(false)
      .option('network', { describe: 'Network config', alias: 'n', type: 'string', demandOption: true })
      .option('account', { describe: 'Admin account; only needed with --apply', alias: 'a', type: 'string' })
      .option('input', { describe: 'JSON array of ConstructionPlanned transaction hashes to inspect', type: 'string' })
      .option('fromBlock', { describe: 'Discover planning transactions from this block through latest', type: 'number' })
      .option('output', { describe: 'Write the review report to this JSON file', type: 'string' })
      .option('apply', { describe: 'Submit verified cleanup writes during maintenance', type: 'boolean', default: false })
      .option('maxFee', { describe: 'Max fee per transaction', type: 'string' })
      .option('tip', { describe: 'Tip per transaction', type: 'string' })
      .check((argv) => {
        if (Boolean(argv.input) === (argv.fromBlock !== undefined)) throw new Error('Provide exactly one of --input or --fromBlock');
        if (argv.fromBlock !== undefined && (!Number.isSafeInteger(argv.fromBlock) || argv.fromBlock < 0)) {
          throw new Error('--fromBlock must be a nonnegative integer');
        }
        return true;
      })
      .epilog(`Requires archival storage and block receipts. Does not infer staleness from current ownership.\nBefore --apply, deploy the ConstructionPlan/RepossessBuilding fixes and unregister (class hash 0) these systems:\n${TENANCY_SYSTEMS.join(', ')}.\nKeep them paused until cleanup completes, then restore their registered hashes. This command does not pause or resume systems.\nOnly UseLot is cleared; agreements and buildings are preserved. Save --output for review and retain transaction hashes.`),
    handler: async (args) => {
      try {
        const account = args.apply ? await getAccount(args.account, args.network) : undefined;
        await cleanupLotTenancy({ ...args, account });
      } catch (error) {
        console.error(error);
        process.exitCode = 1;
      }
    }
  })
  .command({
    command: 'update',
    desc: 'Declares, deploys and ugrades contracts and systems by name',
    help: true,
    builder: (y) => {
      y.version(false);
      y.option('name', { describe: 'Contract or system name. Can be repeated or comma-separated.', array: true });
      y.option('names', { describe: 'Comma-separated contract/system names.' });
      y.option('network', { describe: 'Network config ', alias: 'n', demand: true });
      y.option('account', { describe: 'Account to use', alias: 'a' });
      y.option('skipBuild', { describe: 'Skip building contracts before updating', alias: 's', type: 'boolean' });
      y.option('maxFee', { describe: 'Max fee for transactions', alias: 'm' });
      y.option('tip', { describe: 'Tip for v3 transactions', alias: 't' });
      y.option('dryRun', { describe: 'Estimate declarations and invokes without submitting transactions', type: 'boolean' });
      y.option('ignoreBaseline', { describe: 'Ignore accepted baseline hashes when deciding whether to update', type: 'boolean' });
      y.check((argv) => {
        if (normalizeNames(argv).length === 0) throw new Error('At least one --name or --names value is required');
        return true;
      });
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
      y.option('dryRun', { describe: 'Estimate declarations and invokes without submitting transactions', type: 'boolean' });
      y.option('ignoreBaseline', { describe: 'Ignore accepted baseline hashes when deciding whether to update', type: 'boolean' });
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
