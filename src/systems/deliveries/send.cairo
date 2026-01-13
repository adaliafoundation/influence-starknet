#[starknet::contract]
mod SendDelivery {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use starknet::contract_address::ContractAddress;
    use traits::Into;

    use influence::components;
    use influence::common::{crew::CrewDetailsTrait, inventory, position};
    use influence::config::{entities, errors, permissions};
    use influence::components::{BuildingTypeTrait, Celestial, Control, ControlTrait, Inventory, InventoryTrait,
        Location, LocationTrait, Ship, ShipTrait,
        modifier_type::types as modifier_types,
        product_type::types as products,
        building::{statuses as building_statuses, Building, BuildingTrait},
        delivery::{statuses as delivery_statuses, Delivery}};
    use influence::entities::next_id;
    use influence::types::{Context, Entity, EntityTrait, InventoryItem};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct DeliverySent {
        origin: Entity,
        origin_slot: u64,
        products: Span<InventoryItem>,
        dest: Entity,
        dest_slot: u64,
        delivery: Entity,
        finish_time: u64,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        DeliverySent: DeliverySent
    }

    #[external(v0)]
    fn run(
        ref self: ContractState,
        origin: Entity,
        origin_slot: u64,
        products: Span<InventoryItem>,
        dest: Entity,
        dest_slot: u64,
        caller_crew: Entity,
        context: Context
    ) {
        // Check that crew is delegated, and ready
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_all_but_ready(context.caller, context.now);

        // Check that crew is on asteroid
        let (origin_ast, origin_lot) = origin.to_position();
        let (dest_ast, dest_lot) = dest.to_position();
        assert(crew_details.asteroid_id() == origin_ast, errors::DIFFERENT_ASTEROIDS);
        assert(crew_details.lot_id() != 0, errors::IN_ORBIT);

        // If entities are different, they have to be on the same asteroid and on the surface
        if origin != dest {
            assert(origin_ast == dest_ast, errors::DIFFERENT_ASTEROIDS);
            assert((origin_lot != 0) && (dest_lot != 0), errors::IN_ORBIT);
        }

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

        // Check that the destination exists and is ready to receive
        if dest.label == entities::BUILDING {
            let building_data = components::get::<Building>(dest.path()).expect(errors::BUILDING_NOT_FOUND);
            let config = BuildingTypeTrait::by_type(building_data.building_type);
            let planning = building_data.status == building_statuses::PLANNED && config.site_slot == dest_slot;

            assert(planning || building_data.status == building_statuses::OPERATIONAL, 'inventory inaccessible');
        } else if dest.label == entities::SHIP {
            components::get::<Ship>(dest.path()).expect(errors::SHIP_NOT_FOUND).assert_stationary();
            let location = components::get::<Location>(dest.path()).expect(errors::LOCATION_NOT_FOUND);

            match components::get::<Building>(location.location.path()) {
                Option::Some(building_data) => building_data.assert_operational(),
                Option::None(_) => ()
            };
        }

        // Ensure both inventories are accessible to crew
        caller_crew.assert_can(dest, permissions::ADD_PRODUCTS);
        caller_crew.assert_can(origin, permissions::REMOVE_PRODUCTS);

        // Retrieve inventories and contents
        let mut origin_keys: Array<felt252> = Default::default();
        origin_keys.append(origin.into());
        origin_keys.append(origin_slot.into());
        let mut origin_inv = components::get::<Inventory>(origin_keys.span()).expect(errors::INVENTORY_NOT_FOUND);
        origin_inv.assert_ready();

        let mut dest_keys: Array<felt252> = Default::default();
        dest_keys.append(dest.into());
        dest_keys.append(dest_slot.into());
        let mut dest_inv = components::get::<Inventory>(dest_keys.span()).expect(errors::INVENTORY_NOT_FOUND);
        dest_inv.assert_ready();

        // Calculate transfer time
        let eff = crew_details.bonus(modifier_types::HOPPER_TRANSPORT_TIME, context.now);
        let dist_eff = crew_details.bonus(modifier_types::FREE_TRANSPORT_DISTANCE, context.now);
        let ast = components::get::<Celestial>(EntityTrait::new(entities::ASTEROID, origin_ast).path())
            .expect(errors::CELESTIAL_NOT_FOUND);

        let finish_time = position::hopper_travel_time(origin_lot, dest_lot, ast.radius, eff, dist_eff) + context.now;

        // Reserve space in the destination inventory and validate space
        assert(products.len() > 0, errors::NO_PRODUCTS);
        let mass_eff = crew_details.bonus(modifier_types::INVENTORY_MASS_CAPACITY, context.now);
        let volume_eff = crew_details.bonus(modifier_types::INVENTORY_VOLUME_CAPACITY, context.now);
        inventory::reserve(ref dest_inv, products, mass_eff, volume_eff);
        components::set::<Inventory>(dest_keys.span(), dest_inv);

        // Delete contents in the origin inventory
        inventory::remove(ref origin_inv, products);
        components::set::<Inventory>(origin_keys.span(), origin_inv);

        // Create delivery
        let delivery = EntityTrait::new(entities::DELIVERY, next_id('Delivery'));
        components::set::<Delivery>(delivery.path(), Delivery {
            status: delivery_statuses::SENT,
            origin: origin,
            origin_slot: origin_slot,
            dest: dest,
            dest_slot: dest_slot,
            finish_time: finish_time,
            contents: products
        });

        self.emit(DeliverySent {
            origin: origin,
            origin_slot: origin_slot,
            products: products,
            dest: dest,
            dest_slot: dest_slot,
            delivery: delivery,
            finish_time: finish_time,
            caller_crew: caller_crew,
            caller: context.caller
        });
    }
}
