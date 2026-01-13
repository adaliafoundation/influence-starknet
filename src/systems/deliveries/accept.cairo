#[starknet::contract]
mod AcceptDelivery {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use starknet::contract_address::ContractAddress;
    use traits::Into;

    use influence::{components, contracts};
    use influence::common::{crew::CrewDetailsTrait, inventory, position};
    use influence::config::{entities, errors, permissions};
    use influence::components::{Building, BuildingTrait, Celestial, Control, ControlTrait, Crew, CrewTrait,
        Inventory, InventoryTrait, Location, LocationTrait, Ship, ShipTrait,
        modifier_type::types as modifier_types,
        product_type::types as products,
        delivery::{statuses as delivery_statuses, Delivery},
        private_sale::{statuses as private_sale_statuses, PrivateSale}};
    use influence::contracts::sway::{ISwayDispatcher, ISwayDispatcherTrait};
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
    fn run(ref self: ContractState, delivery: Entity, caller_crew: Entity, context: Context) {
        // Check that crew is delegated, and ready
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_all_but_ready(context.caller, context.now);

        // Get delivery data
        let mut delivery_data = components::get::<Delivery>(delivery.path()).expect(errors::DELIVERY_NOT_FOUND);
        let origin = delivery_data.origin;
        let origin_slot = delivery_data.origin_slot;
        let products = delivery_data.contents;
        let destination = delivery_data.dest;
        let destination_slot = delivery_data.dest_slot;

        // Check that the delivery is in packaged status and the crew controls the destination
        assert(delivery_data.status == delivery_statuses::PACKAGED, errors::INCORRECT_STATUS);
        caller_crew.assert_controls(destination);

        // Check that crew is on asteroid
        let (origin_ast, origin_lot) = origin.to_position();
        let (dest_ast, dest_lot) = destination.to_position();
        assert(crew_details.asteroid_id() == dest_ast, errors::DIFFERENT_ASTEROIDS);
        assert(crew_details.lot_id() != 0, errors::IN_ORBIT);

        // If a private sale is present, ensure it's paid
        let potential_sale_data = components::get::<PrivateSale>(destination.path());

        if potential_sale_data.is_some() {
            let mut sale_data = potential_sale_data.unwrap();
            assert(sale_data.status == private_sale_statuses::OPEN, errors::INCORRECT_STATUS);
            let seller_crew = origin.controller();
            let seller_crew_data = components::get::<Crew>(seller_crew.path()).expect(errors::CREW_NOT_FOUND);

            // Confirm receipt on SWAY contract for payment to seller
            ISwayDispatcher { contract_address: contracts::get('Sway') }.confirm_receipt(
                context.caller, seller_crew_data.delegated_to, sale_data.amount.into(), delivery.into()
            );

            // Update sale status
            sale_data.status = private_sale_statuses::CLOSED;
            components::set::<PrivateSale>(destination.path(), sale_data);
        }

        // Retrieve origin inventory and unreserve space
        let mut origin_path: Array<felt252> = Default::default();
        origin_path.append(origin.into());
        origin_path.append(origin_slot.into());
        let mut origin_inv = components::get::<Inventory>(origin_path.span()).expect(errors::INVENTORY_NOT_FOUND);
        origin_inv.assert_ready();

        inventory::unreserve(ref origin_inv, products);
        components::set::<Inventory>(origin_path.span(), origin_inv);

        // Retrieve destination inventory and reserve space
        let mut dest_path: Array<felt252> = Default::default();
        dest_path.append(destination.into());
        dest_path.append(destination_slot.into());
        let mut dest_inv = components::get::<Inventory>(dest_path.span()).expect(errors::INVENTORY_NOT_FOUND);
        dest_inv.assert_ready();

        let mass_eff = crew_details.bonus(modifier_types::INVENTORY_MASS_CAPACITY, context.now);
        let volume_eff = crew_details.bonus(modifier_types::INVENTORY_VOLUME_CAPACITY, context.now);
        inventory::reserve(ref dest_inv, products, mass_eff, volume_eff);
        components::set::<Inventory>(dest_path.span(), dest_inv);

        // Calculate transfer time
        let eff = crew_details.bonus(modifier_types::HOPPER_TRANSPORT_TIME, context.now);
        let dist_eff = crew_details.bonus(modifier_types::FREE_TRANSPORT_DISTANCE, context.now);
        let ast = components::get::<Celestial>(EntityTrait::new(entities::ASTEROID, origin_ast).path())
            .expect(errors::CELESTIAL_NOT_FOUND);

        let finish_time = position::hopper_travel_time(origin_lot, dest_lot, ast.radius, eff, dist_eff) + context.now;

        // Update delivery
        delivery_data.status = delivery_statuses::SENT;
        delivery_data.finish_time = finish_time;
        components::set::<Delivery>(delivery.path(), delivery_data);

        self.emit(DeliverySent {
            origin: origin,
            origin_slot: origin_slot,
            products: products,
            dest: delivery_data.dest,
            dest_slot: delivery_data.dest_slot,
            delivery: delivery,
            finish_time: finish_time,
            caller_crew: caller_crew,
            caller: context.caller
        });
    }
}
