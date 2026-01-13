#[starknet::contract]
mod TransitBetweenFinish {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use starknet::contract_address::ContractAddress;
    use traits::{Into, TryInto};

    use influence::{components, config};
    use influence::common::crew::CrewDetailsTrait;
    use influence::config::{entities, errors};
    use influence::components::{Location, LocationTrait,
        ship::{statuses as ship_statuses, Ship, ShipTrait},
        ship_type::types as ship_types
    };
    use influence::types::{Context, Entity, EntityTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct TransitFinished {
        ship: Entity, // ship
        origin: Entity, // origin asteroid
        destination: Entity, // destination asteroid
        departure: u64, // in-game time since EPOCH
        arrival: u64, // in-game time since EPOCH
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        TransitFinished: TransitFinished
    }

    #[external(v0)]
    fn run(ref self: ContractState, caller_crew: Entity, context: Context) {
        // Check that crew is delegated, and ready
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_delegated_to(context.caller);

        // Check if crew is on ship it controls
        let (ship, mut ship_data) = crew_details.ship();
        caller_crew.assert_controls(ship);

        // Get ship data and ensure the flight is complete
        ship_data.assert_ready(context.now);
        assert(ship_data.transit_arrival != 0, errors::TRANSIT_NOT_IN_PROGRESS);

        // Update ship and location components
        components::set::<Location>(ship.path(), LocationTrait::new(ship_data.transit_destination));

        let old_ship_data = ship_data;
        ship_data.complete_transit();

        // For ships in emergency mode, immediately restart propellant generation upon arrival
        if ship_data.emergency_at > 0 {
            ship_data.emergency_at = old_ship_data.ready_at;
        }

        components::set::<Ship>(ship.path(), ship_data);

        self.emit(TransitFinished {
            ship: ship,
            origin: old_ship_data.transit_origin,
            destination: old_ship_data.transit_destination,
            departure: old_ship_data.transit_departure,
            arrival: old_ship_data.transit_arrival,
            caller_crew: caller_crew,
            caller: context.caller
        });
    }
}
