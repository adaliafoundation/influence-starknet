# influence-starknet

## License
This project is licensed under the Creative Commons Attribution-NonCommercial 4.0 International License (CC BY-NC 4.0).

Commercial use is not permitted without a separate license from Unstoppable Games, Inc.

## Setup
- `npm install` (will run submodule update automatically)

## Build
- `npm run build`

## Testing
- Ensure that Docker Desktop is installed and started
- Build contracts (see above)
- `npm run test-contracts` (cairo tests)
- `npm run test-integration` (integration tests with Ibis)

### Integration Test Setup
- After changes to contracts, run `npm run build` to build the contracts
- Clear the `./test/seeds` directory
- Start devnet with `starknet-devnet --timeout 5000 --sierra-compiler-path /path/to/starknet-sierra-compile`
- Run `npm run manager updateAll -- --network devnet`
- When complete, run `curl -X POST http://127.0.0.1:5050/dump -d '{ "path": "/path/to/test/seeds/devnet.dump" }' -H "Content-Type: application/json"`
- Move `devnet.ibis.contracts.json` from `./cache` to `./test/seeds`
- Shutdown devnet

## Deploying

### The Dispatcher, contracts (NFTs, etc.) and systems are updated and registered using:
- `npm run manager update -- --name <contractName> --network <networkName> --account <accountName`
- `npm run manager updateAll -- --network <networkName> --account <accountName`

### Additional configuration requirements at "Mainnet Limited Release":
- manually run `add_grant` on `Asteroid` contract with `{ account: dispatcher.address, role: 2 }`
- manually run `add_grant` on `Crewmate` contract with `{ account: dispatcher.address, role: 2 }`
- manually run `add_grant` on `Crew` contract with `{ account: dispatcher.address, role: 2 }`
- manually `run_system` with `SeedHabitat` on `Dispatcher`
- manually set `Ether` contract via `register_contract` on `Dispatcher` to `0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7`
- manually set `ReceivablesAccount` via `register_contract` on `Dispatcher`

For asteroids:
- run `seedAsteroids` script via `npm run manager`
- manually `set_l1_bridge_address` on `Asteroid`
- manually `setL2BridgeContract` on L1 AsteroidBridge to L2 Asteroid address
- manually `setL2BridgeSelector` on L1 AsteroidBridge to `getSelector('bridge_from_l1')`
- manually set `ASTEROID_BASE_PRICE_ETH` constant via `register_constant` on `Dispatcher`
- manually set `ASTEROID_LOT_PRICE_ETH` constant via `register_constant` on `Dispatcher`

For crewmates:
- run `seedCrewmates` script via `npm run manager`
- manually `set_l1_bridge_address` on `Crewmate`
- manually `setL2BridgeContract` on L1 CrewmateBridge to L2 Crewmate address
- manually `setL2BridgeSelector` on L1 CrewmateBridge to `getSelector('bridge_from_l1')`
- manually set `ADALIAN_PRICE_ETH` constant via `register_constant` on `Dispatcher`

### Additional configuration requirements at "Mainnet":
- manually `add_grant` on `Ship` with `{ account: dispatcher.address, role: 2 }`
- manually `set_l1_bridge_address` on `Ship` with L1 ShipBridge proxy address
- manually `set_l1_bridge_address` on `Crew` with L1 CrewBridge proxy address
- manually `set_l1_bridge` on `Sway` with L1 SwayBridge address
- manually `set_l1_sway_volume_address` on `Sway` with L1 SwayVolume proxy address
- manaully `updateBeneficiary` on `SwayGovernor`

### At launch:
- ensure all constants are set: `TIME_ACCELERATION`, `ADALIAN_PRICE_ETH`, `ASTEROID_BASE_PRICE_ETH`, `ASTEROID_LOT_PRICE_ETH`
- manually set `LAUNCH_TIME` constant to the launch timestamp with `register_constant` on `Dispatcher
- manually `launch` Sway contract on L1
