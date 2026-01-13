#[starknet::contract]
mod ClaimArrivalReward {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use starknet::contract_address::ContractAddress;
    use traits::{Into, TryInto};

    use cubit::f64::{Fixed, FixedTrait};

    use influence::{components, contracts};
    use influence::common::{crew::CrewDetailsTrait, inventory};
    use influence::components::{Control, ControlTrait, Crew, CrewTrait, Dock, DockTrait, Inventory, InventoryTrait,
        Location, LocationTrait, ProcessTypeTrait, Station, StationTrait, Unique, UniqueTrait,
        celestial::{statuses as scan_statuses, Celestial, CelestialTrait},
        building_type::{types as building_types, BuildingTypeTrait},
        inventory_type::{types as inventory_types, InventoryTypeTrait},
        product_type::{types as product_types, ProductTypeTrait},
        ship::{statuses as ship_statuses, variants, Ship, ShipTrait},
        ship_type::{types as ship_types, ShipTypeTrait},
        station_type::types as station_types
    };
    use influence::config::{entities, errors, permissions};
    use influence::contracts::asteroid::{IAsteroidDispatcher, IAsteroidDispatcherTrait};
    use influence::contracts::ship::{IShipDispatcher, IShipDispatcherTrait};
    use influence::types::{Context, Entity, EntityTrait, InventoryItem};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct ArrivalRewardClaimed {
        asteroid: Entity,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        ArrivalRewardClaimed: ArrivalRewardClaimed
    }

    #[external(v0)]
    fn run(ref self: ContractState, asteroid: Entity, caller_crew: Entity, context: Context) {
        // Check that crew is delegated, and ready
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_all_ready(context.caller, context.now);
        let mut crew_data = crew_details.component;

        // Only the controller of the asteroid can claim
        caller_crew.assert_controls(asteroid);

        // Check the asteroid is in the correct purchase order range
        let celestial_data = components::get::<Celestial>(asteroid.path()).expect(errors::CELESTIAL_NOT_FOUND);
        assert(celestial_data.purchase_order > 0 && celestial_data.purchase_order <= 1859, errors::REWARD_NOT_FOUND);
        assert(celestial_data.scan_status >= scan_statuses::SURFACE_SCANNED, 'asteroid must be scanned');

        // Check that the asteroid hasn't already been used to claim
        let mut path: Array<felt252> = Default::default();
        path.append(asteroid.into());
        path.append('ArrivalRewardClaimed');
        assert(components::get::<Unique>(path.span()).is_none(), errors::REWARD_ALREADY_CLAIMED);
        components::set::<Unique>(path.span(), Unique { unique: 1 }); // set it to used

        // Grant ships in orbit for small, medium, and large asteroids
        let mut ship = EntityTrait::new(entities::SHIP, 0);

        if celestial_data.radius <= FixedTrait::new_unscaled(5, false) {
            // One limited edition light transport
            ship = grant_ship(ship_types::LIGHT_TRANSPORT, variants::COBALT_PIONEER, caller_crew, context);
        } else if celestial_data.radius <= FixedTrait::new_unscaled(20, false) {
            // One limited edition light transport
            ship = grant_ship(ship_types::LIGHT_TRANSPORT, variants::TITANIUM_PIONEER, caller_crew, context);

            // One standard light transport
            grant_ship(ship_types::LIGHT_TRANSPORT, variants::STANDARD, caller_crew, context);

            // One standard shuttle
            grant_ship(ship_types::SHUTTLE, variants::STANDARD, caller_crew, context);
        } else if celestial_data.radius <= FixedTrait::new_unscaled(50, false) {
            // One limited edition light transport
            ship = grant_ship(ship_types::LIGHT_TRANSPORT, variants::AUREATE_PIONEER, caller_crew, context);

            // Two standard light transports
            grant_ship(ship_types::LIGHT_TRANSPORT, variants::STANDARD, caller_crew, context);
            grant_ship(ship_types::LIGHT_TRANSPORT, variants::STANDARD, caller_crew, context);

            // Two standard shuttles
            grant_ship(ship_types::SHUTTLE, variants::STANDARD, caller_crew, context);
            grant_ship(ship_types::SHUTTLE, variants::STANDARD, caller_crew, context);

            // One standard heavy transport
            grant_ship(ship_types::HEAVY_TRANSPORT, variants::STANDARD, caller_crew, context);
        }

        self.emit(ArrivalRewardClaimed {
            asteroid: asteroid,
            caller_crew: caller_crew,
            caller: context.caller
        });
    }

    fn grant_ship(ship_type: u64, variant: u64, caller_crew: Entity, context: Context) -> Entity {
        let id = IShipDispatcher { contract_address: contracts::get('Ship') }.mint_with_auto_id(context.caller);

        // Create ship component
        let ship = EntityTrait::new(entities::SHIP, id.try_into().unwrap());
        components::set::<Ship>(ship.path(), Ship {
            ship_type: ship_type,
            status: ship_statuses::AVAILABLE,
            ready_at: context.now,
            emergency_at: 0,
            variant: variant,
            transit_origin: EntityTrait::new(0, 0),
            transit_departure: 0,
            transit_destination: EntityTrait::new(0, 0),
            transit_arrival: 0
        });

        // Update location of the ship and crew rest time
        let adalia_prime = EntityTrait::new(entities::ASTEROID, 1);
        components::set::<Location>(ship.path(), LocationTrait::new(adalia_prime));

        // Add storage and station to ship
        let config = ShipTypeTrait::by_type(ship_type);

        let mut prop_path: Array<felt252> = Default::default();
        prop_path.append(ship.into());
        prop_path.append(config.propellant_slot.into());

        let mut cargo_path: Array<felt252> = Default::default();
        cargo_path.append(ship.into());
        cargo_path.append(config.cargo_slot.into());

        if config.propellant_inventory_type != 0 {
            components::set::<Inventory>(prop_path.span(), InventoryTrait::new(config.propellant_inventory_type));
        }

        if config.cargo_inventory_type != 0 {
            components::set::<Inventory>(cargo_path.span(), InventoryTrait::new(config.cargo_inventory_type));
        }

        if config.station_type != 0 {
            components::set::<Station>(ship.path(), StationTrait::new(config.station_type));
        }

        let product_config = ProductTypeTrait::by_type(product_types::HYDROGEN_PROPELLANT);
        let prop_unit_mass = product_config.mass;

        // Grant a full tank of propellant to the variant light transport
        if ship_type == ship_types::LIGHT_TRANSPORT && variant > 1 {
            let prop_mass = InventoryTypeTrait::by_type(inventory_types::PROPELLANT_MEDIUM).mass;
            let mut prop_inv: Array<InventoryItem> = Default::default();
            prop_inv.append(InventoryItem {
                product: product_types::HYDROGEN_PROPELLANT,
                amount: prop_mass / prop_unit_mass
            });

            let mut prop_data = components::get::<Inventory>(prop_path.span()).expect(errors::INVENTORY_NOT_FOUND);
            inventory::add_unchecked(ref prop_data, prop_inv.span());
            components::set::<Inventory>(prop_path.span(), prop_data);

            // Grant extractor, warehouse materials and five core samplers to variant light transport
            let mut cargo_data = components::get::<Inventory>(cargo_path.span()).expect(errors::INVENTORY_NOT_FOUND);
            let mut cargo_inv: Array<InventoryItem> = Default::default();
            cargo_inv.append(InventoryItem {
                product: product_types::CORE_DRILL,
                amount: 5
            });

            inventory::add_unchecked(ref cargo_data, cargo_inv.span());

            // Get configs for warehouse
            let warehouse_config = BuildingTypeTrait::by_type(building_types::WAREHOUSE);
            let warehouse_proc_config = ProcessTypeTrait::by_type(warehouse_config.process_type);

            // Get configs for extractor
            let extractor_config = BuildingTypeTrait::by_type(building_types::EXTRACTOR);
            let extractor_proc_config = ProcessTypeTrait::by_type(extractor_config.process_type);

            inventory::add_unchecked(ref cargo_data, warehouse_proc_config.inputs);
            inventory::add_unchecked(ref cargo_data, extractor_proc_config.inputs);
            components::set::<Inventory>(cargo_path.span(), cargo_data);
        } else if ship_type == ship_types::LIGHT_TRANSPORT {
            // Grant 2% propellant to light transport
            let prop_mass = InventoryTypeTrait::by_type(inventory_types::PROPELLANT_MEDIUM).mass;
            let mut prop_inv: Array<InventoryItem> = Default::default();
            prop_inv.append(InventoryItem {
                product: product_types::HYDROGEN_PROPELLANT,
                amount: (prop_mass / prop_unit_mass) / 50
            });

            let mut prop_data = components::get::<Inventory>(prop_path.span()).expect(errors::INVENTORY_NOT_FOUND);
            inventory::add_unchecked(ref prop_data, prop_inv.span());
            components::set::<Inventory>(prop_path.span(), prop_data);
        } else if ship_type == ship_types::HEAVY_TRANSPORT {
            // Grant 2% propellant to heavy transport
            let prop_mass = InventoryTypeTrait::by_type(inventory_types::PROPELLANT_LARGE).mass;
            let mut prop_inv: Array<InventoryItem> = Default::default();
            prop_inv.append(InventoryItem {
                product: product_types::HYDROGEN_PROPELLANT,
                amount: (prop_mass / prop_unit_mass) / 50
            });

            let mut prop_data = components::get::<Inventory>(prop_path.span()).expect(errors::INVENTORY_NOT_FOUND);
            inventory::add_unchecked(ref prop_data, prop_inv.span());
            components::set::<Inventory>(prop_path.span(), prop_data);
        } else if ship_type == ship_types::SHUTTLE {
            // Grant 2% propellant to shuttle
            let prop_mass = InventoryTypeTrait::by_type(inventory_types::PROPELLANT_SMALL).mass;
            let mut prop_inv: Array<InventoryItem> = Default::default();
            prop_inv.append(InventoryItem {
                product: product_types::HYDROGEN_PROPELLANT,
                amount: (prop_mass / prop_unit_mass) / 50
            });

            let mut prop_data = components::get::<Inventory>(prop_path.span()).expect(errors::INVENTORY_NOT_FOUND);
            inventory::add_unchecked(ref prop_data, prop_inv.span());
            components::set::<Inventory>(prop_path.span(), prop_data);
        }

        // Grant control of ship to caller crew
        components::set::<Control>(ship.path(), ControlTrait::new(caller_crew));

        return ship;
    }
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use traits::Into;

    use influence::{components, config};
    use influence::components::{Celestial, Control, ControlTrait, Location, LocationTrait,
        building_type::types as building_types,
        inventory_type::types as inventory_types,
        modifier_type::types as modifier_types,
        process_type::types as process_types,
        product_type::types as product_types,
        inventory::MAX_AMOUNT,
        ship::{statuses as ship_statuses, variants, Ship, ShipTrait},
        ship_type::types as ship_types
    };
    use influence::config::entities;
    use influence::contracts::asteroid::{IAsteroidDispatcher, IAsteroidDispatcherTrait};
    use influence::contracts::ship::{IShipDispatcher, IShipDispatcherTrait};
    use influence::test::{helpers, mocks};
    use influence::types::{Entity, EntityTrait, InventoryItemTrait};

    use super::ClaimArrivalReward;

    #[test]
    #[available_gas(70000000)]
    fn test_claim_arrival() {
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        config::set('TIME_ACCELERATION', 24);
        helpers::init();
        let asteroid_address = helpers::deploy_asteroid();
        let ship_address = helpers::deploy_ship();

        // Add configs
        mocks::inventory_type(inventory_types::PROPELLANT_SMALL);
        mocks::inventory_type(inventory_types::PROPELLANT_MEDIUM);
        mocks::inventory_type(inventory_types::PROPELLANT_LARGE);
        mocks::inventory_type(inventory_types::CARGO_SMALL);
        mocks::inventory_type(inventory_types::CARGO_MEDIUM);
        mocks::inventory_type(inventory_types::CARGO_LARGE);
        mocks::product_type(product_types::HYDROGEN_PROPELLANT);
        mocks::product_type(product_types::CORE_DRILL);
        mocks::product_type(product_types::CEMENT);
        mocks::product_type(product_types::STEEL_BEAM);
        mocks::product_type(product_types::STEEL_SHEET);
        mocks::product_type(product_types::POLYACRYLONITRILE_FABRIC);
        mocks::product_type(product_types::FLUIDS_AUTOMATION_MODULE);
        mocks::product_type(product_types::POWER_MODULE);
        mocks::building_type(building_types::WAREHOUSE);
        mocks::building_type(building_types::EXTRACTOR);
        mocks::process_type(process_types::WAREHOUSE_CONSTRUCTION);
        mocks::process_type(process_types::EXTRACTOR_CONSTRUCTION);
        mocks::ship_type(ship_types::LIGHT_TRANSPORT);
        mocks::ship_type(ship_types::SHUTTLE);
        mocks::ship_type(ship_types::HEAVY_TRANSPORT);

        starknet::testing::set_contract_address(starknet::contract_address_const::<'ADMIN'>());
        IAsteroidDispatcher { contract_address: asteroid_address }
            .add_grant(starknet::contract_address_const::<'DISPATCHER'>(), 2);

        IShipDispatcher { contract_address: ship_address }
            .add_grant(starknet::contract_address_const::<'DISPATCHER'>(), 2);

        // Mint asteroid to caller
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        IAsteroidDispatcher { contract_address: asteroid_address }
            .mint_with_id(starknet::contract_address_const::<'PLAYER'>(), 104);

        let adalia_prime = mocks::adalia_prime();
        let asteroid = mocks::asteroid();
        let crew = mocks::delegated_crew(1, 'PLAYER');
        components::set::<Control>(asteroid.path(), ControlTrait::new(crew));

        let hab = mocks::public_habitat(crew, 1);
        components::set::<Location>(hab.path(), LocationTrait::new(EntityTrait::from_position(1, 1)));
        components::set::<Location>(crew.path(), LocationTrait::new(hab));

        let mut celestial_data = components::get::<Celestial>(asteroid.path()).unwrap();
        celestial_data.purchase_order = 100;
        celestial_data.scan_status = 2;
        components::set::<Celestial>(asteroid.path(), celestial_data);

        // Run the system
        let mut state = ClaimArrivalReward::contract_state_for_testing();
        ClaimArrivalReward::run(ref state, asteroid, crew, mocks::context('PLAYER'));

        // Check the ships were granted
        let ship1 = EntityTrait::new(entities::SHIP, 1);
        let ship1_data = components::get::<Ship>(ship1.path()).unwrap();
        assert(ship1_data.ship_type == ship_types::LIGHT_TRANSPORT, 'wrong ship 1 type');
        assert(components::get::<Location>(ship1.path()).unwrap().location == adalia_prime, 'wrong ship 1 location');

        let ship6 = EntityTrait::new(entities::SHIP, 6);
        let ship6_data = components::get::<Ship>(ship6.path()).unwrap();
        assert(ship6_data.ship_type == ship_types::HEAVY_TRANSPORT, 'wrong ship 6 type');
        assert(components::get::<Location>(ship6.path()).unwrap().location == adalia_prime, 'wrong ship 6 location');
    }
}
