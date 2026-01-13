#[starknet::contract]
mod CollectEmergencyPropellant {
    use array::{ArrayTrait, SpanTrait};
    use cmp::min;
    use option::OptionTrait;
    use starknet::ContractAddress;
    use traits::{Into, TryInto};

    use cubit::f64::{FixedTrait, ONE};

    use influence::{components, config};
    use influence::common::{crew::CrewDetailsTrait, inventory};
    use influence::components::{Control, ControlTrait, Crew, CrewTrait, Inventory, InventoryTrait, Location,
        LocationTrait, ProductTypeTrait,
        inventory_type::{types as inventory_types, InventoryTypeTrait},
        modifier_type::types as modifier_types,
        product_type::types as products,
        ship::{statuses as ship_statuses, Ship, ShipTrait},
        ship_type::{types as ship_type_types, ShipTypeTrait},
    };
    use influence::config::errors;
    use influence::common::math::RoundedDivTrait;
    use influence::types::{Context, Entity, EntityTrait, InventoryItem, InventoryItemTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct EmergencyPropellantCollected {
        ship: Entity,
        amount: u64,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        EmergencyPropellantCollected: EmergencyPropellantCollected
    }

    #[external(v0)]
    fn run(ref self: ContractState, caller_crew: Entity, context: Context) {
        // Check that crew is delegated, and ready
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_delegated_to(context.caller);
        crew_details.assert_manned();
        crew_details.assert_ready(context.now);
        let mut crew_data = crew_details.component;

        // Retrieve the ship and check that it's in emergency mode
        let (ship, mut ship_data) = crew_details.ship();
        ship_data.assert_ready(context.now);
        assert(ship_data.emergency_at > 0, errors::EMERGENCY_INACTIVE);

        let ship_config = ShipTypeTrait::by_type(ship_data.ship_type);
        let prop_config = InventoryTypeTrait::by_type(ship_config.propellant_inventory_type);

        // NOTE: always volume limited for now, add in mass for potential future propellants
        let max_volume: u128 = (prop_config.volume / ship_config.propellant_emergency_divisor).into();
        let volume_eff = crew_details.bonus(modifier_types::INVENTORY_VOLUME_CAPACITY, context.now);

        let mut prop_path: Array<felt252> = Default::default();
        prop_path.append(ship.into());
        prop_path.append(ship_config.propellant_slot.into());
        let mut prop_inventory = components::get::<Inventory>(prop_path.span()).expect(errors::INVENTORY_NOT_FOUND);

        // Calculate the amount of propellant that was generated
        let elapsed_time = context.now - ship_data.emergency_at;
        let emergency_prop_time: u64 = config::get('EMERGENCY_PROP_GEN_TIME').try_into().unwrap();
        let max_gen_time = emergency_prop_time.div_ceil(config::get('TIME_ACCELERATION').try_into().unwrap());

        let product_config = ProductTypeTrait::by_type(ship_config.propellant_type);
        let prop_volume = product_config.volume;
        let generated_units = (max_volume * elapsed_time.into()) / max_gen_time.into() / prop_volume.into(); // in units
        let modified_max_units = (max_volume * volume_eff.mag.into() / prop_volume.into()) / ONE.into();
        let current_units = prop_inventory.amount_of(ship_config.propellant_type);


        // Check that there isn't already more propellant than the 10% cap
        assert(modified_max_units > current_units.into(), errors::INVENTORY_FULL);

        let actual_generated = (min(generated_units, modified_max_units - current_units.into())).try_into().unwrap();
        let mut to_add: Array<InventoryItem> = Default::default();
        to_add.append(InventoryItemTrait::new(ship_config.propellant_type, actual_generated));

        inventory::add_unchecked(ref prop_inventory, to_add.span());
        components::set::<Inventory>(prop_path.span(), prop_inventory);

        // Update to ship to reflect the new emergency time
        ship_data.emergency_at = context.now;
        components::set::<Ship>(ship.path(), ship_data);

        self.emit(EmergencyPropellantCollected {
            ship: ship.into(),
            amount: actual_generated,
            caller_crew: caller_crew.into(),
            caller: context.caller
        });
    }
}
