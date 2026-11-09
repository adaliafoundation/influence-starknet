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
        let mut _market_crew_data = market_crew_details.component;
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

// Tests --------------------------------------------------------------------------------------------------------------

// Characterization tests: these pin down the current behavior of the sell order system,
// including known quirks, so that any intentional behavioral change shows up as a
// deliberate test update rather than a silent regression.
#[cfg(test)]
mod tests {
    use array::{ArrayTrait, Span, SpanTrait};
    use option::OptionTrait;
    use traits::{Into, TryInto};

    use influence::common::inventory;
    use influence::components;
    use influence::components::{Exchange, Inventory,
        crewmate::{classes, crewmate_traits, departments},
        order::{statuses as order_statuses, types as order_types, Order},
        product_type::types as product_types};
    use influence::systems::orders::helpers::order_path;
    use influence::types::{Entity, EntityTrait, InventoryItem, InventoryItemTrait};
    use influence::test::{helpers, mocks};

    use super::CreateSellOrder;

    fn setup() -> (Entity, Entity, Entity) {
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        helpers::init();
        return mocks::market_order_fixture();
    }

    // Sell orders escrow products in the origin inventory: the products are removed from the
    // inventory and the same space is reserved again so a later cancellation can return them.

    fn stock_origin(origin: Entity, amount: u64) {
        let mut inventory_path: Array<felt252> = Default::default();
        inventory_path.append(origin.into());
        inventory_path.append(2.into());
        let mut inventory_data = components::get::<Inventory>(inventory_path.span()).unwrap();
        let mut supplies: Array<InventoryItem> = Default::default();
        supplies.append(InventoryItemTrait::new(product_types::WATER, amount));
        inventory::add_unchecked(ref inventory_data, supplies.span());
        components::set::<Inventory>(inventory_path.span(), inventory_data);
    }

    fn place_sell_order(
        ref state: CreateSellOrder::ContractState, crew: Entity, market: Entity, origin: Entity, amount: u64
    ) {
        CreateSellOrder::run(
            ref state,
            exchange: market,
            product: product_types::WATER,
            amount: amount,
            price: 1,
            storage: origin,
            storage_slot: 2,
            caller_crew: crew,
            context: mocks::context('BUYER')
        );
    }

    fn order_path_of(crew: Entity, market: Entity, origin: Entity) -> Span<felt252> {
        return order_path(crew, market, order_types::LIMIT_SELL, product_types::WATER, 1, origin, 2);
    }

    fn inventory_of(origin: Entity) -> Inventory {
        let mut inventory_path: Array<felt252> = Default::default();
        inventory_path.append(origin.into());
        inventory_path.append(2.into());
        return components::get::<Inventory>(inventory_path.span()).unwrap();
    }

    #[test]
    #[available_gas(100000000)]
    fn test_create_sell_order() {
        let (crew, market, origin) = setup();
        let mut state = CreateSellOrder::contract_state_for_testing();

        stock_origin(origin, 1000);

        // A crew without a Merchant pays double the exchange's 1% maker fee
        place_sell_order(ref state, crew, market, origin, 1000);

        let order_data = components::get::<Order>(order_path_of(crew, market, origin)).unwrap();
        assert(order_data.status == order_statuses::OPEN, 'wrong status');
        assert(order_data.amount == 1000, 'wrong amount');
        assert(order_data.maker_fee == 200, 'wrong maker fee');
        assert(order_data.valid_time == 0, 'wrong valid time');

        // The exchange counts one open order
        assert(components::get::<Exchange>(market.path()).unwrap().orders == 1, 'wrong order count');

        // The sold products are removed from the origin and the space is reserved for a
        // potential cancellation
        let inventory_data = inventory_of(origin);
        assert(inventory_data.mass == 0, 'wrong mass');
        assert(inventory_data.reserved_mass == 1000 * 1000, 'wrong reserved mass');
        assert(inventory_data.reserved_volume == 1000 * 971, 'wrong reserved volume');
        assert(inventory_data.contents.len() == 0, 'wrong contents');
    }

    #[test]
    #[available_gas(100000000)]
    fn test_redeposit_grows_sell_order() {
        let (crew, market, origin) = setup();
        let mut state = CreateSellOrder::contract_state_for_testing();

        stock_origin(origin, 1500);

        // Unlike buy orders, redepositing for an existing open sell order grows it: the
        // order amounts accumulate, matching the products escrowed in the origin inventory
        place_sell_order(ref state, crew, market, origin, 1000);
        place_sell_order(ref state, crew, market, origin, 500);

        let order_data = components::get::<Order>(order_path_of(crew, market, origin)).unwrap();
        assert(order_data.status == order_statuses::OPEN, 'wrong status');
        assert(order_data.amount == 1500, 'wrong amount');

        // Quirk: the exchange counts each placement as a separate order, so the grown order
        // is counted twice even though fills only ever decrement it once
        assert(components::get::<Exchange>(market.path()).unwrap().orders == 2, 'wrong order count');

        let inventory_data = inventory_of(origin);
        assert(inventory_data.mass == 0, 'wrong mass');
        assert(inventory_data.reserved_mass == 1500 * 1000, 'wrong reserved mass');
        assert(inventory_data.contents.len() == 0, 'wrong contents');
    }

    #[test]
    #[available_gas(100000000)]
    fn test_each_placement_increments_exchange_order_count() {
        let (crew, market, origin) = setup();
        let mut state = CreateSellOrder::contract_state_for_testing();

        stock_origin(origin, 1750);

        // Every placement increments the exchange's order count, even when it grows an
        // existing order at the same key rather than adding a new one
        place_sell_order(ref state, crew, market, origin, 1000);
        assert(components::get::<Exchange>(market.path()).unwrap().orders == 1, 'wrong order count');

        place_sell_order(ref state, crew, market, origin, 500);
        assert(components::get::<Exchange>(market.path()).unwrap().orders == 2, 'wrong order count');

        place_sell_order(ref state, crew, market, origin, 250);
        assert(components::get::<Exchange>(market.path()).unwrap().orders == 3, 'wrong order count');

        // The placements accumulated into a single order component, so fills can only ever
        // decrement the count once even though it was incremented three times
        let order_data = components::get::<Order>(order_path_of(crew, market, origin)).unwrap();
        assert(order_data.amount == 1750, 'wrong amount');
    }

    #[test]
    #[available_gas(100000000)]
    fn test_merchant_crew_pays_exchange_fee() {
        let (crew, market, origin) = setup();
        let mut state = CreateSellOrder::contract_state_for_testing();

        stock_origin(origin, 1000);

        // A Merchant crewmate negates the class affinity penalty
        mocks::crewmate_with(1, classes::MERCHANT, 0, array![].span());

        place_sell_order(ref state, crew, market, origin, 1000);

        let order_data = components::get::<Order>(order_path_of(crew, market, origin)).unwrap();
        assert(order_data.maker_fee == 100, 'wrong maker fee');
    }

    #[test]
    #[available_gas(100000000)]
    fn test_mogul_enforcement_trims_discount() {
        let (crew, market, origin) = setup();
        let mut state = CreateSellOrder::contract_state_for_testing();

        stock_origin(origin, 1000);

        // An Arts Merchant (efficiency 1.05) against a Mogul market (enforcement 1.16):
        // net 1.05 - 0.05 * 0.16 = 1.042 -> fee = round(100 / 1.042) = 96
        mocks::crewmate_with(2, classes::PILOT, 0, array![crewmate_traits::MOGUL].span());
        mocks::crewmate_with(1, classes::MERCHANT, departments::ARTS_ENTERTAINMENT, array![].span());

        place_sell_order(ref state, crew, market, origin, 1000);

        let order_data = components::get::<Order>(order_path_of(crew, market, origin)).unwrap();
        assert(order_data.maker_fee == 96, 'wrong maker fee');
    }

    #[test]
    #[should_panic(expected: ('removing too many', ))]
    #[available_gas(100000000)]
    fn test_sell_rejects_insufficient_inventory() {
        let (crew, market, origin) = setup();
        let mut state = CreateSellOrder::contract_state_for_testing();

        stock_origin(origin, 500);
        place_sell_order(ref state, crew, market, origin, 1000);
    }
}
