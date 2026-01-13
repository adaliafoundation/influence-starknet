// Emergency mode is activated for regular ships
// Escape modules are automatically in emergency mode as soon as they are ejected (EjectCrew system)

#[starknet::contract]
mod ActivateEmergency {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use starknet::ContractAddress;
    use traits::Into;

    use influence::components;
    use influence::common::crew::CrewDetailsTrait;
    use influence::components::{Control, ControlTrait, Crew, CrewTrait, Location, LocationTrait, Inventory,
        InventoryTrait,
        ship::{statuses as ship_statuses, Ship, ShipTrait},
        ship_type::{types as ship_types, ShipTypeTrait}
    };
    use influence::config::errors;
    use influence::types::{Context, Entity, EntityTrait, InventoryItem, InventoryItemTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct EmergencyActivated {
        ship: Entity,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        EmergencyActivated: EmergencyActivated
    }

    #[external(v0)]
    fn run(ref self: ContractState, caller_crew: Entity, context: Context) {
        // Check that crew is delegated, and ready
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_all_ready(context.caller, context.now);
        let mut crew_data = crew_details.component;

        // Retrieve the ship and check it's not yet in emergency mode
        let (ship, mut ship_data) = crew_details.ship();
        ship_data.assert_ready(context.now);
        assert(ship_data.ship_type != ship_types::ESCAPE_MODULE, errors::INCORRECT_SHIP_TYPE);
        assert(ship_data.emergency_at == 0, errors::EMERGENCY_ACTIVE);

        // Already know that the caller crew is on the ship, make sure they're the controller
        caller_crew.assert_controls(ship);

        // Check that there are no reservations on ship inventories
        let ship_config = ShipTypeTrait::by_type(ship_data.ship_type);

        let mut cargo_path: Array<felt252> = Default::default();
        cargo_path.append(ship.into());
        cargo_path.append(ship_config.cargo_slot.into());
        let mut cargo_inventory = components::get::<Inventory>(cargo_path.span()).expect(errors::INVENTORY_NOT_FOUND);
        assert(cargo_inventory.reserved_mass + cargo_inventory.reserved_volume == 0, errors::DELIVERY_IN_PROGRESS);

        let mut prop_path: Array<felt252> = Default::default();
        prop_path.append(ship.into());
        prop_path.append(ship_config.propellant_slot.into());
        let prop_inventory = components::get::<Inventory>(prop_path.span()).expect(errors::INVENTORY_NOT_FOUND);
        assert(prop_inventory.reserved_mass + prop_inventory.reserved_volume == 0, errors::DELIVERY_IN_PROGRESS);

        // Purge ship cargo
        cargo_inventory.mass = 0;
        cargo_inventory.volume = 0;
        let empty_contents: Array<InventoryItem> = Default::default();
        cargo_inventory.contents = empty_contents.span();
        components::set::<Inventory>(cargo_path.span(), cargo_inventory);

        // Check that station population equals current crew size (otherwise other crews need to be ejected)
        let (station, station_data) = crew_details.station();
        assert(station_data.population == crew_data.roster.len().into(), errors::OTHER_CREWS_PRESENT);

        // Put ship into emergency mode
        ship_data.emergency_at = context.now;
        components::set::<Ship>(ship.path(), ship_data);

        self.emit(EmergencyActivated {
            ship: ship.into(),
            caller_crew: caller_crew.into(),
            caller: context.caller
        });
    }
}
