// Handles:
// - ejecting your own crew from a habitat to orbit
// - ejecting your own crew from a ship in orbit
// - ejecting another crew (without permissions) from a station to orbit

#[starknet::contract]
mod EjectCrew {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use starknet::ContractAddress;
    use traits::Into;

    use influence::components;
    use influence::common::{crew::CrewDetailsTrait, position};
    use influence::config::{entities, errors, permissions};
    use influence::components::{Celestial, Crew, CrewTrait, Inventory, InventoryTrait, Location, LocationTrait,
        Station, StationTrait,
        modifier_type::types as modifier_types,
        ship::{statuses as ship_statuses, Ship, ShipTrait},
        ship_type::types as ship_types, ShipTypeTrait};
    use influence::types::{Context, Entity, EntityTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct CrewEjected {
        station: Entity,
        ejected_crew: Entity,
        finish_time: u64,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        CrewEjected: CrewEjected
    }

    #[external(v0)]
    fn run(ref self: ContractState, ejected_crew: Entity, caller_crew: Entity, context: Context) {
        // Check that crew is delegated and ready
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_launched(context.now);
        crew_details.assert_delegated_to(context.caller);
        crew_details.assert_manned();
        crew_details.assert_not_in_emergency();
        let mut crew_data = crew_details.component;

        let mut ejected_crew_details = CrewDetailsTrait::new(ejected_crew);
        let mut ejected_crew_data = ejected_crew_details.component;

        // Can't eject from an escape module
        let location = ejected_crew_details.location();
        let (ship, ship_data) = ejected_crew_details.ship();

        // Must be in a ship, or in a habitat building
        assert(location == ship || location.label == entities::BUILDING, errors::INCORRECT_SHIP_TYPE);

        // If ejected by the controller, make sure the caller is ready and the ejected crew doesn't have permissions
        if ejected_crew != caller_crew {
            crew_details.assert_ready(context.now);
            assert(!ejected_crew.can(location, permissions::STATION_CREW), errors::ACCESS_DENIED);
        }

        // Adjust station population
        let (station, mut station_data) = ejected_crew_details.station();
        station_data.population -= ejected_crew_data.roster.len().into();
        components::set::<Station>(station.path(), station_data);

        let mut finish_time = 0;
        let mut destination = EntityTrait::new(entities::SPACE, 1);

        let mut escape_module_data = components::get::<Ship>(ejected_crew.path()).expect(errors::SHIP_NOT_FOUND);
        escape_module_data.status = ship_statuses::AVAILABLE;

        if ship_data.transit_arrival > 0 {
            // Update crew / escape module location to space
            components::set::<Location>(ejected_crew.path(), LocationTrait::new(destination));
            finish_time = ship_data.ready_at;

            // If ship is in transit, update the ejected crew's escape module with the same trajectory
            escape_module_data.ready_at = ship_data.ready_at;
            escape_module_data.emergency_at = ship_data.ready_at;
            escape_module_data.transit_origin = ship_data.transit_origin;
            escape_module_data.transit_departure = ship_data.transit_departure;
            escape_module_data.transit_destination = ship_data.transit_destination;
            escape_module_data.transit_arrival = ship_data.transit_arrival;
        } else {
            // If ship is not in transit, calculate the crew transfer time
            let asteroid = EntityTrait::new(entities::ASTEROID, ejected_crew_details.asteroid_id());
            let celestial_data = components::get::<Celestial>(asteroid.path()).expect(errors::CELESTIAL_NOT_FOUND);
            let hopper_eff = ejected_crew_details.bonus(modifier_types::HOPPER_TRANSPORT_TIME, context.now);
            let dist_eff = crew_details.bonus(modifier_types::FREE_TRANSPORT_DISTANCE, context.now);
            let crew_to_orbit = position::hopper_travel_time(
                ejected_crew_details.lot_id(), 0, celestial_data.radius, hopper_eff, dist_eff
            );

            // Update crew location and escape module
            components::set::<Location>(ejected_crew.path(), LocationTrait::new(asteroid));
            finish_time = ejected_crew_data.busy_until(context.now) + crew_to_orbit;
            escape_module_data.ready_at = finish_time;
            escape_module_data.emergency_at = finish_time;
            destination = asteroid;
        }

        // Update escape module and make propellant available
        let ship_config = ShipTypeTrait::by_type(ship_types::ESCAPE_MODULE);
        components::set::<Ship>(ejected_crew.path(), escape_module_data);
        let mut inventory_path: Array<felt252> = Default::default();
        inventory_path.append(ejected_crew.into());
        inventory_path.append(ship_config.propellant_slot.into());
        let mut inv_data = components::get::<Inventory>(inventory_path.span()).expect(errors::INVENTORY_NOT_FOUND);
        inv_data.enable();
        components::set::<Inventory>(inventory_path.span(), inv_data);

        // Update the crew's ready at timestamp
        ejected_crew_data.ready_at = finish_time;
        components::set::<Crew>(ejected_crew.path(), ejected_crew_data);

        self.emit(CrewEjected {
            station: station,
            ejected_crew: ejected_crew,
            finish_time: finish_time,
            caller_crew: caller_crew,
            caller: context.caller
        });
    }
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use traits::Into;

    use influence::{config, components};
    use influence::config::{entities, permissions};
    use influence::components::{Control, ControlTrait, Crew, CrewTrait, Location, LocationTrait, PrepaidAgreement,
        Station,
        crewmate::{classes, crewmate_traits, departments},
        modifier_type::types as modifier_types,
        product_type::types as products,
        ship::{statuses as ship_statuses, Ship, ShipTrait},
        ship_type::types as ship_types};
    use influence::systems::agreements::helpers::agreement_path;
    use influence::types::{Entity, EntityTrait};
    use influence::test::{helpers, mocks};

    use super::EjectCrew;

    fn add_modifiers() {
        mocks::modifier_type(modifier_types::HOPPER_TRANSPORT_TIME);
        mocks::modifier_type(modifier_types::FREE_TRANSPORT_DISTANCE);
    }

    #[test]
    #[available_gas(25000000)]
    fn test_eject_self() {
        helpers::init();
        mocks::constants();
        starknet::testing::set_block_timestamp(1000);
        add_modifiers();

        let asteroid = influence::test::mocks::asteroid();
        let crew = influence::test::mocks::delegated_crew(1, 'PLAYER');
        let ship = influence::test::mocks::controlled_light_transport(crew, 1);
        let mut station_data = components::get::<Station>(ship.path()).unwrap();
        station_data.population += 1; // 1 crew of 1
        components::set::<Station>(ship.path(), station_data);

        components::set::<Location>(crew.path(), LocationTrait::new(ship));
        components::set::<Location>(ship.path(), LocationTrait::new(asteroid));

        let mut state = EjectCrew::contract_state_for_testing();
        EjectCrew::run(ref state, crew, crew, mocks::context('PLAYER'));

        assert(components::get::<Location>(crew.path()).unwrap().location == asteroid, 'wrong location');
        assert(components::get::<Ship>(crew.path()).unwrap().status == ship_statuses::AVAILABLE, 'wrong ship status');
    }

    #[test]
    #[available_gas(25000000)]
    fn test_eject_other() {
        helpers::init();
        mocks::constants();
        starknet::testing::set_block_timestamp(1000);
        add_modifiers();

        let asteroid = influence::test::mocks::asteroid();
        let controller_crew = influence::test::mocks::delegated_crew(1, 'CONTROLLER');
        let ship = influence::test::mocks::controlled_light_transport(controller_crew, 1);

        components::set::<Location>(controller_crew.path(), LocationTrait::new(ship));
        components::set::<Location>(ship.path(), LocationTrait::new(asteroid));

        // Add another crew to ship
        let player_crew = influence::test::mocks::delegated_crew(2, 'PLAYER');
        components::set::<Location>(player_crew.path(), LocationTrait::new(ship));
        let mut station_data = components::get::<Station>(ship.path()).unwrap();
        station_data.population += 2; // 2 crews of 1
        components::set::<Station>(ship.path(), station_data);

        let mut state = EjectCrew::contract_state_for_testing();
        EjectCrew::run(ref state, player_crew, controller_crew, mocks::context('CONTROLLER'));

        assert(components::get::<Location>(player_crew.path()).unwrap().location == asteroid, 'wrong location');
        assert(components::get::<Ship>(player_crew.path()).unwrap().status == ship_statuses::AVAILABLE, 'wrong ship status');
    }

    #[test]
    #[available_gas(18000000)]
    fn test_eject_habitat() {
        helpers::init();
        mocks::constants();
        starknet::testing::set_block_timestamp(1000);
        add_modifiers();

        let asteroid = influence::test::mocks::asteroid();
        let crew = influence::test::mocks::delegated_crew(1, 'PLAYER');
        let habitat = mocks::public_habitat(crew, 1);
        let mut station_data = components::get::<Station>(habitat.path()).unwrap();
        station_data.population += 1; // 1 crew of 1
        components::set::<Station>(habitat.path(), station_data);

        components::set::<Location>(crew.path(), LocationTrait::new(habitat));
        components::set::<Location>(habitat.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 25)));

        let mut state = EjectCrew::contract_state_for_testing();
        EjectCrew::run(ref state, crew, crew, mocks::context('PLAYER'));

        assert(components::get::<Location>(crew.path()).unwrap().location == asteroid, 'wrong location');
        assert(components::get::<Ship>(crew.path()).unwrap().status == ship_statuses::AVAILABLE, 'wrong ship status');
    }

    #[test]
    #[available_gas(22000000)]
    fn test_eject_habitat_other() {
        helpers::init();
        mocks::constants();
        starknet::testing::set_block_timestamp(1000);
        add_modifiers();

        let asteroid = influence::test::mocks::asteroid();
        let controller_crew = influence::test::mocks::delegated_crew(1, 'CONTROLLER');
        let player_crew = influence::test::mocks::delegated_crew(2, 'PLAYER');

        let habitat = mocks::public_habitat(controller_crew, 1);
        let mut station_data = components::get::<Station>(habitat.path()).unwrap();
        station_data.population += 1; // 2 crew of 1
        components::set::<Station>(habitat.path(), station_data);

        components::set::<Location>(controller_crew.path(), LocationTrait::new(habitat));
        components::set::<Location>(player_crew.path(), LocationTrait::new(habitat));
        components::set::<Location>(habitat.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 25)));

        let mut state = EjectCrew::contract_state_for_testing();
        EjectCrew::run(ref state, player_crew, controller_crew, mocks::context('CONTROLLER'));

        assert(components::get::<Location>(player_crew.path()).unwrap().location == asteroid, 'wrong location');
        assert(components::get::<Ship>(player_crew.path()).unwrap().status == ship_statuses::AVAILABLE, 'wrong ship status');
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('E2002: access denied', ))]
    fn test_fail_with_permission() {
        helpers::init();
        config::set('TIME_ACCELERATION', 24);
        starknet::testing::set_block_timestamp(1000);

        let asteroid = influence::test::mocks::asteroid();
        let controller_crew = influence::test::mocks::delegated_crew(1, 'CONTROLLER');
        let player_crew = influence::test::mocks::delegated_crew(2, 'PLAYER');

        let habitat = mocks::public_habitat(controller_crew, 1);
        let mut station_data = components::get::<Station>(habitat.path()).unwrap();
        station_data.population += 1; // 2 crew of 1
        components::set::<Station>(habitat.path(), station_data);

        // Assign permission to player crew
        let path = agreement_path(habitat, permissions::STATION_CREW, player_crew.into());
        components::set::<PrepaidAgreement>(path, PrepaidAgreement {
            rate: 1,
            initial_term: 10000,
            notice_period: 10000,
            start_time: 1,
            end_time: 10000,
            notice_time: 0
        });

        components::set::<Location>(controller_crew.path(), LocationTrait::new(habitat));
        components::set::<Location>(player_crew.path(), LocationTrait::new(habitat));
        components::set::<Location>(habitat.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 25)));

        let mut state = EjectCrew::contract_state_for_testing();
        EjectCrew::run(ref state, player_crew, controller_crew, mocks::context('CONTROLLER'));
    }
}
