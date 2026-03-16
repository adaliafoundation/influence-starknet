# influence-starknet

## License
This project is licensed under the Creative Commons Attribution-NonCommercial 4.0 International License (CC BY-NC 4.0).
Commercial use is not permitted without a separate license from Unstoppable Games, Inc.

For the avoidance of doubt:
The licensor considers non-commercial use under this license to include deployments or uses that collect funds solely to recover the reasonable costs of operating, maintaining, or administering the software, provided that such use is not primarily intended for or directed toward commercial advantage or monetary compensation, and that no profit is distributed to operators, contributors, or participants.

## Environment prerequisites

This project uses historical version 2.1.1 of [cairo](https://github.com/starkware-libs/cairo/tree/v2.1.1),
0.6.2 of [scarb](https://github.com/software-mansion/scarb/tree/release/v0.6.2) and 1.76.0 of Rust. These cairo and
scarb versions are no longer readily available using the https://sh.starkup.sh path. We need to build them using Rust.

Rust is easiest obtained by installing [rustup](https://rustup.rs/). This tool allows you to obtain complete toolchains
for specific versions of Rust. After install, invoke the following commands to set your local environment to use version
1.76.0 of Rust:

    rustup toolchain install 1.76.0
    rustup override set 1.76.0

To build cairo:

    git clone https://github.com/starkware-libs/cairo.git
    cd cairo
    git checkout v2.1.1
    cargo build --all --release

To build scarb:

    git clone https://github.com/software-mansion/scarb.git
    cd scarb
    git checkout v0.6.2
    cargo build --all --release

You need to set `$PATH_TO_CAIRO/target/release` and `$PATH_TO_SCARB/target/release` directories into your `PATH`
environment variable to be able to easily access the cairo and scarb CLI commands.

Environment should be now set up for proceeding with building the project and running test-contracts.

## Setup

- `npm install` (will run submodule update automatically to obtain the dependency library `cubit`)
- Must setup `.env` to include `SIERRA_COMPILER_PATH`, currently dependent on v2.1.1
- Relies on `starknet-devnet` version 0.7.2 to be installed in local `pyenv` for integration testing
- Unzip `devnet.dump.zip` in `./test/seeds` to `./test/seeds/devnet.dump` for integration testing

## Build

This step depends on the cairo and scarb builds to be accessible in your `PATH`.

- `npm run build`

## Contract unit tests

This step depends on the `cairo-test` command from the cairo build to be accessible in your `PATH`.

- `npm run test-contracts`

## Integration testing

- Ensure that Docker Desktop is installed and started
- Build contracts (see above)
- `npm run test-integration` (integration tests with Ibis)

### Integration Test Setup
- After changes to contracts, run `npm run build` to build the contracts
- Clear the `./test/seeds` directory
- Start devnet with `starknet-devnet --timeout 5000 --seed 12345 --initial-balance 10000000000000000000000000 --dump-path ./test/seeds/devnet.dump --dump-on exit`
- Run `npm run manager updateAll -- --network devnet`
- Run `npm run manager updateConfigs -- --network devnet --type all`
- When complete, exit with `CTRL+C` to generate the `devnet.dump` file in `./test/seeds`
- Move `devnet.ibis.contracts.json` from `./cache` to `./test/seeds`

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
