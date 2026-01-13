import ibis from '@influenceth/ibis';
import updateBuildings from '../lib/updateBuildings.js';
import updateConstants from '../lib/updateConstants.js';
import updateDocks from '../lib/updateDocks.js';
import updateDryDocks from '../lib/updateDryDocks.js';
import updateExchanges from '../lib/updateExchanges.js';
import updateInventories from '../lib/updateInventories.js';
import updateModifiers from '../lib/updateModifiers.js';
import updateProcesses from '../lib/updateProcesses.js';
import updateProducts from '../lib/updateProducts.js';
import updateShips from '../lib/updateShips.js';
import updateShipVariants from '../lib/updateShipVariants.js';
import updateStations from '../lib/updateStations.js';

const updateConfigs = async (network, account, type) => {
  const { contracts } = ibis(network);
  const dispatcher = contracts.deployed('Dispatcher');
  dispatcher.connect(account);

  switch (type) {
    case 'constants':
      await updateConstants(dispatcher, account);
      break;
    case 'buildings':
      await updateBuildings(dispatcher, account);
      break;
    case 'docks':
      await updateDocks(dispatcher, account);
      break;
    case 'dryDocks':
      await updateDryDocks(dispatcher, account);
      break;
    case 'exchanges':
      await updateExchanges(dispatcher, account);
      break;
    case 'inventories':
      await updateInventories(dispatcher, account);
      break;
    case 'modifiers':
      await updateModifiers(dispatcher, account);
      break;
    case 'processes':
      await updateProcesses(dispatcher, account);
      break;
    case 'products':
      await updateProducts(dispatcher, account);
      break;
    case 'ships':
      await updateShips(dispatcher, account);
      break;
    case 'shipVariants':
      await updateShipVariants(dispatcher, account);
      break;
    case 'stations':
      await updateStations(dispatcher, account);
      break;
    case 'all':
      await updateConstants(dispatcher, account);
      await updateBuildings(dispatcher, account);
      await updateDocks(dispatcher, account);
      await updateDryDocks(dispatcher, account);
      await updateExchanges(dispatcher, account);
      await updateInventories(dispatcher, account);
      await updateModifiers(dispatcher, account);
      await updateProcesses(dispatcher, account);
      await updateProducts(dispatcher, account);
      await updateShips(dispatcher, account);
      await updateShipVariants(dispatcher, account);
      await updateStations(dispatcher, account);
      break;
    default:
      return;
  }
};

export default updateConfigs;