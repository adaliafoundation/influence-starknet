#[starknet::contract]
mod CancelSellOrder {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use starknet::contract_address::ContractAddress;
    use traits::{Into, TryInto};

    use influence::{components, config};
    use influence::common::{crew::CrewDetailsTrait, inventory, position};
    use influence::components::{Building, BuildingTrait, Celestial, Control, ControlTrait, Exchange,
        modifier_type::types as modifier_types,
        delivery::{statuses as delivery_statuses, Delivery},
        order::{statuses as order_statuses, types as order_types, Order}};
    use influence::config::{entities, errors, permissions};
    use influence::systems::orders::helpers::order_path;
    use influence::types::{SpanTraitExt, Context, Entity, EntityTrait, InventoryItem, InventoryItemTrait};

    use influence::entities::next_id;

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

    #[derive(Copy, Drop, starknet::Event)]
    struct SellOrderCancelled {
        seller_crew: Entity,
        exchange: Entity,
        product: u64,
        price: u64,
        storage: Entity,
        storage_slot: u64,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        DeliverySent: DeliverySent,
        SellOrderCancelled: SellOrderCancelled
    }

    #[external(v0)]
    fn run(
        ref self: ContractState,
        seller_crew: Entity,
        exchange: Entity,
        product: u64,
        price: u64,
        storage: Entity,
        storage_slot: u64,
        caller_crew: Entity,
        context: Context
    ) {
        // Check that crew is delegated, ready
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_all_but_ready(context.caller, context.now);

        // When caller is not the seller, check that caller has control and the seller no longer has permission
        if caller_crew != seller_crew {
            caller_crew.assert_controls(exchange);
            let can_sell = seller_crew.can(exchange, permissions::LIMIT_SELL);
            let can_store = seller_crew.can(storage, permissions::REMOVE_PRODUCTS);
            assert(!can_sell || !can_store, errors::ACCESS_DENIED);
        }

        // Validate order is cancellable
        let order_path = order_path(
            seller_crew, exchange, order_types::LIMIT_SELL, product, price, storage, storage_slot
        );

        let mut order_data = components::get::<Order>(order_path).expect(errors::ORDER_NOT_FOUND);
        assert(order_data.status == order_statuses::OPEN, errors::INCORRECT_STATUS);

        // Calculate transfer time
        let (exchange_ast, exchange_lot) = exchange.to_position();
        let (dest_ast, dest_lot) = storage.to_position();
        let eff = crew_details.bonus(modifier_types::HOPPER_TRANSPORT_TIME, context.now);
        let dist_eff = crew_details.bonus(modifier_types::FREE_TRANSPORT_DISTANCE, context.now);
        let ast = components::get::<Celestial>(EntityTrait::new(entities::ASTEROID, exchange_ast).path())
            .expect(errors::CELESTIAL_NOT_FOUND);

        let finish_time = position::hopper_travel_time(exchange_lot, dest_lot, ast.radius, eff, dist_eff) + context.now;

        // Create delivery to return the goods
        let mut products: Array<InventoryItem> = Default::default();
        products.append(InventoryItemTrait::new(product, order_data.amount));
        let delivery = EntityTrait::new(entities::DELIVERY, next_id('Delivery'));
        components::set::<Delivery>(delivery.path(), Delivery {
            status: delivery_statuses::SENT,
            origin: exchange,
            origin_slot: 0,
            dest: storage,
            dest_slot: storage_slot,
            finish_time: finish_time,
            contents: products.span()
        });

        // Update the order
        order_data.status = order_statuses::CANCELLED;
        components::set::<Order>(order_path, order_data);

        // Update the exchange
        let mut exchange_data = components::get::<Exchange>(exchange.path()).expect(errors::EXCHANGE_NOT_FOUND);
        exchange_data.orders -= 1;
        components::set::<Exchange>(exchange.path(), exchange_data);

        self.emit(SellOrderCancelled {
            seller_crew: seller_crew,
            exchange: exchange,
            product: product,
            price: price,
            storage: storage,
            storage_slot: storage_slot,
            caller_crew: caller_crew,
            caller: context.caller
        });

        self.emit(DeliverySent {
            origin: exchange,
            origin_slot: 0,
            products: products.span(),
            dest: storage,
            dest_slot: storage_slot,
            delivery: delivery,
            finish_time: finish_time,
            caller_crew: caller_crew,
            caller: context.caller
        });
    }
}
