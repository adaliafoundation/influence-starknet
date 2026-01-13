#[starknet::contract]
mod StationCrew {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use starknet::contract_address::ContractAddress;
    use traits::Into;

    use influence::components;
    use influence::common::{position, crew::CrewDetailsTrait};
    use influence::components::{Building, BuildingTrait, Celestial, CelestialTrait, Crew, CrewTrait, Inventory,
        InventoryTrait, Location, LocationTrait, Ship, ShipTrait, Station, StationTrait,
        modifier_type::types as modifier_types,
        ship_type::{types as ship_types, ShipTypeTrait},
        station_type::{types as station_types, StationTypeTrait}
    };
    use influence::config::{entities, errors, permissions};
    use influence::types::{Context, Entity, EntityTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct CrewStationed {
        station: Entity,
        finish_time: u64,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[derive(Copy, Drop, starknet::Event)]
    struct CrewStationedV1 {
        origin_station: Entity,
        destination_station: Entity,
        finish_time: u64,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        CrewStationed: CrewStationed,
        CrewStationedV1: CrewStationedV1
    }

    #[external(v0)]
    fn run(ref self: ContractState, destination: Entity, caller_crew: Entity, context: Context) {
        // Check that crew is delegated, and ready (must be available even when ship / building aren't ready)
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_delegated_to(context.caller);
        crew_details.assert_manned();
        crew_details.assert_ready(context.now);
        let mut crew_data = crew_details.component;

        // Check that the crew is in the right location
        let (dest_ast, dest_lot) = destination.to_position();
        assert(crew_details.asteroid_id() == dest_ast, errors::INCORRECT_ASTEROID);


        // Calculate the crew transfer time
        let asteroid = EntityTrait::new(entities::ASTEROID, dest_ast);
        let celestial_data = components::get::<Celestial>(asteroid.path()).expect(errors::CELESTIAL_NOT_FOUND);
        let hopper_eff = crew_details.bonus(modifier_types::HOPPER_TRANSPORT_TIME, context.now);
        let dist_eff = crew_details.bonus(modifier_types::FREE_TRANSPORT_DISTANCE, context.now);
        let crew_to_lot = position::hopper_travel_time(
            crew_details.lot_id(), dest_lot, celestial_data.radius, hopper_eff, dist_eff
        );

        // Check permissions to station crew
        caller_crew.assert_can(destination, permissions::STATION_CREW);

        // Check station is ready to receive crew
        if destination.label == entities::BUILDING {
            components::get::<Building>(destination.path()).expect(errors::BUILDING_NOT_FOUND).assert_operational();
        } else if destination.label == entities::SHIP {
            let mut dest_ship_data = components::get::<Ship>(destination.path()).expect(errors::SHIP_NOT_FOUND);
            dest_ship_data.assert_stationary();
            dest_ship_data.extend_ready(context.now + crew_to_lot);
            components::set::<Ship>(destination.path(), dest_ship_data);

            let location = components::get::<Location>(destination.path()).expect(errors::LOCATION_NOT_FOUND);
            match components::get::<Building>(location.location.path()) {
                Option::Some(building_data) => building_data.assert_operational(),
                Option::None(_) => ()
            };
        }

        // Update occupancy of stations
        let mut dest_station_data = components::get::<Station>(destination.path()).expect(errors::STATION_NOT_FOUND);
        let new_crewmates = crew_data.roster.len().into();
        let station_config = StationTypeTrait::by_type(dest_station_data.station_type);
        dest_station_data.population += new_crewmates;
        assert(dest_station_data.population <= station_config.cap, 'station is full');
        components::set::<Station>(destination.path(), dest_station_data);

        let (ship, mut ship_data) = crew_details.ship();
        let mut origin_station = caller_crew; // Default to escape module as origin

        if ship == caller_crew && ship_data.emergency_at != 0 {
            // For escape modules, update to disabled (cancels emergency as well)
            ship_data.disable();
            components::set::<Ship>(ship.path(), ship_data);

            // Disable the inventory
            let ship_config = ShipTypeTrait::by_type(ship_types::ESCAPE_MODULE);
            let mut inventory_path: Array<felt252> = Default::default();
            inventory_path.append(ship.into());
            inventory_path.append(ship_config.propellant_slot.into());
            let mut inv_data = components::get::<Inventory>(inventory_path.span()).expect(errors::INVENTORY_NOT_FOUND);
            inv_data.disable();
            components::set::<Inventory>(inventory_path.span(), inv_data);
        } else {
            // In a ship or station, update the station info
            let (_origin_station, mut origin_station_data) = crew_details.station();
            origin_station = _origin_station;
            origin_station_data.population -= crew_data.roster.len().into();
            components::set::<Station>(origin_station.path(), origin_station_data);
        }

        // Update crew location
        components::set::<Location>(caller_crew.path(), LocationTrait::new(destination));

        // Update crew data
        crew_data.add_busy(context.now, crew_to_lot);
        components::set::<Crew>(caller_crew.path(), crew_data);

        self.emit(CrewStationedV1 {
            origin_station: origin_station,
            destination_station: destination,
            finish_time: crew_data.ready_at,
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

    use influence::{components, config};
    use influence::components::{Crew, CrewTrait, Location, LocationTrait, Station, StationTrait,
        modifier_type::types as modifier_types,
        ship::{statuses as ship_statuses, Ship, ShipTrait},
        ship_type::types as ship_types};
    use influence::test::{helpers, mocks};
    use influence::types::{Entity, EntityTrait};

    use super::StationCrew;

    #[test]
    #[available_gas(20000000)]
    fn test_stationing() {
        helpers::init();
        mocks::constants();
        starknet::testing::set_block_timestamp(100);

        // Add configs
        mocks::modifier_type(modifier_types::HOPPER_TRANSPORT_TIME);
        mocks::modifier_type(modifier_types::FREE_TRANSPORT_DISTANCE);

        let asteroid = influence::test::mocks::asteroid();
        let crew = influence::test::mocks::delegated_crew(1, 'PLAYER');
        let station = influence::test::mocks::public_habitat(crew, 37);
        components::set::<Location>(station.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 37)));
        components::set::<Location>(crew.path(), LocationTrait::new(station));
        components::set::<Ship>(crew.path(), Ship {
            ship_type: ship_types::ESCAPE_MODULE,
            status: ship_statuses::DISABLED,
            ready_at: 0,
            emergency_at: 0,
            variant: 1,
            transit_origin: EntityTrait::new(0, 0),
            transit_departure: 0,
            transit_destination: EntityTrait::new(0, 0),
            transit_arrival: 0
        });

        // Update station population
        let mut station_data = components::get::<Station>(station.path()).unwrap();
        let crew_data = components::get::<Crew>(crew.path()).unwrap();
        station_data.population = crew_data.roster.len().into();
        components::set::<Station>(station.path(), station_data);

        // Create a second station
        let second_station = influence::test::mocks::public_habitat(crew, 73);
        components::set::<Location>(
            second_station.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 37))
        );

        // Try stationing the crew
        let mut state = StationCrew::contract_state_for_testing();
        StationCrew::run(ref state, second_station, crew, mocks::context('PLAYER'));

        // Check the data
        let crew_location = components::get::<Location>(crew.path()).unwrap();
        assert(crew_location.location == second_station, 'wrong station');
        let origin_data = components::get::<Station>(station.path()).unwrap();
        assert(origin_data.population == 0, 'wrong origin population');
        let dest_data = components::get::<Station>(second_station.path()).unwrap();
        assert(dest_data.population == 1, 'wrong destination population');
    }

    // TEST: tests based on https://docs.google.com/spreadsheets/d/1kBRYB0YNv3uNnT7KsGN-5_wL8p55-daWbXsZt7HUShE
}
