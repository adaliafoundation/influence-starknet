#[starknet::contract]
mod CreateSellOrder {
    use array::{ArrayTrait, SpanTrait};
    use cmp::max;
    use option::OptionTrait;
    use starknet::contract_address::ContractAddress;
    use traits::{Into, TryInto};

    use influence::{components, config};
    use influence::common::{crew::CrewDetailsTrait, inventory, position};
    use influence::components::{Building, BuildingTrait, Celestial, Control, ControlTrait, Crew, CrewTrait, Exchange,
        Inventory, Location, Ship, ShipTrait,
        modifier_type::types as modifier_types,
        order::{statuses as order_statuses, types as order_types, Order}};
    use influence::config::{entities, errors, permissions};
    use influence::systems::orders::helpers::{adjusted_fee, order_path};
    use influence::types::{SpanTraitExt, Context, Entity, EntityTrait, InventoryItem, InventoryItemTrait};

    use influence::entities::next_id;

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct SellOrderCreated {
        exchange: Entity,
        product: u64,
        amount: u64,
        price: u64,
        storage: Entity,
        storage_slot: u64,
        valid_time: u64,
        maker_fee: u64,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        SellOrderCreated: SellOrderCreated
    }

    #[external(v0)]
    fn run(
        ref self: ContractState,
        exchange: Entity,
        product: u64,
        amount: u64,
        price: u64,
        storage: Entity,
        storage_slot: u64,
        caller_crew: Entity,
        context: Context
    ) {
        // Check that crew is delegated, ready and has permission to sell
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_all_ready(context.caller, context.now);
        let mut crew_data = crew_details.component;

        caller_crew.assert_can(exchange, permissions::LIMIT_SELL);

        // Check that the exchange is ready and handles this product
        components::get::<Building>(exchange.path()).expect(errors::BUILDING_NOT_FOUND).assert_operational();
        let mut exchange_data = components::get::<Exchange>(exchange.path()).expect(errors::EXCHANGE_NOT_FOUND);
        assert(exchange_data.allowed_products.contains(product), errors::PRODUCT_NOT_ALLOWED);

        // Check that the storage exists and is ready to send
        if storage.label == entities::BUILDING {
            components::get::<Building>(storage.path()).expect(errors::BUILDING_NOT_FOUND).assert_operational();
        } else if storage.label == entities::SHIP {
            components::get::<Ship>(storage.path()).expect(errors::SHIP_NOT_FOUND).assert_stationary();
            let location = components::get::<Location>(storage.path()).expect(errors::LOCATION_NOT_FOUND);

            match components::get::<Building>(location.location.path()) {
                Option::Some(building_data) => building_data.assert_operational(),
                Option::None(_) => ()
            };
        }

        caller_crew.assert_can(storage, permissions::REMOVE_PRODUCTS);

        let mut origin_path: Array<felt252> = Default::default();
        origin_path.append(storage.into());
        origin_path.append(storage_slot.into());

        let mut origin_data = components::get::<Inventory>(origin_path.span()).expect(errors::INVENTORY_NOT_FOUND);
        let mut products: Array<InventoryItem> = Default::default();
        products.append(InventoryItemTrait::new(product, amount));
        inventory::remove(ref origin_data, products.span());

        // Reserve space in origin for potential cancellation
        inventory::reserve_unchecked(ref origin_data, products.span());
        components::set::<Inventory>(origin_path.span(), origin_data);

        // Calculate surface transfer time for valid at
        let (origin_ast, origin_lot) = storage.to_position();
        let hopper_eff = crew_details.bonus(modifier_types::HOPPER_TRANSPORT_TIME, context.now);
        let dist_eff = crew_details.bonus(modifier_types::FREE_TRANSPORT_DISTANCE, context.now);
        let ast = components::get::<Celestial>(EntityTrait::new(entities::ASTEROID, origin_ast).path())
            .expect(errors::CELESTIAL_NOT_FOUND);

        let (exchange_ast, exchange_lot) = exchange.to_position();
        assert(origin_ast == exchange_ast, errors::DIFFERENT_ASTEROIDS);
        assert(origin_lot != 0, errors::IN_ORBIT);
        let origin_to_exchange = position::hopper_travel_time(
            origin_lot, exchange_lot, ast.radius, hopper_eff, dist_eff
        );

        // Update the exchange
        exchange_data.orders += 1;
        components::set::<Exchange>(exchange.path(), exchange_data);

        // Update the crew (makers must actually travel to the marketplace)
        assert(crew_details.asteroid_id() == origin_ast, errors::DIFFERENT_ASTEROIDS);
        assert(crew_details.lot_id() != 0, errors::IN_ORBIT);
        let crew_to_marketplace = position::hopper_travel_time(
            crew_details.lot_id(), exchange_lot, ast.radius, hopper_eff, dist_eff
        );

        // Calculate times
        let order_readiness = max(origin_to_exchange, crew_to_marketplace);
        let valid_time = crew_data.busy_until(context.now) + order_readiness;
        crew_data.add_busy(context.now, order_readiness + crew_to_marketplace);
        components::set::<Crew>(caller_crew.path(), crew_data);

        let (station_ship, mut station_ship_data) = crew_details.ship();
        if caller_crew != station_ship {
            station_ship_data.extend_ready(crew_data.ready_at);
            components::set::<Ship>(station_ship.path(), station_ship_data);
        }

        // Calculate fees
        assert(price != 0, 'price must be positive');
        let market_crew = components::get::<Control>(exchange.path()).expect(errors::CONTROL_NOT_FOUND).controller;
        let mut market_crew_details = CrewDetailsTrait::new(market_crew);
        let mut market_crew_data = market_crew_details.component;
        let enforce_eff = market_crew_details.bonus(modifier_types::MARKETPLACE_FEE_ENFORCEMENT, context.now);
        let maker_eff = crew_details.bonus(modifier_types::MARKETPLACE_FEE_REDUCTION, context.now);
        let maker_fee = adjusted_fee(exchange_data.maker_fee, maker_eff, enforce_eff);

        // Create order component
        let order_path = order_path(
            caller_crew, exchange, order_types::LIMIT_SELL, product, price, storage, storage_slot
        );

        let mut new_order_data = Order {
            status: order_statuses::OPEN,
            amount: amount,
            valid_time: valid_time,
            maker_fee: maker_fee
        };

        // If order already exists and is open, add to it, otherwise create it
        match components::get::<Order>(order_path) {
            Option::Some(mut existing_order_data) => {
                if existing_order_data.status == order_statuses::OPEN {
                    new_order_data.amount += existing_order_data.amount;
                }
            },
            Option::None(_) => ()
        };

        components::set::<Order>(order_path, new_order_data);

        self.emit(SellOrderCreated {
            exchange: exchange,
            product: product,
            amount: amount,
            price: price,
            storage: storage,
            storage_slot: storage_slot,
            valid_time: valid_time,
            maker_fee: maker_fee,
            caller_crew: caller_crew,
            caller: context.caller
        });
    }
}
