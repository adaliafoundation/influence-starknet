#[starknet::contract]
mod ReceiveDelivery {
    use array::{Array, ArrayTrait};
    use option::OptionTrait;
    use starknet::contract_address::ContractAddress;
    use traits::Into;

    use influence::components;
    use influence::common::{crew::CrewDetailsTrait, inventory};
    use influence::components::{Inventory, InventoryTrait,
        delivery::{statuses as delivery_statuses, Delivery}};
    use influence::config::errors;
    use influence::types::{Context, Entity, EntityTrait, InventoryItem};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct DeliveryReceived {
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
        DeliveryReceived: DeliveryReceived
    }

    #[external(v0)]
    fn run(ref self: ContractState, delivery: Entity, caller_crew: Entity, context: Context) {
        // Check that crew is delegated
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_delegated_to(context.caller);

        let mut delivery_data: Delivery = components::get::<Delivery>(delivery.path())
            .expect(errors::DELIVERY_NOT_FOUND);

        // Ensure the delivery is not finished and can be finished
        assert(delivery_data.status == delivery_statuses::SENT, errors::INCORRECT_STATUS);
        assert(delivery_data.finish_time <= context.now, errors::DELIVERY_IN_PROGRESS);

        // TODO: check that building / ship is operational

        // Remove reserved space in destination inventory
        let mut dest_keys: Array<felt252> = Default::default();
        dest_keys.append(delivery_data.dest.into());
        dest_keys.append(delivery_data.dest_slot.into());

        let mut dest_inv: Inventory = components::get::<Inventory>(dest_keys.span())
            .expect(errors::INVENTORY_NOT_FOUND);

        inventory::unreserve(ref dest_inv, delivery_data.contents);

        // Add contents to destination inventory
        // Ignore efficiency since we're just swapping reserved space for actual space
        inventory::add_unchecked(ref dest_inv, delivery_data.contents);
        components::set::<Inventory>(dest_keys.span(), dest_inv);

        // Update delivery status
        delivery_data.status = delivery_statuses::COMPLETE;
        components::set::<Delivery>(delivery.path(), delivery_data);

        self.emit(DeliveryReceived {
            origin: delivery_data.origin,
            origin_slot: delivery_data.origin_slot,
            products: delivery_data.contents,
            dest: delivery_data.dest,
            dest_slot: delivery_data.dest_slot,
            delivery: delivery,
            caller_crew: caller_crew,
            caller: context.caller
        });
    }
}
