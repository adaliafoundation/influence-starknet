#[starknet::contract]
mod DeactivateEmergency {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use starknet::ContractAddress;
    use traits::{Into, TryInto};

    use cubit::f64::{FixedTrait, ONE};

    use influence::components;
    use influence::common::{crew::CrewDetailsTrait, inventory};
    use influence::components::{Control, ControlTrait, Crew, CrewTrait, Inventory, Location, LocationTrait,
        inventory_type::{types as inventory_types, InventoryTypeTrait},
        modifier_type::types as modifier_types,
        ship::{statuses as ship_statuses, Ship, ShipTrait},
        ship_type::{types as ship_types, ShipTypeTrait},
    };
    use influence::config::{errors};
    use influence::types::{Context, Entity, EntityTrait, InventoryItem, InventoryItemTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct EmergencyDeactivated {
        ship: Entity,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        EmergencyDeactivated: EmergencyDeactivated
    }

    #[external(v0)]
    fn run(ref self: ContractState, caller_crew: Entity, context: Context) {
        // Check that crew is delegated, and ready
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_delegated_to(context.caller);
        crew_details.assert_manned();
        crew_details.assert_ready(context.now);
        let mut crew_data = crew_details.component;

        // Retrieve the ship and check that it's in emergency mode (and not an escape module)
        let (ship, mut ship_data) = crew_details.ship();
        ship_data.assert_ready(context.now);
        assert(ship_data.ship_type != ship_types::ESCAPE_MODULE, errors::INCORRECT_SHIP_TYPE);
        assert(ship_data.emergency_at > 0, errors::EMERGENCY_INACTIVE);

        // Purge up to 10% of propellant tanks
        let ship_config = ShipTypeTrait::by_type(ship_data.ship_type);
        let prop_config = InventoryTypeTrait::by_type(ship_config.propellant_inventory_type);

        // NOTE: always volume limited for now, add in mass for potential future propellants
        let mut max_volume: u128 = (prop_config.volume / ship_config.propellant_emergency_divisor).into();
        let volume_eff = crew_details.bonus(modifier_types::INVENTORY_VOLUME_CAPACITY, context.now);
        max_volume = max_volume * volume_eff.mag.into() / ONE.into();

        let mut prop_path: Array<felt252> = Default::default();
        prop_path.append(ship.into());
        prop_path.append(ship_config.propellant_slot.into());
        let mut prop_inventory = components::get::<Inventory>(prop_path.span()).expect(errors::INVENTORY_NOT_FOUND);

        // Remove up to 10% of the propellant inventory volume
        let remove_volume = cmp::min(prop_inventory.volume.into(), max_volume);
        let mut to_remove: Array<InventoryItem> = Default::default();
        let mut iter = 0;

        loop {
            if iter >= prop_inventory.contents.len() { break; }
            let mut item = *prop_inventory.contents.at(iter);
            item.amount = (item.amount.into() * remove_volume / prop_inventory.volume.into()).try_into().unwrap();
            to_remove.append(item);
            iter += 1;
        };

        inventory::remove(ref prop_inventory, to_remove.span());
        components::set::<Inventory>(prop_path.span(), prop_inventory);

        ship_data.emergency_at = 0;
        components::set::<Ship>(ship.path(), ship_data);

        self.emit(EmergencyDeactivated {
            ship: ship.into(),
            caller_crew: caller_crew.into(),
            caller: context.caller
        });
    }
}
