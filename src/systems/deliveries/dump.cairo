#[starknet::contract]
mod DumpDelivery {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use starknet::contract_address::ContractAddress;
    use traits::Into;

    use influence::components;
    use influence::common::{crew::CrewDetailsTrait, inventory, position};
    use influence::config::{entities, errors, permissions};
    use influence::components::{BuildingTypeTrait, Control, ControlTrait, Inventory, InventoryTrait,
        Location, LocationTrait, Ship, ShipTrait,
        building::{statuses as building_statuses, Building, BuildingTrait}};
    use influence::types::{Context, Entity, EntityTrait, InventoryItem};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct DeliveryDumped {
        origin: Entity,
        origin_slot: u64,
        products: Span<InventoryItem>,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        DeliveryDumped: DeliveryDumped
    }

    #[external(v0)]
    fn run(
        ref self: ContractState,
        origin: Entity,
        origin_slot: u64,
        products: Span<InventoryItem>,
        caller_crew: Entity,
        context: Context
    ) {
        // Check that crew is delegated, and ready
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_all_but_ready(context.caller, context.now);

        // Check that crew is on asteroid
        let (origin_ast, origin_lot) = origin.to_position();
        assert(crew_details.asteroid_id() == origin_ast, errors::DIFFERENT_ASTEROIDS);
        assert(crew_details.lot_id() != 0, errors::IN_ORBIT);

        // Check that the origin exists and is ready to send
        if origin.label == entities::BUILDING {
            let building_data = components::get::<Building>(origin.path()).expect(errors::BUILDING_NOT_FOUND);
            let config = BuildingTypeTrait::by_type(building_data.building_type);
            let planning = building_data.status == building_statuses::PLANNED && config.site_slot == origin_slot;

            assert(planning || building_data.status == building_statuses::OPERATIONAL, 'inventory inaccessible');
        } else if origin.label == entities::SHIP {
            components::get::<Ship>(origin.path()).expect(errors::SHIP_NOT_FOUND).assert_stationary();
            let location = components::get::<Location>(origin.path()).expect(errors::LOCATION_NOT_FOUND);

            match components::get::<Building>(location.location.path()) {
                Option::Some(building_data) => building_data.assert_operational(),
                Option::None(_) => ()
            };
        }

        // Ensure both inventories are accessible to crew
        caller_crew.assert_can(origin, permissions::REMOVE_PRODUCTS);

        // Retrieve inventories and contents
        let mut origin_keys: Array<felt252> = Default::default();
        origin_keys.append(origin.into());
        origin_keys.append(origin_slot.into());
        let mut origin_inv = components::get::<Inventory>(origin_keys.span()).expect(errors::INVENTORY_NOT_FOUND);
        origin_inv.assert_ready();

        // Delete contents in the origin inventory
        inventory::remove(ref origin_inv, products);
        components::set::<Inventory>(origin_keys.span(), origin_inv);

        self.emit(DeliveryDumped {
            origin: origin,
            origin_slot: origin_slot,
            products: products,
            caller_crew: caller_crew,
            caller: context.caller
        });
    }
}
