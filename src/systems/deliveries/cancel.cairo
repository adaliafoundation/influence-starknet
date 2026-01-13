#[starknet::contract]
mod CancelDelivery {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use starknet::contract_address::ContractAddress;
    use traits::Into;

    use influence::components;
    use influence::common::{crew::CrewDetailsTrait, inventory, position};
    use influence::config::{entities, errors, permissions};
    use influence::components::{Building, BuildingTrait, Celestial, Control, ControlTrait, Inventory, InventoryTrait,
        Location, LocationTrait, PrivateSale, Ship, ShipTrait,
        modifier_type::types as modifier_types,
        product_type::types as products,
        delivery::{statuses as delivery_statuses, Delivery}};
    use influence::entities::next_id;
    use influence::types::{Context, Entity, EntityTrait, InventoryItem};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct DeliveryCancelled {
        origin: Entity,
        origin_slot: u64,
        products: Span<InventoryItem>,
        dest: Entity,
        dest_slot: u64,
        delivery: Entity,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        DeliveryCancelled: DeliveryCancelled
    }

    #[external(v0)]
    fn run(ref self: ContractState, delivery: Entity, caller_crew: Entity, context: Context) {
        // Check that crew is delegated, and ready
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_all_but_ready(context.caller, context.now);

        // Get delivery data
        let mut delivery_data = components::get::<Delivery>(delivery.path()).expect(errors::DELIVERY_NOT_FOUND);
        let origin = delivery_data.origin;
        let origin_slot = delivery_data.origin_slot;
        let dest = delivery_data.dest;
        let dest_slot = delivery_data.dest_slot;
        let products = delivery_data.contents;

        // Check that crew is on asteroid
        let (origin_ast, origin_lot) = origin.to_position();
        assert(crew_details.asteroid_id() == origin_ast, errors::DIFFERENT_ASTEROIDS);
        assert(crew_details.lot_id() != 0, errors::IN_ORBIT);

        // Retrieve inventories and contents
        let mut origin_path: Array<felt252> = Default::default();
        origin_path.append(origin.into());
        origin_path.append(origin_slot.into());
        let mut origin_inv = components::get::<Inventory>(origin_path.span()).expect(errors::INVENTORY_NOT_FOUND);
        origin_inv.assert_ready();

        if delivery_data.status == delivery_statuses::PACKAGED {
            // Check that the delivery is in packaged status and the crew can add products to dest OR
            // remove products from origin (i.e. they had permission to start the delivery in the first place)
            let add_to_dest = caller_crew.can(dest, permissions::ADD_PRODUCTS);
            let remove_from_origin = caller_crew.can(origin, permissions::REMOVE_PRODUCTS);
            assert(add_to_dest || remove_from_origin, errors::ACCESS_DENIED);

            // Unreserve space and add products
            inventory::unreserve(ref origin_inv, products); // unreserve space on origin
            inventory::add_unchecked(ref origin_inv, products); // add products back to origin
        } else if delivery_data.status == delivery_statuses::SENT {
            // If cancelling a sent delivery crew needs permission to remove products on the destination
            // as well as to add products on origin. It also must have already reached the destiation.
            assert(delivery_data.finish_time <= context.now, errors::DELIVERY_IN_PROGRESS);
            // TODO: either has remove products permission or the building / ship is no longer operational
            caller_crew.assert_can(dest, permissions::REMOVE_PRODUCTS);
            caller_crew.assert_can(origin, permissions::ADD_PRODUCTS);

            // Retrieve destination inventory
            let mut dest_path: Array<felt252> = Default::default();
            dest_path.append(dest.into());
            dest_path.append(dest_slot.into());
            let mut dest_inv = components::get::<Inventory>(dest_path.span()).expect(errors::INVENTORY_NOT_FOUND);

            // Unreserve space and add products
            let mass_eff = crew_details.bonus(modifier_types::INVENTORY_MASS_CAPACITY, context.now);
            let volume_eff = crew_details.bonus(modifier_types::INVENTORY_VOLUME_CAPACITY, context.now);
            inventory::unreserve(ref dest_inv, products); // unreserve space on destination
            components::set::<Inventory>(dest_path.span(), dest_inv);
            inventory::add(ref origin_inv, products, mass_eff, volume_eff); // add products back to origin
        }

        // Update delivery
        components::set::<Inventory>(origin_path.span(), origin_inv); // origin updated in both scenarios
        delivery_data.status = 0;
        components::set::<Delivery>(delivery.path(), delivery_data);

        self.emit(DeliveryCancelled {
            origin: origin,
            origin_slot: origin_slot,
            products: products,
            dest: delivery_data.dest,
            dest_slot: delivery_data.dest_slot,
            delivery: delivery,
            caller_crew: caller_crew,
            caller: context.caller
        });
    }
}
