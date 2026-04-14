# Influence Starknet - Codebase Summary

## What Is This?

Influence is a **space-mining MMO game** built on Starknet (an Ethereum L2). This repository contains the on-chain smart contracts (written in Cairo) and JavaScript tooling for deploying, configuring, and testing them. The game models asteroid mining, spaceship logistics, crew management, resource extraction, manufacturing, and a player-driven economy -- all enforced on-chain with real orbital mechanics.

**Author:** Unstoppable Games, Inc.  
**License:** CC BY-NC 4.0  
**Stack:** Cairo 2.1 (Scarb), Starknet, Node.js (deployment tooling), Mocha (integration tests)

---

## Folder & File Hierarchy

```
influence-starknet/
|
|-- src/                          # Cairo smart contracts (the core of the repo)
|   |-- lib.cairo                 # Root module: exports common, components, contracts, entities, systems
|   |
|   |-- common/                   # Shared utilities & game logic libraries
|   |   |-- common.cairo          # Module index
|   |   |-- access.cairo          # Permission resolution (public policies, whitelists, agreements, delegates)
|   |   |-- crew.cairo            # Crew bonus/efficiency calculation (food, traits, station population)
|   |   |-- inventory.cairo       # Inventory mass/volume tracking, reservations, product masks
|   |   |-- math.cairo            # Rounded division, power-of-2 lookups
|   |   |-- nft.cairo             # NFT utility functions
|   |   |-- packed.cairo          # Bit-packing helpers for compact storage
|   |   |-- position.cairo        # Geodetic positioning on asteroids, travel time calculations
|   |   |-- propulsion.cairo      # Propellant cost & exhaust velocity calculations
|   |   |-- random.cairo          # Commit-reveal randomness (entropy or blockhash strategies)
|   |   |-- astro/                # Orbital mechanics
|   |   |   |-- angles.cairo      # Angle conversions (true anomaly, eccentric anomaly, mean anomaly)
|   |   |   |-- elements.cairo    # Keplerian orbital elements
|   |   |   |-- propagation.cairo # Orbit propagation over time
|   |   |-- config/               # Game configuration & constants
|   |   |   |-- actions.cairo     # Action type definitions
|   |   |   |-- entities.cairo    # Entity type constants (ASTEROID, CREW, SHIP, etc.)
|   |   |   |-- errors.cairo      # Error code constants
|   |   |   |-- noise.cairo       # Noise generation for procedural content
|   |   |   |-- permissions.cairo # Permission type definitions
|   |   |   |-- random_events.cairo # Random event configuration
|   |   |   |-- resource_bonuses.cairo # Resource bonus tables
|   |   |-- types/                # Core type definitions
|   |       |-- array.cairo       # Array utilities
|   |       |-- context.cairo     # Context struct (caller, timestamp, payment)
|   |       |-- entity.cairo      # Entity struct (label + id, bit-packed)
|   |       |-- inventory_item.cairo # Inventory item struct
|   |       |-- merkle_tree.cairo # Merkle tree verification
|   |       |-- string.cairo      # String utilities
|   |
|   |-- components/               # ECS data components (game state storage)
|   |   |-- components.cairo      # Module index
|   |   |-- account.cairo         # Account component
|   |   |-- agreements/           # Access agreement components
|   |   |   |-- contract.cairo    # Contract-based agreement
|   |   |   |-- prepaid.cairo     # Time-limited prepaid agreement
|   |   |   |-- whitelist.cairo   # Whitelist-based agreement
|   |   |-- asteroid_sale.cairo   # Asteroid sale state
|   |   |-- building.cairo        # Building status, type, timestamps
|   |   |-- building_type.cairo   # Building type definitions
|   |   |-- celestial.cairo       # Asteroid metadata (mass, radius, scan status, resources)
|   |   |-- control.cairo         # Entity control (which crew controls what)
|   |   |-- crew.cairo            # Crew roster, delegation, food, action tracking
|   |   |-- crewmate.cairo        # Crewmate attributes (class, traits, appearance)
|   |   |-- delivery.cairo        # Delivery tracking
|   |   |-- deposit.cairo         # Resource deposit state
|   |   |-- dock.cairo            # Docking bay state
|   |   |-- dock_type.cairo       # Dock type definitions
|   |   |-- dry_dock.cairo        # Ship assembly bay state
|   |   |-- dry_dock_type.cairo   # Dry dock type definitions
|   |   |-- exchange.cairo        # Marketplace exchange state
|   |   |-- exchange_type.cairo   # Exchange type definitions
|   |   |-- extractor.cairo       # Resource extractor state
|   |   |-- extractor_type.cairo  # Extractor type definitions
|   |   |-- inventory.cairo       # Inventory contents, mass/volume, reservations
|   |   |-- inventory_type.cairo  # Inventory type definitions
|   |   |-- location.cairo        # Hierarchical location (entity -> parent entity)
|   |   |-- modifier_type.cairo   # Modifier type definitions
|   |   |-- name.cairo            # Nameable entity component
|   |   |-- orbit.cairo           # Orbital elements (a, e, i, omega, etc.)
|   |   |-- order.cairo           # Buy/sell order state
|   |   |-- policies/             # Access policy components
|   |   |   |-- contract.cairo    # Contract-based policy
|   |   |   |-- prepaid.cairo     # Prepaid policy
|   |   |   |-- prepaid_merkle.cairo # Merkle-proof prepaid policy
|   |   |   |-- public.cairo      # Public access policy
|   |   |-- private_sale.cairo    # Private sale state
|   |   |-- processor.cairo       # Manufacturing processor state
|   |   |-- process_type.cairo    # Process type definitions
|   |   |-- product_type.cairo    # Product type definitions
|   |   |-- ship.cairo            # Ship status, transit state, emergency mode
|   |   |-- ship_type.cairo       # Ship type definitions
|   |   |-- ship_variant_type.cairo # Ship variant definitions
|   |   |-- station.cairo         # Station state (population, etc.)
|   |   |-- station_type.cairo    # Station type definitions
|   |   |-- unique.cairo          # Uniqueness tracking
|   |
|   |-- contracts/                # Deployable Starknet contracts
|   |   |-- contracts.cairo       # Module index
|   |   |-- dispatcher.cairo      # Central registry & router (constants, contracts, systems, grants)
|   |   |-- asteroid.cairo        # Asteroid NFT (ERC721)
|   |   |-- crew.cairo            # Crew NFT (ERC721)
|   |   |-- crewmate.cairo        # Crewmate NFT (ERC721)
|   |   |-- ship.cairo            # Ship NFT (ERC721)
|   |   |-- sway.cairo            # SWAY token (ERC20, in-game currency)
|   |   |-- escrow.cairo          # Token escrow for transactions
|   |   |-- ether.cairo           # ETH/L1 bridge handling
|   |   |-- contract_policy.cairo # External contract policy interface
|   |   |-- designate.cairo       # Delegation/designation contract
|   |
|   |-- entities.cairo            # Entity ID generation (scoped auto-increment per entity type)
|   |
|   |-- interfaces/               # External contract interfaces (traits)
|   |   |-- contract_policy.cairo # IContractPolicy interface
|   |   |-- erc165.cairo          # ERC165 introspection
|   |   |-- erc20.cairo           # ERC20 token interface
|   |   |-- erc721.cairo          # ERC721 NFT interface
|   |   |-- escrow.cairo          # IEscrow interface
|   |
|   |-- systems/                  # Game logic (stateless system contracts)
|   |   |-- systems.cairo         # Module index
|   |   |-- helpers.cairo         # CrewDetailsTrait: lazy-loading crew hierarchy, modifiers, food
|   |   |-- agreements/           # Access agreement management
|   |   |   |-- accept_contract.cairo
|   |   |   |-- accept_prepaid.cairo
|   |   |   |-- accept_prepaid_merkle.cairo
|   |   |   |-- cancel_prepaid.cairo
|   |   |   |-- extend_prepaid.cairo
|   |   |   |-- remove_account_from_whitelist.cairo
|   |   |   |-- remove_from_whitelist.cairo
|   |   |   |-- transfer_prepaid.cairo
|   |   |   |-- whitelist.cairo
|   |   |   |-- whitelist_account.cairo
|   |   |-- construction/         # Building construction lifecycle
|   |   |   |-- construction_plan.cairo     # Reserve lot, create building entity
|   |   |   |-- construction_start.cairo    # Begin construction with materials
|   |   |   |-- construction_finish.cairo   # Complete construction
|   |   |   |-- construction_deconstruct.cairo # Tear down building
|   |   |   |-- construction_abandon.cairo  # Abandon planned construction
|   |   |-- control/              # Entity ownership & control
|   |   |   |-- commandeer_ship.cairo       # Take control of a ship
|   |   |   |-- manage_asteroid.cairo       # Manage asteroid operations
|   |   |   |-- repossess_building.cairo    # Reclaim a building
|   |   |-- crew/                 # Crew management
|   |   |   |-- arrange_crew.cairo          # Rearrange crewmate roster
|   |   |   |-- delegate_crew.cairo         # Delegate crew control to address
|   |   |   |-- eject_crew.cairo            # Eject crew from location
|   |   |   |-- exchange_crew.cairo         # Swap crewmates between crews
|   |   |   |-- initialize_arvadian.cairo   # Initialize Arvadian crewmate
|   |   |   |-- recruit_adalian.cairo       # Mint new Adalian crew + crewmate NFTs
|   |   |   |-- resupply_food.cairo         # Resupply food from inventory
|   |   |   |-- resupply_food_from_exchange.cairo # Resupply food from marketplace
|   |   |   |-- station_crew.cairo          # Station crew at a building
|   |   |-- deliveries/           # Item delivery system
|   |   |   |-- send.cairo        # Send delivery
|   |   |   |-- accept.cairo      # Accept incoming delivery
|   |   |   |-- cancel.cairo      # Cancel delivery
|   |   |   |-- dump.cairo        # Dump delivery contents
|   |   |   |-- package.cairo     # Package items for delivery
|   |   |   |-- receive.cairo     # Receive delivery at destination
|   |   |-- deposits/             # Resource deposit management
|   |   |   |-- sample_start.cairo   # Begin sampling a deposit
|   |   |   |-- sample_improve.cairo # Improve sample quality
|   |   |   |-- sample_finish.cairo  # Complete sampling
|   |   |   |-- abundance.cairo      # Resource abundance calculations
|   |   |   |-- list_for_sale.cairo  # List deposit for sale
|   |   |   |-- purchase.cairo       # Purchase a deposit
|   |   |   |-- unlist_for_sale.cairo
|   |   |-- emergencies/          # Emergency mode
|   |   |   |-- activate_emergency.cairo
|   |   |   |-- collect_emergency_propellant.cairo
|   |   |   |-- deactivate_emergency.cairo
|   |   |-- orders/               # Marketplace buy/sell orders
|   |   |   |-- create_sell.cairo    # Create sell order
|   |   |   |-- fill_sell.cairo      # Fill sell order (buy)
|   |   |   |-- cancel_sell.cairo    # Cancel sell order
|   |   |   |-- create_buy.cairo     # Create buy order
|   |   |   |-- fill_buy.cairo       # Fill buy order (sell)
|   |   |-- policies/             # Access policy assignment
|   |   |   |-- assign_public.cairo
|   |   |   |-- assign_contract.cairo
|   |   |   |-- assign_prepaid.cairo
|   |   |   |-- assign_prepaid_merkle.cairo
|   |   |   |-- remove_public.cairo
|   |   |   |-- remove_contract.cairo
|   |   |   |-- remove_prepaid.cairo
|   |   |   |-- remove_prepaid_merkle.cairo
|   |   |-- production/           # Resource extraction & manufacturing
|   |   |   |-- extract_resource_start.cairo  # Start mining a resource
|   |   |   |-- extract_resource_finish.cairo # Complete mining
|   |   |   |-- process_products_start.cairo  # Start manufacturing
|   |   |   |-- process_products_finish.cairo # Complete manufacturing
|   |   |   |-- assemble_ship_start.cairo     # Start ship assembly
|   |   |   |-- assemble_ship_finish.cairo    # Complete ship assembly
|   |   |-- random_events/        # Procedural random events
|   |   |   |-- check_for.cairo              # Check if random event triggers
|   |   |   |-- resolve.cairo                # Resolve triggered event
|   |   |   |-- always_leave_a_note.cairo    # Specific event types...
|   |   |   |-- fly_me_to_the_moon.cairo
|   |   |   |-- greatness.cairo
|   |   |   |-- groundbreaking.cairo
|   |   |   |-- keep_em_separated.cairo
|   |   |   |-- no_sound_in_space.cairo
|   |   |   |-- stardust.cairo
|   |   |   |-- the_cake_is_a_half_truth.cairo
|   |   |-- rewards/              # Reward claiming
|   |   |   |-- claim_arrival.cairo
|   |   |   |-- claim_prepare_for_launch.cairo
|   |   |   |-- claim_testnet.cairo
|   |   |-- sales/                # In-game purchases
|   |   |   |-- grant_adalians.cairo
|   |   |   |-- grant_starter_pack.cairo
|   |   |   |-- purchase_adalian.cairo
|   |   |   |-- purchase_asteroid.cairo
|   |   |-- scanning/             # Asteroid scanning
|   |   |   |-- scan_resources_start.cairo
|   |   |   |-- scan_resources_finish.cairo
|   |   |   |-- scan_surface_start.cairo
|   |   |   |-- scan_surface_finish.cairo
|   |   |-- seeding/              # Initial world state setup
|   |   |   |-- initialize_asteroid.cairo
|   |   |   |-- seed_asteroids.cairo
|   |   |   |-- seed_colony.cairo
|   |   |   |-- seed_crewmates.cairo
|   |   |   |-- seed_habitat.cairo
|   |   |   |-- seed_orders.cairo
|   |   |-- ship/                 # Ship operations
|   |   |   |-- dock_ship.cairo
|   |   |   |-- undock_ship.cairo
|   |   |   |-- transit_between_start.cairo  # Begin interplanetary travel
|   |   |   |-- transit_between_finish.cairo # Arrive at destination
|   |   |-- annotate_event.cairo  # Event annotation
|   |   |-- change_name.cairo     # Rename entities
|   |   |-- configure_exchange.cairo # Configure marketplace exchanges
|   |   |-- direct_message.cairo  # Player-to-player messaging
|   |   |-- read_component.cairo  # Generic component reader
|   |   |-- rekey_inbox.cairo     # Re-key messaging inbox
|   |   |-- type_component.cairo  # Type component operations
|   |   |-- write_component.cairo # Generic component writer
|   |
|   |-- test/                     # Cairo test utilities
|       |-- test.cairo            # Test module index
|       |-- helpers.cairo         # Test helper functions
|       |-- mocks.cairo           # Mock data (asteroids, crews, crewmates)
|
|-- bin/                          # JavaScript deployment & management CLI
|   |-- manager.js                # CLI entry point (yargs commands)
|   |-- commands/                 # CLI commands
|   |   |-- cancelOrders.js       # Cancel existing orders
|   |   |-- combineAbis.js        # Extract & combine ABIs for frontend
|   |   |-- fixFeatures.js        # Repair feature data
|   |   |-- fixInventories.js     # Repair inventory data
|   |   |-- fixStations.js        # Repair station data
|   |   |-- seedAsteroids.js      # Seed asteroid data (from IPFS snapshot)
|   |   |-- seedCrewmates.js      # Seed crewmate NFTs
|   |   |-- seedOrders.js         # Seed marketplace orders
|   |   |-- updateConfigs.js      # Update game constants from SDK
|   |   |-- updateConstant.js     # Update individual constants
|   |-- lib/                      # Shared deployment logic
|       |-- ContractConfig.js     # Load network-specific config from influence.config.js
|       |-- updateBuildings.js    # Register building type configs
|       |-- updateConstants.js    # Batch update game constants
|       |-- updateContract.js     # Declare/deploy/upgrade contracts
|       |-- updateDispatcher.js   # Deploy/upgrade Dispatcher
|       |-- updateDocks.js        # Register dock type configs
|       |-- updateDryDocks.js     # Register dry dock type configs
|       |-- updateExchanges.js    # Register exchange type configs
|       |-- updateInventories.js  # Register inventory type configs
|       |-- updateModifiers.js    # Register modifier type configs
|       |-- updateProcesses.js    # Register process type configs
|       |-- updateProducts.js     # Register product type configs
|       |-- updateShips.js        # Register ship type configs
|       |-- updateShipVariants.js # Register ship variant configs
|       |-- updateStations.js     # Register station type configs
|       |-- updateSystem.js       # Declare/register systems
|       |-- utils.js              # Constructor arg parsing, helpers
|
|-- cache/                        # Deployed contract metadata (addresses, class hashes)
|   |-- mainnet.ibis.contracts.json
|   |-- sepolia.ibis.contracts.json
|   |-- testnet.ibis.contracts.json
|
|-- test/                         # JavaScript integration tests
|   |-- exploitation.spec.js      # Exploitation phase tests (stub)
|   |-- limitedRelease.spec.js    # Limited release tests (L1/L2 bridging, merkle proofs)
|   |-- preRelease.spec.js        # Pre-release tests (stub)
|   |-- seeds/                    # Deterministic devnet state for tests
|   |   |-- devnet.dump           # Devnet snapshot (binary)
|   |   |-- devnet.ibis.contracts.json  # Contract addresses for test devnet
|   |-- utils/
|       |-- index.js              # Test helpers (getAccounts, assertReverts, readComponent)
|       |-- setup.js              # Devnet lifecycle (start/stop, load seed state)
|
|-- .github/workflows/test.yaml  # CI: build Cairo from source, run contract tests
|-- influence.config.js           # Network configs: contract constructor args, system registrations
|-- Scarb.toml                    # Cairo package config (dependencies: starknet, cubit)
|-- cairo_project.toml            # Cairo project roots
|-- package.json                  # Node.js dependencies & scripts
|-- .nvmrc                        # Node version (18)
|-- .gitmodules                   # Git submodules (vendor/cubit)
```

---

## Architecture: Entity-Component-System (ECS)

The codebase follows an **ECS pattern** adapted for Starknet:

### Entities
- Every game object (asteroid, crew, ship, building, lot, order, etc.) is an `Entity(label, id)` -- a type tag plus a scoped numeric ID, bit-packed into a single `u128`/`felt252`.
- Entity IDs auto-increment per type via `src/entities.cairo`.

### Components
- Components are pure data attached to entities. Each component has `get()`/`set()` functions that read/write to storage keyed by entity path hashes.
- Examples: a Ship entity has `Ship`, `Inventory`, `Location`, `Orbit`, `Control`, and `Name` components.
- Components emit `ComponentUpdated` events on every write for off-chain indexing.

### Systems
- Systems are **stateless contracts** containing game logic. They are registered with the Dispatcher and invoked via `dispatcher.run_system(system_name, calldata)`.
- Each system reads components, validates permissions, performs calculations, and writes updated components.
- Systems never store state themselves -- all state lives in components.

### Dispatcher (Central Router)
- The `Dispatcher` contract is the hub. It stores:
  - **Constants**: game parameters (time acceleration, prices, thresholds)
  - **Contract addresses**: NFT contracts, ERC20 tokens, escrow
  - **System class hashes**: registered system implementations
  - **Grants**: role-based admin permissions
- All system calls are routed through the Dispatcher via `library_call_syscall`.

---

## Main Flows

### 1. Deployment & Configuration Flow
```
scarb build  -->  JS manager declares Sierra contracts on-chain
                  --> deploys Dispatcher, NFT contracts (Asteroid, Crew, Crewmate, Ship), Sway token
                  --> registers all systems with Dispatcher
                  --> updates game constants (from @influenceth/sdk)
                  --> registers type configs (buildings, ships, processes, products, etc.)
                  --> seeds initial world state (asteroids from IPFS, crewmates, orders)
```

### 2. Player Onboarding
1. **Purchase Asteroid** (`sales/purchase_asteroid`): Player pays ETH, receives an Asteroid NFT via merkle proof verification.
2. **Purchase Adalian** (`sales/purchase_adalian`): Player buys a crewmate, which mints Crew + Crewmate NFTs, initializes food, attaches to station, creates escape module ship.
3. **Scan Surface** (`scanning/scan_surface_start` -> `_finish`): Reveal asteroid surface features.
4. **Scan Resources** (`scanning/scan_resources_start` -> `_finish`): Discover resource deposits.
5. **Station Crew** (`crew/station_crew`): Place crew at a building to begin operations.

### 3. Construction Flow
1. **Plan** (`construction/construction_plan`): Reserve a lot on an asteroid, create building entity with site inventory.
2. **Start** (`construction/construction_start`): Deliver construction materials to site inventory, begin build timer.
3. **Finish** (`construction/construction_finish`): After timer expires, building becomes operational.
4. **Deconstruct** (`construction/construction_deconstruct`): Tear down a building, recover some materials.
5. **Abandon** (`construction/construction_abandon`): Cancel a planned (not started) construction.

### 4. Resource Extraction & Production Flow
1. **Sample Deposit** (`deposits/sample_start` -> `sample_improve` -> `sample_finish`): Discover and improve knowledge of a resource deposit's yield.
2. **Extract Resource** (`production/extract_resource_start` -> `_finish`): Mine raw resources from a deposit. Duration based on `sqrt(yield)` modified by crew bonuses. Consumes deposit over time.
3. **Process Products** (`production/process_products_start` -> `_finish`): Transform raw materials into refined products at a Processor building. Input/output defined by process type configs.
4. **Assemble Ship** (`production/assemble_ship_start` -> `_finish`): Build a ship at a Dry Dock from manufactured components.

### 5. Ship & Travel Flow
1. **Undock Ship** (`ship/undock_ship`): Release ship from a dock.
2. **Transit Between** (`ship/transit_between_start` -> `_finish`): Travel between asteroids. Solves orbital mechanics (Keplerian elements, transfer orbits), calculates propellant cost via Tsiolkovsky equation, applies crew efficiency modifiers. Travel time is in game-time (accelerated).
3. **Dock Ship** (`ship/dock_ship`): Dock at destination asteroid's dock.

### 6. Marketplace / Trading Flow
1. **Configure Exchange** (`configure_exchange`): Set up a marketplace exchange at a building.
2. **Create Sell Order** (`orders/create_sell`): List products for sale with pricing and fees.
3. **Fill Sell Order** (`orders/fill_sell`): Another player buys the listed products. Handles fee distribution, inventory transfer.
4. **Create/Fill Buy Order** (`orders/create_buy`, `fill_buy`): Reverse direction -- place buy orders, sellers fill them.
5. **Cancel** (`orders/cancel_sell`): Cancel unfilled orders.

### 7. Delivery Flow
1. **Package** (`deliveries/package`): Package items from inventory.
2. **Send** (`deliveries/send`): Send packaged delivery to a destination.
3. **Receive** (`deliveries/receive`): Receive at destination.
4. **Accept/Cancel/Dump** (`deliveries/accept`, `cancel`, `dump`): Manage incoming deliveries.

### 8. Crew Management Flow
- **Recruit Adalian** (`crew/recruit_adalian`): Mint new crew members.
- **Arrange Crew** (`crew/arrange_crew`): Rearrange crewmate roster (up to 5 per crew).
- **Delegate Crew** (`crew/delegate_crew`): Transfer crew control to another player address.
- **Resupply Food** (`crew/resupply_food`): Feed crew from inventory or marketplace.
- **Eject/Exchange Crew** (`crew/eject_crew`, `exchange_crew`): Remove or swap crewmates.

### 9. Access Control & Permissions Flow
- **Policies**: Building owners assign access policies (public, prepaid, contract-based, merkle-proof).
- **Agreements**: Other players accept agreements to use controlled buildings.
- **Whitelists**: Owners can whitelist specific accounts.
- Permission checks happen in every system via `access::can()`, which walks the hierarchy: crew -> entity control -> policies -> agreements -> delegates.

### 10. Emergency & Random Events
- **Emergencies** (`emergencies/activate_emergency`): Ships can enter emergency mode to generate propellant.
- **Random Events** (`random_events/check_for`, `resolve`): Commit-reveal randomness triggers events during gameplay actions (e.g., "Stardust", "Fly Me to the Moon", "Groundbreaking").

---

## Key Concepts

| Concept | Description |
|---------|-------------|
| **Entity** | `(label, id)` pair identifying any game object (asteroid, crew, ship, building, etc.) |
| **Component** | Data attached to an entity (inventory, location, orbit, control, etc.) |
| **System** | Stateless logic invoked through the Dispatcher |
| **Dispatcher** | Central contract routing all system calls, storing config & registrations |
| **SWAY** | In-game ERC20 currency (Standard Weighted Adalian Yield) |
| **Crew** | Group of up to 5 crewmates; the "actor" that performs all actions |
| **Crewmate** | Individual character with class (Pilot/Engineer/Miner/Merchant/Scientist), traits, department |
| **Time Acceleration** | Game time runs faster than real time (e.g., 24x); affects transit, production, etc. |
| **Fixed-Point Math** | Uses the Cubit library (2^61 scale) for decimal arithmetic on-chain |
| **Commit-Reveal** | Randomness pattern: commit at time T, reveal after N blocks with hash verification |

---

## Development Workflow

```bash
# Setup
npm install                          # Install deps + init git submodules

# Build Cairo contracts
npm run build                        # Runs `scarb build`

# Test
npm run test-contracts               # Cairo unit tests
npm run test-integration             # Integration tests against seeded devnet

# Deploy / Manage
npm run manager update -- --name <contract> --network <net> --account <acct>
npm run manager updateAll -- --network <net> --account <acct>
npm run manager updateConfigs -- --network <net> --account <acct>
npm run manager seedAsteroids -- --network <net> --account <acct>
```

### Networks
- **devnet**: Local development (starknet-devnet)
- **testnet / sepolia**: Public testnets
- **mainnet**: Production deployment

### Key Dependencies
- **@influenceth/sdk**: Game data definitions (building types, process recipes, ship specs, constants)
- **@influenceth/ibis**: Starknet interaction library (account abstraction, contract calls)
- **starknet.js v6.7**: Low-level Starknet SDK
- **cubit** (Cairo, git submodule): Fixed-point math library
