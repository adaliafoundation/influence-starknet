#[starknet::contract]
mod CreateBuyOrder {
    use array::{ArrayTrait, SpanTrait};
    use cmp::max;
    use option::OptionTrait;
    use starknet::contract_address::ContractAddress;
    use traits::{Into, TryInto};

    use influence::{components, config, contracts};
    use influence::common::{crew::CrewDetailsTrait, inventory, position};
    use influence::components::{Building, BuildingTrait, Celestial, Control, ControlTrait, Crew, CrewTrait, Exchange,
        Inventory, Location, Ship, ShipTrait,
        modifier_type::types as modifier_types,
        order::{statuses as order_statuses, types as order_types, Order}};
    use influence::config::{entities, errors, permissions};
    use influence::systems::orders::helpers::{adjusted_fee, required_deposit, order_path};
    use influence::types::{SpanTraitExt, Context, Entity, EntityTrait, InventoryItem, InventoryItemTrait};

    use influence::entities::next_id;

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct BuyOrderCreated {
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
        BuyOrderCreated: BuyOrderCreated
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
        escrow_caller: ContractAddress,
        escrow_type: u64,
        escrow_token: ContractAddress,
        escrow_amount: u256,
        mut context: Context
    ) {
        // Check that this call is originating from the escrow contract and extract actual caller
        assert(context.caller == contracts::get('Escrow'), errors::INCORRECT_CALLER);
        context.caller = escrow_caller; // map escrow caller to actual caller

        // Check that crew is delegated, ready and has permission to sell
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_all_ready(context.caller, context.now);
        let mut crew_data = crew_details.component;

        // Check that the exchange is ready and handles this product
        components::get::<Building>(exchange.path()).expect(errors::BUILDING_NOT_FOUND).assert_operational();
        let mut exchange_data = components::get::<Exchange>(exchange.path()).expect(errors::EXCHANGE_NOT_FOUND);
        assert(exchange_data.allowed_products.contains(product), errors::PRODUCT_NOT_ALLOWED);

        // Calculate fees
        assert(price != 0, 'price must be positive');
        let market_crew = components::get::<Control>(exchange.path()).expect(errors::CONTROL_NOT_FOUND).controller;
        let mut market_crew_details = CrewDetailsTrait::new(market_crew);
        let mut _market_crew_data = market_crew_details.component;
        let enforce_eff = market_crew_details.bonus(modifier_types::MARKETPLACE_FEE_ENFORCEMENT, context.now);
        let maker_eff = crew_details.bonus(modifier_types::MARKETPLACE_FEE_REDUCTION, context.now);
        let (deposit, maker_fee) = required_deposit(price * amount, exchange_data.maker_fee, maker_eff, enforce_eff);

        // Ensure Sway is being deposited to escrow and is sufficient
        assert(escrow_type == 1, errors::NOT_ESCROW_DEPOSIT); // 1 = DEPOSIT
        assert(escrow_token.into() == contracts::get('Sway'), errors::INCORRECT_TOKEN);
        assert(escrow_amount.try_into().unwrap() == deposit, 'incorrect deposit');

        caller_crew.assert_can(exchange, permissions::LIMIT_BUY);

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

        caller_crew.assert_can(storage, permissions::ADD_PRODUCTS);

        // Reserve space for products in destination inventory
        let mut destination_path: Array<felt252> = Default::default();
        destination_path.append(storage.into());
        destination_path.append(storage_slot.into());

        let mut destination_data = components::get::<Inventory>(destination_path.span())
            .expect(errors::INVENTORY_NOT_FOUND);

        let mut products: Array<InventoryItem> = Default::default();
        products.append(InventoryItemTrait::new(product, amount));
        let mass_eff = crew_details.bonus(modifier_types::INVENTORY_MASS_CAPACITY, context.now);
        let volume_eff = crew_details.bonus(modifier_types::INVENTORY_VOLUME_CAPACITY, context.now);
        inventory::reserve(ref destination_data, products.span(), mass_eff, volume_eff);
        components::set::<Inventory>(destination_path.span(), destination_data);

        // Calculate surface transfer time for valid at
        let (dest_ast, _dest_lot) = storage.to_position();
        let hopper_eff = crew_details.bonus(modifier_types::HOPPER_TRANSPORT_TIME, context.now);
        let dist_eff = crew_details.bonus(modifier_types::FREE_TRANSPORT_DISTANCE, context.now);
        let ast = components::get::<Celestial>(EntityTrait::new(entities::ASTEROID, dest_ast).path())
            .expect(errors::CELESTIAL_NOT_FOUND);


        // Update the inventory and exchange
        components::set::<Inventory>(destination_path.span(), destination_data);
        exchange_data.orders += 1;
        components::set::<Exchange>(exchange.path(), exchange_data);

        // Update the crew (makers must actually travel to the marketplace)
        assert(crew_details.asteroid_id() == dest_ast, errors::DIFFERENT_ASTEROIDS);
        assert(crew_details.lot_id() != 0, errors::IN_ORBIT);
        let (_exchange_ast, exchange_lot) = exchange.to_position();
        let crew_to_marketplace = position::hopper_travel_time(
            crew_details.lot_id(), exchange_lot, ast.radius, hopper_eff, dist_eff
        );

        // Calculate times
        let valid_time = crew_data.busy_until(context.now) + crew_to_marketplace;
        crew_data.add_busy(context.now, crew_to_marketplace * 2);
        components::set::<Crew>(caller_crew.path(), crew_data);

        let (station_ship, mut station_ship_data) = crew_details.ship();
        if caller_crew != station_ship {
            station_ship_data.extend_ready(crew_data.ready_at);
            components::set::<Ship>(station_ship.path(), station_ship_data);
        }

        // Create order component
        let order_path = order_path(
            caller_crew, exchange, order_types::LIMIT_BUY, product, price, storage, storage_slot
        );

        components::set::<Order>(order_path, Order {
            status: order_statuses::OPEN,
            amount: amount,
            valid_time: valid_time,
            maker_fee: maker_fee
        });

        self.emit(BuyOrderCreated {
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

// Characterization tests: these pin down the current behavior of the buy order system,
// including known defects, so that any intentional behavioral change shows up as a
// deliberate test update rather than a silent regression.
#[cfg(test)]
mod tests {
    use array::{ArrayTrait, Span, SpanTrait};
    use option::OptionTrait;
    use traits::{Into, TryInto};

    use cubit::f64::FixedTrait;

    use influence::components;
    use influence::components::{Exchange, Inventory,
        crewmate::{classes, crewmate_traits, departments},
        order::{statuses as order_statuses, types as order_types, Order},
        product_type::types as product_types};
    use influence::systems::orders::helpers::{order_path, required_deposit};
    use influence::types::{Entity, EntityTrait};
    use influence::test::{helpers, mocks};

    use super::CreateBuyOrder;

    // Fee expectations under the standard modifier configs (see mocks::modifier_type) and a
    // 1% exchange maker fee:
    // - a crew without a Merchant crewmate incurs the class affinity penalty
    //   (1.5 - 0.5^0 = 0.5), halving its fee-reduction efficiency and doubling the fee to 200
    // - a Merchant crewmate removes the penalty (efficiency 1.0), fee 100
    // - a Merchant with an Arts & Entertainment title (rank 2, dept eff 500) adds 5%
    //   efficiency, net 1.05, fee = round(100 / 1.05) = 95
    // - a Mogul on the market crew enforces 1.16 against maker efficiencies above 1.0:
    //   net 1.05 - 0.05 * 0.16 = 1.042, fee = round(100 / 1.042) = 96

    fn setup() -> (Entity, Entity, Entity) {
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        helpers::init();
        return mocks::market_order_fixture();
    }

    fn place_buy_order(
        ref state: CreateBuyOrder::ContractState, crew: Entity, market: Entity, destination: Entity,
        amount: u64, maker_fee: u64
    ) -> u64 {
        let (deposit, _) = required_deposit(amount, maker_fee, FixedTrait::ONE(), FixedTrait::ONE());
        CreateBuyOrder::run(
            ref state,
            exchange: market,
            product: product_types::WATER,
            amount: amount,
            price: 1,
            storage: destination,
            storage_slot: 2,
            caller_crew: crew,
            escrow_caller: starknet::contract_address_const::<'BUYER'>(),
            escrow_type: 1,
            escrow_token: starknet::contract_address_const::<'SWAY'>(),
            escrow_amount: deposit.into(),
            context: mocks::context('ESCROW')
        );
        return deposit;
    }

    fn order_path_of(crew: Entity, market: Entity, destination: Entity) -> Span<felt252> {
        return order_path(crew, market, order_types::LIMIT_BUY, product_types::WATER, 1, destination, 2);
    }

    fn reserved_mass_of(destination: Entity) -> u64 {
        let mut inventory_path: Array<felt252> = Default::default();
        inventory_path.append(destination.into());
        inventory_path.append(2.into());
        return components::get::<Inventory>(inventory_path.span()).unwrap().reserved_mass;
    }

    #[test]
    #[available_gas(100000000)]
    fn test_create_buy_order() {
        let (crew, market, destination) = setup();
        let mut state = CreateBuyOrder::contract_state_for_testing();

        // A crew without a Merchant pays double the exchange's 1% maker fee
        let deposit = place_buy_order(ref state, crew, market, destination, 1000, 200);
        assert(deposit == 1020, 'wrong deposit');

        let order_data = components::get::<Order>(order_path_of(crew, market, destination)).unwrap();
        assert(order_data.status == order_statuses::OPEN, 'wrong status');
        assert(order_data.amount == 1000, 'wrong amount');
        assert(order_data.maker_fee == 200, 'wrong maker fee');
        assert(order_data.valid_time == 0, 'wrong valid time');

        // The exchange counts one open order
        assert(components::get::<Exchange>(market.path()).unwrap().orders == 1, 'wrong order count');

        // The destination inventory reserves space for the purchased products
        assert(reserved_mass_of(destination) == 1000 * 1000, 'wrong reserved mass');
    }

    #[test]
    #[available_gas(100000000)]
    fn test_redeposit_replaces_order_and_strands_escrow() {
        let (crew, market, destination) = setup();
        let mut state = CreateBuyOrder::contract_state_for_testing();

        // Known defect, characterized here: redepositing for an existing open buy order does
        // not grow it. The order component is keyed by (crew, exchange, type, product,
        // price, storage, slot), so the second placement replaces the first, while the
        // escrow pools both deposits under the same order id (caller, token, hook). Fills
        // and cancels only ever pay out against the replaced amount, so the first deposit
        // becomes unreachable without a 7-day forced withdrawal that also drains the live
        // order.
        let deposit1 = place_buy_order(ref state, crew, market, destination, 1000, 200);
        let deposit2 = place_buy_order(ref state, crew, market, destination, 500, 200);

        let path = order_path_of(crew, market, destination);
        let order_data = components::get::<Order>(path).unwrap();
        assert(order_data.status == order_statuses::OPEN, 'wrong status');
        assert(order_data.amount == 500, 'order was not replaced');

        // Both placements are counted as separate orders by the exchange
        assert(components::get::<Exchange>(market.path()).unwrap().orders == 2, 'wrong order count');

        // Reservations accumulate for both placements, but only the replacement order's
        // amount (500) can ever be unreserved by fills and cancels
        assert(reserved_mass_of(destination) == 1500 * 1000, 'wrong reserved mass');

        // The pooled escrow deposits exceed the replacement order's required deposit; the
        // difference is stranded
        let (required, _) = required_deposit(500, 200, FixedTrait::ONE(), FixedTrait::ONE());
        assert(deposit1 + deposit2 - required == 1020, 'wrong stranded deposit');
    }

    #[test]
    #[available_gas(100000000)]
    fn test_each_placement_increments_exchange_order_count() {
        let (crew, market, destination) = setup();
        let mut state = CreateBuyOrder::contract_state_for_testing();

        // Every placement increments the exchange's order count, even when it replaces an
        // existing order at the same key rather than adding a new one
        place_buy_order(ref state, crew, market, destination, 1000, 200);
        assert(components::get::<Exchange>(market.path()).unwrap().orders == 1, 'wrong order count');

        place_buy_order(ref state, crew, market, destination, 500, 200);
        assert(components::get::<Exchange>(market.path()).unwrap().orders == 2, 'wrong order count');

        place_buy_order(ref state, crew, market, destination, 250, 200);
        assert(components::get::<Exchange>(market.path()).unwrap().orders == 3, 'wrong order count');

        // Despite the count of 3, only a single order component exists, holding only the
        // last placement's amount
        let order_data = components::get::<Order>(order_path_of(crew, market, destination)).unwrap();
        assert(order_data.amount == 250, 'order was not replaced');
    }

    #[test]
    #[available_gas(100000000)]
    fn test_merchant_crew_pays_exchange_fee() {
        let (crew, market, destination) = setup();
        let mut state = CreateBuyOrder::contract_state_for_testing();

        // A Merchant crewmate negates the class affinity penalty
        mocks::crewmate_with(1, classes::MERCHANT, 0, array![].span());

        let deposit = place_buy_order(ref state, crew, market, destination, 1000, 100);
        assert(deposit == 1010, 'wrong deposit');

        let order_data = components::get::<Order>(order_path_of(crew, market, destination)).unwrap();
        assert(order_data.maker_fee == 100, 'wrong maker fee');
    }

    #[test]
    #[available_gas(100000000)]
    fn test_arts_merchant_gets_discounted_fee() {
        let (crew, market, destination) = setup();
        let mut state = CreateBuyOrder::contract_state_for_testing();

        // A Merchant with an Arts & Entertainment title adds 5% fee-reduction efficiency;
        // net 1.05 -> fee = round(100 / 1.05) = 95
        mocks::crewmate_with(1, classes::MERCHANT, departments::ARTS_ENTERTAINMENT, array![].span());

        let deposit = place_buy_order(ref state, crew, market, destination, 10000, 95);
        assert(deposit == 10095, 'wrong deposit');

        let order_data = components::get::<Order>(order_path_of(crew, market, destination)).unwrap();
        assert(order_data.maker_fee == 95, 'wrong maker fee');
    }

    #[test]
    #[available_gas(100000000)]
    fn test_mogul_enforcement_ignored_at_par() {
        let (crew, market, destination) = setup();
        let mut state = CreateBuyOrder::contract_state_for_testing();

        // A Mogul on the market crew raises fee enforcement to 1.16, but enforcement only
        // bites maker efficiencies above 1.0; a plain Merchant crew still pays the
        // exchange's maker fee
        mocks::crewmate_with(2, classes::PILOT, 0, array![crewmate_traits::MOGUL].span());
        mocks::crewmate_with(1, classes::MERCHANT, 0, array![].span());

        place_buy_order(ref state, crew, market, destination, 1000, 100);

        let order_data = components::get::<Order>(order_path_of(crew, market, destination)).unwrap();
        assert(order_data.maker_fee == 100, 'wrong maker fee');
    }

    #[test]
    #[available_gas(100000000)]
    fn test_mogul_enforcement_trims_discount() {
        let (crew, market, destination) = setup();
        let mut state = CreateBuyOrder::contract_state_for_testing();

        // An Arts Merchant (efficiency 1.05) against a Mogul market (enforcement 1.16):
        // net 1.05 - 0.05 * 0.16 = 1.042 -> fee = round(100 / 1.042) = 96
        mocks::crewmate_with(2, classes::PILOT, 0, array![crewmate_traits::MOGUL].span());
        mocks::crewmate_with(1, classes::MERCHANT, departments::ARTS_ENTERTAINMENT, array![].span());

        let deposit = place_buy_order(ref state, crew, market, destination, 10000, 96);
        assert(deposit == 10096, 'wrong deposit');

        let order_data = components::get::<Order>(order_path_of(crew, market, destination)).unwrap();
        assert(order_data.maker_fee == 96, 'wrong maker fee');
    }
}
