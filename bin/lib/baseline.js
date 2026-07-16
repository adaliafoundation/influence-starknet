import fs from 'fs';
import path from 'path';

const normalizeHash = (value) => {
  if (!value) return null;
  return `0x${BigInt(value).toString(16)}`;
};

export const isBaselineIgnored = (options = {}) => {
  return Boolean(options.ignoreBaseline || options.force);
};

export const cacheEntryForContract = (contracts, contractName) => {
  const artifact = contracts.artifacts.find((item) => item.contract_name === contractName);
  const artifactKey = artifact ? `${artifact.package_name}.${artifact.contract_name}.${artifact.id}` : null;

  if (artifactKey && contracts.cache[artifactKey]) {
    return { key: artifactKey, entry: contracts.cache[artifactKey] };
  }

  const matches = Object.entries(contracts.cache).filter(([key]) => {
    return key.split('.')[1] === contractName;
  });

  if (matches.length !== 1) return null;

  const [key, entry] = matches[0];
  return { key, entry };
};

export const isAcceptedBaseline = ({
  contracts,
  contractName,
  actualClassHash,
  computedClassHash,
  options = {}
}) => {
  if (isBaselineIgnored(options)) return false;

  const cached = cacheEntryForContract(contracts, contractName);
  const baseline = cached?.entry?.baseline;

  if (!baseline) return false;

  const acceptedHash = normalizeHash(baseline.acceptedClassHash);
  const baselineHash = normalizeHash(baseline.classHash);

  if (
    acceptedHash === normalizeHash(actualClassHash)
    && baselineHash === normalizeHash(computedClassHash)
  ) {
    console.log(
      `${contractName} skipped by accepted baseline: ` +
      `${actualClassHash} accepted for local hash ${computedClassHash}`
    );
    return true;
  }

  return false;
};

export const updateAcceptedBaseline = ({
  contracts,
  contractName,
  classHash,
  reason = 'updated on-chain class hash'
}) => {
  const cached = cacheEntryForContract(contracts, contractName);

  if (!cached) return;

  cached.entry.baseline = {
    acceptedClassHash: classHash,
    classHash,
    updatedAt: new Date().toISOString(),
    reason
  };

  cached.entry.classHash = classHash;

  const file = path.resolve(
    contracts.config.contractsConfig.cache,
    `${contracts.config.network}.ibis.contracts.json`
  );

  fs.writeFileSync(
    file,
    `${JSON.stringify(contracts.cache, (key, value) => typeof value === 'bigint' ? value.toString() : value, 2)}\n`
  );
};
