mod dock_ship;
mod undock_ship;
mod transit_between_start;
mod transit_between_finish;

use dock_ship::DockShip;
use undock_ship::UndockShip;
use transit_between_start::TransitBetweenStart;
use transit_between_finish::TransitBetweenFinish;

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use traits::Into;

    use cubit::{f64, f128};

    use influence::{config, components};
    use influence::common::inventory;
    use influence::config::entities;
    use influence::components::{Building, BuildingTrait, Celestial, CelestialTrait, Control, ControlTrait, Crew,
        CrewTrait, Location, LocationTrait, Orbit, OrbitTrait, PublicPolicy, PublicPolicyTrait, Unique,
        dock_type::types as dock_types,
        inventory_type::types as inventory_types,
        modifier_type::types as modifier_types,
        product_type::types as product_types,
        dock::{Dock, DockTrait},
        inventory::{Inventory, InventoryTrait, MAX_AMOUNT},
        ship::{statuses as ship_statuses, Ship, ShipTrait},
        ship_type::{types as ship_types, ShipTypeTrait},
        ship_variant_type::types as ship_variant_types
    };
    use influence::types::{Entity, EntityTrait, InventoryItem, InventoryItemTrait, InventoryContentsTrait};
    use influence::test::{helpers, mocks};

    use super::{DockShip, UndockShip, TransitBetweenStart, TransitBetweenFinish};

    #[test]
    #[available_gas(35000000)]
    fn test_unpowered_docking() {
        helpers::init();
        mocks::constants();
        starknet::testing::set_block_timestamp(1000);

        // Add configs
        mocks::modifier_type(modifier_types::PROPELLANT_EXHAUST_VELOCITY);
        mocks::modifier_type(modifier_types::HOPPER_TRANSPORT_TIME);
        mocks::modifier_type(modifier_types::FREE_TRANSPORT_DISTANCE);
        mocks::dock_type(dock_types::BASIC);

        let asteroid = influence::test::mocks::asteroid();
        let mut celestial_data = components::get::<Celestial>(asteroid.path()).unwrap();
        celestial_data.scan_status = 4;
        components::set::<Celestial>(asteroid.path(), celestial_data);

        let crew = influence::test::mocks::delegated_crew(1, 'PLAYER');
        let ship = influence::test::mocks::controlled_light_transport(crew, 1);

        components::set::<Location>(crew.path(), LocationTrait::new(ship));
        components::set::<Location>(ship.path(), LocationTrait::new(asteroid));

        let spaceport = mocks::public_spaceport(crew, 1);
        components::set::<Location>(spaceport.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 25)));

        let mut dock_state = DockShip::contract_state_for_testing();
        DockShip::run(ref dock_state, spaceport, false, crew, mocks::context('PLAYER'));
        assert(components::get::<Location>(ship.path()).unwrap().location == spaceport, 'ship not docked');

        // Undock
        starknet::testing::set_block_timestamp(components::get::<Crew>(crew.path()).unwrap().ready_at);
        let mut undock_state = UndockShip::contract_state_for_testing();
        UndockShip::run(ref undock_state, ship, false, crew, mocks::context('PLAYER'));
        assert(components::get::<Location>(ship.path()).unwrap().location == asteroid, 'ship not undocked');
    }

    #[test]
    #[available_gas(40000000)]
    fn test_powered_docking() {
        helpers::init();
        config::set('TIME_ACCELERATION', 24);
        starknet::testing::set_block_timestamp(1000);

        let asteroid = influence::test::mocks::asteroid();
        let mut celestial_data = components::get::<Celestial>(asteroid.path()).unwrap();
        celestial_data.scan_status = 4;
        components::set::<Celestial>(asteroid.path(), celestial_data);

        // Add configs
        mocks::modifier_type(modifier_types::PROPELLANT_EXHAUST_VELOCITY);
        mocks::modifier_type(modifier_types::HOPPER_TRANSPORT_TIME);
        mocks::modifier_type(modifier_types::FREE_TRANSPORT_DISTANCE);
        mocks::product_type(product_types::HYDROGEN_PROPELLANT);
        mocks::dock_type(dock_types::BASIC);
        mocks::ship_variant_type(ship_variant_types::STANDARD);

        let crew = influence::test::mocks::delegated_crew(1, 'PLAYER');
        let ship = influence::test::mocks::controlled_light_transport(crew, 1);

        let mut prop_inv_path: Array<felt252> = Default::default();
        prop_inv_path.append(ship.into());
        prop_inv_path.append(ShipTypeTrait::by_type(ship_types::LIGHT_TRANSPORT).propellant_slot.into());

        let mut prop_inv = components::get::<Inventory>(prop_inv_path.span()).unwrap();
        let prop_to_add = array![InventoryItemTrait::new(product_types::HYDROGEN_PROPELLANT, 1000)].span();
        inventory::add(ref prop_inv, prop_to_add, f64::FixedTrait::ONE(), f64::FixedTrait::ONE());
        components::set::<Inventory>(prop_inv_path.span(), prop_inv);

        components::set::<Location>(crew.path(), LocationTrait::new(ship));
        components::set::<Location>(ship.path(), LocationTrait::new(asteroid));

        let spaceport = mocks::public_spaceport(crew, 1);
        components::set::<Location>(spaceport.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 25)));

        let mut dock_state = DockShip::contract_state_for_testing();
        DockShip::run(ref dock_state, spaceport, true, crew, mocks::context('PLAYER'));
        assert(components::get::<Location>(ship.path()).unwrap().location == spaceport, 'ship not docked');

        // Undock
        starknet::testing::set_block_timestamp(components::get::<Crew>(crew.path()).unwrap().ready_at);
        let mut undock_state = UndockShip::contract_state_for_testing();
        UndockShip::run(ref undock_state, ship, true, crew, mocks::context('PLAYER'));
        assert(components::get::<Location>(ship.path()).unwrap().location == asteroid, 'ship not undocked');
    }

    #[test]
    #[available_gas(35000000)]
    fn test_landing() {
        helpers::init();
        mocks::constants();
        starknet::testing::set_block_timestamp(1000);

        // Add configs
        mocks::modifier_type(modifier_types::PROPELLANT_EXHAUST_VELOCITY);
        mocks::modifier_type(modifier_types::HOPPER_TRANSPORT_TIME);
        mocks::modifier_type(modifier_types::FREE_TRANSPORT_DISTANCE);

        let asteroid = influence::test::mocks::asteroid();
        let mut celestial_data = components::get::<Celestial>(asteroid.path()).unwrap();
        celestial_data.scan_status = 4;
        components::set::<Celestial>(asteroid.path(), celestial_data);

        let crew = influence::test::mocks::delegated_crew(1, 'PLAYER');
        let ship = influence::test::mocks::controlled_light_transport(crew, 1);

        components::set::<Location>(crew.path(), LocationTrait::new(ship));
        components::set::<Location>(ship.path(), LocationTrait::new(asteroid));

        let lot = EntityTrait::from_position(asteroid.id, 25);

        let mut dock_state = DockShip::contract_state_for_testing();
        DockShip::run(ref dock_state, lot, false, crew, mocks::context('PLAYER'));
        assert(components::get::<Location>(ship.path()).unwrap().location == lot, 'ship not landed');
        assert(components::get::<Unique>(array!['LotUse', lot.into()].span()).is_some(), 'lot not in use');

        // Undock
        starknet::testing::set_block_timestamp(components::get::<Crew>(crew.path()).unwrap().ready_at);
        let mut undock_state = UndockShip::contract_state_for_testing();
        UndockShip::run(ref undock_state, ship, false, crew, mocks::context('PLAYER'));

        assert(components::get::<Location>(ship.path()).unwrap().location == asteroid, 'ship not undocked');
        assert(components::get::<Unique>(array!['LotUse', lot.into()].span()).is_none(), 'lot still in use');
    }

    #[test]
    #[available_gas(17000000)]
    #[should_panic(expected: ('E6037: emergency active', ))]
    fn test_escape_land_fail() {
        helpers::init();
        config::set('TIME_ACCELERATION', 24);
        starknet::testing::set_block_timestamp(1000);

        let asteroid = influence::test::mocks::asteroid();
        let crew = influence::test::mocks::delegated_crew(1, 'PLAYER');
        let mut ship_data = components::get::<Ship>(crew.path()).unwrap();
        ship_data.status = ship_statuses::AVAILABLE;
        ship_data.emergency_at = 1;
        components::set::<Ship>(crew.path(), ship_data);
        components::set::<Location>(crew.path(), LocationTrait::new(asteroid));

        let lot = EntityTrait::from_position(asteroid.id, 25);
        let mut dock_state = DockShip::contract_state_for_testing();
        DockShip::run(ref dock_state, lot, false, crew, mocks::context('PLAYER'));
    }

    // Benchmark 1: 488k steps for start
    // Benchmark 2: 483k steps for start

    #[test]
    #[available_gas(70000000)]
    fn test_transit() {
        helpers::init();
        config::set('TIME_ACCELERATION', 24);

        // Setup asteroids
        let origin = influence::test::mocks::adalia_prime();
        components::set::<Orbit>(origin.path(), Orbit {
            a: f128::FixedTrait::new(6049029247426345898732421120, false),
            ecc: f128::FixedTrait::new(5995191823955604275, false),
            inc: f128::FixedTrait::new(45073898850257648, false),
            raan: f128::FixedTrait::new(62919943230756085760, false),
            argp: f128::FixedTrait::new(97469086699478581248, false),
            m: f128::FixedTrait::new(17488672753899966464, false)
        });

        let destination = influence::test::mocks::asteroid();
        let mut celestial_data = components::get::<Celestial>(destination.path()).unwrap();
        celestial_data.scan_status = 2;
        components::set::<Celestial>(destination.path(), celestial_data);
        components::set::<Orbit>(destination.path(), Orbit {
            a: f128::FixedTrait::new(5276343029689403780074217825, false),
            ecc: f128::FixedTrait::new(2711671378835304087, false),
            inc: f128::FixedTrait::new(1101090957627722624, false),
            raan: f128::FixedTrait::new(45595468251239202816, false),
            argp: f128::FixedTrait::new(5936876391419651072, false),
            m: f128::FixedTrait::new(73740898519021518848, false)
        });

        // Add configs
        mocks::modifier_type(modifier_types::PROPELLANT_EXHAUST_VELOCITY);
        mocks::product_type(product_types::HYDROGEN_PROPELLANT);
        mocks::ship_variant_type(ship_variant_types::STANDARD);

        // Setup crew and ship
        let crew = influence::test::mocks::delegated_crew(1, 'PLAYER');
        let mut crew_data = components::get::<Crew>(crew.path()).unwrap();
        crew_data.last_fed = 1699610330;
        components::set::<Crew>(crew.path(), crew_data);
        let ship = influence::test::mocks::controlled_light_transport(crew, 1);

        let mut prop_inv_path: Array<felt252> = Default::default();
        prop_inv_path.append(ship.into());
        prop_inv_path.append(ShipTypeTrait::by_type(ship_types::LIGHT_TRANSPORT).propellant_slot.into());

        let mut prop_inv = components::get::<Inventory>(prop_inv_path.span()).unwrap();
        let prop_to_add = array![InventoryItemTrait::new(product_types::HYDROGEN_PROPELLANT, 100000)].span();
        inventory::add(ref prop_inv, prop_to_add, f64::FixedTrait::ONE(), f64::FixedTrait::ONE());
        components::set::<Inventory>(prop_inv_path.span(), prop_inv);

        components::set::<Location>(crew.path(), LocationTrait::new(ship));
        components::set::<Location>(ship.path(), LocationTrait::new(origin));

        // Start transit
        starknet::testing::set_block_timestamp(1699610330);
        let mut state = TransitBetweenStart::contract_state_for_testing();
        TransitBetweenStart::run(
            ref state,
            origin: origin,
            destination: destination,
            departure_time: 2188639872,
            arrival_time: 2210931072,
            transit_p: f128::FixedTrait::new(5214913760873839215396257792, false),
            transit_ecc: f128::FixedTrait::new(6857648137579236352, false),
            transit_inc: f128::FixedTrait::new(1871424578812082944, false),
            transit_raan: f128::FixedTrait::new(29034774961839652864, false),
            transit_argp: f128::FixedTrait::new(19889453798826442752, false),
            transit_nu_start: f128::FixedTrait::new(20316077186598404096, true),
            transit_nu_end: f128::FixedTrait::new(26458273329151033000, false),
            caller_crew: crew,
            context: mocks::context('PLAYER')
        );

        let mut ship_data = components::get::<Ship>(ship.path()).unwrap();
        assert(ship_data.transit_arrival > 0, 'wrong arrival');

        // Complete transit
        starknet::testing::set_block_timestamp(1701581330);
        let mut state = TransitBetweenFinish::contract_state_for_testing();
        TransitBetweenFinish::run(
            ref state,
            caller_crew: crew,
            context: mocks::context('PLAYER')
        );

        ship_data = components::get::<Ship>(ship.path()).unwrap();
        assert(ship_data.transit_arrival == 0, 'wrong arrival');
    }

    #[test]
    #[available_gas(110000000)]
    fn test_escape_module() {
        helpers::init();
        config::set('TIME_ACCELERATION', 24);

        // Setup asteroids
        let origin = influence::test::mocks::adalia_prime();
        components::set::<Orbit>(origin.path(), Orbit {
            a: f128::FixedTrait::new(6049029247426345898732421120, false),
            ecc: f128::FixedTrait::new(5995191823955604275, false),
            inc: f128::FixedTrait::new(45073898850257648, false),
            raan: f128::FixedTrait::new(62919943230756085760, false),
            argp: f128::FixedTrait::new(97469086699478581248, false),
            m: f128::FixedTrait::new(17488672753899966464, false)
        });

        let destination = influence::test::mocks::asteroid();
        let mut celestial_data = components::get::<Celestial>(destination.path()).unwrap();
        celestial_data.scan_status = 2;
        components::set::<Celestial>(destination.path(), celestial_data);
        components::set::<Orbit>(destination.path(), Orbit {
            a: f128::FixedTrait::new(5276343029689403780074217825, false),
            ecc: f128::FixedTrait::new(2711671378835304087, false),
            inc: f128::FixedTrait::new(1101090957627722624, false),
            raan: f128::FixedTrait::new(45595468251239202816, false),
            argp: f128::FixedTrait::new(5936876391419651072, false),
            m: f128::FixedTrait::new(73740898519021518848, false)
        });

        // Setup crew and ship
        starknet::testing::set_block_timestamp(1);
        let crew = influence::test::mocks::delegated_crew(1, 'PLAYER');
        let mut ship_data = components::get::<Ship>(crew.path()).unwrap();
        ship_data.status = ship_statuses::AVAILABLE;
        ship_data.emergency_at = 1;
        components::set::<Ship>(crew.path(), ship_data);

        // Add configs
        mocks::modifier_type(modifier_types::PROPELLANT_EXHAUST_VELOCITY);
        mocks::product_type(product_types::HYDROGEN_PROPELLANT);
        mocks::ship_variant_type(ship_variant_types::STANDARD);

        let mut prop_inv_path: Array<felt252> = Default::default();
        prop_inv_path.append(crew.into());
        prop_inv_path.append(ShipTypeTrait::by_type(ship_types::ESCAPE_MODULE).propellant_slot.into());

        let mut prop_inv = components::get::<Inventory>(prop_inv_path.span()).unwrap();
        let mut prop_to_add = Default::default();
        prop_to_add.append(InventoryItemTrait::new(product_types::HYDROGEN_PROPELLANT, 5000));
        prop_inv.enable();
        inventory::add(ref prop_inv, prop_to_add.span(), f64::FixedTrait::ONE(), f64::FixedTrait::ONE());

        components::set::<Inventory>(prop_inv_path.span(), prop_inv);
        components::set::<Location>(crew.path(), LocationTrait::new(origin));

        let mut state = TransitBetweenStart::contract_state_for_testing();
        TransitBetweenStart::run(
            ref state,
            origin: origin,
            destination: destination,
            departure_time: 2188639872,
            arrival_time: 2210931072,
            transit_p: f128::FixedTrait::new(5214913760873839215396257792, false),
            transit_ecc: f128::FixedTrait::new(6857648137579236352, false),
            transit_inc: f128::FixedTrait::new(1871424578812082944, false),
            transit_raan: f128::FixedTrait::new(29034774961839652864, false),
            transit_argp: f128::FixedTrait::new(19889453798826442752, false),
            transit_nu_start: f128::FixedTrait::new(20316077186598404096, true),
            transit_nu_end: f128::FixedTrait::new(26458273329151033000, false),
            caller_crew: crew,
            context: mocks::context('PLAYER')
        );

        ship_data = components::get::<Ship>(crew.path()).unwrap();
        assert(ship_data.transit_arrival > 0, 'wrong arrival');

        // Complete transit
        starknet::testing::set_block_timestamp(1701581330);
        let mut state = TransitBetweenFinish::contract_state_for_testing();
        TransitBetweenFinish::run(
            ref state,
            caller_crew: crew,
            context: mocks::context('PLAYER')
        );

        ship_data = components::get::<Ship>(crew.path()).unwrap();
        assert(ship_data.transit_arrival == 0, 'wrong arrival');
    }
}
