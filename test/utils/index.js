import ibis from '@influenceth/ibis';
import { Entity } from '@influenceth/sdk';
import { expect } from 'chai';
import { shortString } from 'starknet';

const SCALE = 2n ** 61n;
const PRIME = 3618502788666131213697322783095070105623107215331596699973092056135872020481n;
const PRIME_HALF = PRIME / 2n;
const PI = 7244019458077122842n;

const getAccounts = async function ({ count = 5 }) {
  const { accounts } = ibis('devnet');
  const results = [];

  for (let i = 0; i < count; i++) {
    const account = await accounts.predeployedAccount(i);
    results.push(account);
  }

  return results;
};

const assertReverts = async function (promise, expectedError) {
  let reverted = false;

  try {
    await promise;
  } catch (error) {
    reverted = true;
    const hexMessage = shortString.encodeShortString(expectedError);
    expect(error.message).to.deep.contain.oneOf([ hexMessage, expectedError ]);
  }

  if (!reverted) expect.fail(`Test expected to revert with: ${expectedError}`);
};

const declareAndRegisterSystem = async (name, account) => {
  const { contracts } = ibis('devnet');
  const { class_hash } = await contracts.declare(name);
  const dispatcher = contracts.deployed('Dispatcher');
  dispatcher.connect(account);
  await dispatcher.compileAndInvoke('register_system', { name: shortString.encodeShortString(name), class_hash });
};

const readComponent = async (component, path) => {
  const { contracts, provider } = ibis('devnet');
  const dispatcher = contracts.deployed('Dispatcher');
  dispatcher.connect(provider);

  const flatPath = path.map(p => typeof p === 'object' ? Entity.packEntity(p) : p);
  let res = await dispatcher.compileAndCall('run_system', {
    name: shortString.encodeShortString('ReadComponent'),
    calldata: [ shortString.encodeShortString(component), flatPath.length, ...flatPath ]
  });

  return res;
};

export {
  PI,
  PRIME_HALF,
  PRIME,
  SCALE,
  assertReverts,
  declareAndRegisterSystem,
  getAccounts,
  readComponent
};