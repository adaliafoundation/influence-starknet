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

        // Check that no open order already exists at this order path. Orders cannot be
        // modified or grown after placement: the escrow pools deposits by order id, so a
        // replacement would strand the existing order's escrowed deposit
        let order_path = order_path(
            caller_crew, exchange, order_types::LIMIT_BUY, product, price, storage, storage_slot
        );
        match components::get::<Order>(order_path) {
            Option::Some(existing_order_data) => {
                assert(existing_order_data.status != order_statuses::OPEN, errors::ORDER_ALREADY_EXISTS);
            },
            Option::None(_) => ()
        };

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
    use result::Result;
    use serde::Serde;
    use starknet::{call_contract_syscall, ContractAddress};
    use traits::Into;

    use cubit::f64::FixedTrait;

    use influence::components;
    use influence::components::{Exchange, Inventory, Location, LocationTrait,
        delivery::{statuses as delivery_statuses, Delivery},
        crewmate::{classes, crewmate_traits, departments},
        order::{statuses as order_statuses, types as order_types, Order},
        product_type::types as product_types};
    use influence::config::entities;
    use influence::contracts::escrow::{IERC20Dispatcher, IERC20DispatcherTrait};
    use influence::interfaces::escrow::{IEscrowDispatcher, IEscrowDispatcherTrait, Hook, Withdrawal};
    use influence::systems::orders::fill_buy::FillBuyOrder;
    use influence::systems::orders::helpers::{order_path, required_deposit, required_withdrawals};
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
        return place_buy_order_at(ref state, crew, market, destination, 1, amount, maker_fee);
    }

    fn place_buy_order_at(
        ref state: CreateBuyOrder::ContractState, crew: Entity, market: Entity, destination: Entity,
        price: u64, amount: u64, maker_fee: u64
    ) -> u64 {
        let (deposit, _) = required_deposit(price * amount, maker_fee, FixedTrait::ONE(), FixedTrait::ONE());
        CreateBuyOrder::run(
            ref state,
            exchange: market,
            product: product_types::WATER,
            amount: amount,
            price: price,
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
        return order_path_at(crew, market, destination, 1);
    }

    fn order_path_at(crew: Entity, market: Entity, destination: Entity, price: u64) -> Span<felt252> {
        return order_path(crew, market, order_types::LIMIT_BUY, product_types::WATER, price, destination, 2);
    }

    fn reserved_mass_of(destination: Entity) -> u64 {
        let mut inventory_path: Array<felt252> = Default::default();
        inventory_path.append(destination.into());
        inventory_path.append(2.into());
        return components::get::<Inventory>(inventory_path.span()).unwrap().reserved_mass;
    }

    fn reserved_volume_of(destination: Entity) -> u64 {
        let mut inventory_path: Array<felt252> = Default::default();
        inventory_path.append(destination.into());
        inventory_path.append(2.into());
        return components::get::<Inventory>(inventory_path.span()).unwrap().reserved_volume;
    }

    fn set_zero_taker_fee(market: Entity) {
        let mut exchange_data = components::get::<Exchange>(market.path()).unwrap();
        exchange_data.taker_fee = 0;
        components::set::<Exchange>(market.path(), exchange_data);
    }

    fn fill_buy_order(
        ref state: FillBuyOrder::ContractState, buyer_crew: Entity, market: Entity, destination: Entity,
        price: u64, amount: u64, seller_crew: Entity, source: Entity, maker_fee: u64
    ) {
        let (to_market, to_seller) = required_withdrawals(
            price * amount, maker_fee, 0, FixedTrait::ONE(), FixedTrait::ONE()
        );
        let withdrawals = array![
            Withdrawal {
                recipient: starknet::contract_address_const::<'SELLER'>(), amount: to_seller.into()
            },
            Withdrawal {
                recipient: starknet::contract_address_const::<'MARKET'>(), amount: to_market.into()
            }
        ];

        FillBuyOrder::run(
            ref state,
            buyer_crew: buyer_crew,
            exchange: market,
            product: product_types::WATER,
            price: price,
            storage: destination,
            storage_slot: 2,
            amount: amount,
            origin: source,
            origin_slot: 2,
            caller_crew: seller_crew,
            escrow_caller: starknet::contract_address_const::<'SELLER'>(),
            escrow_type: 2,
            escrow_token: starknet::contract_address_const::<'SWAY'>(),
            escrow_withdrawals: withdrawals.span(),
            context: mocks::context('ESCROW')
        );
    }


    fn append_span(ref destination: Array<felt252>, values: Span<felt252>) {
        let mut index = 0;
        loop {
            if index >= values.len() {
                break;
            };
            destination.append(*values.at(index));
            index += 1;
        };
    }

    fn system_hook(
        dispatcher: ContractAddress, system: felt252, system_args: Array<felt252>, appended_args: u32
    ) -> Hook {
        let mut calldata: Array<felt252> = array![system];
        calldata.append((system_args.len() + appended_args).into());
        append_span(ref calldata, system_args.span());

        return Hook {
            contract: dispatcher,
            entry_point_selector: selector!("run_system"),
            calldata: calldata.span()
        };
    }

    fn buy_order_hooks(
        dispatcher: ContractAddress, buyer_crew: Entity, market: Entity, destination: Entity, price: u64,
        amount: u64
    ) -> (Hook, Hook) {
        let mut create_args: Array<felt252> = Default::default();
        Serde::<Entity>::serialize(@market, ref create_args);
        create_args.append(product_types::WATER.into());
        create_args.append(amount.into());
        create_args.append(price.into());
        Serde::<Entity>::serialize(@destination, ref create_args);
        create_args.append(2);
        Serde::<Entity>::serialize(@buyer_crew, ref create_args);

        let mut fill_args: Array<felt252> = Default::default();
        Serde::<Entity>::serialize(@buyer_crew, ref fill_args);
        Serde::<Entity>::serialize(@market, ref fill_args);
        fill_args.append(product_types::WATER.into());
        fill_args.append(price.into());
        Serde::<Entity>::serialize(@destination, ref fill_args);
        fill_args.append(2);

        // Escrow appends caller, hook type, token, and u256 amount for deposits.
        let deposit_hook = system_hook(dispatcher, 'CreateBuyOrder', create_args, 5);
        // Withdrawals append six fill arguments plus caller, hook type, token, and two payments.
        let withdraw_hook = system_hook(dispatcher, 'FillBuyOrder', fill_args, 16);
        return (deposit_hook, withdraw_hook);
    }

    fn deposit_escrow_order(
        dispatcher: ContractAddress, escrow: ContractAddress, sway: ContractAddress,
        buyer_crew: Entity, market: Entity, destination: Entity, price: u64, amount: u64
    ) -> (felt252, u64) {
        let (deposit, _) = required_deposit(price * amount, 200, FixedTrait::ONE(), FixedTrait::ONE());
        let (deposit_hook, withdraw_hook) = buy_order_hooks(dispatcher, buyer_crew, market, destination, price, amount);
        IERC20Dispatcher { contract_address: sway }
            .mint(starknet::contract_address_const::<'BUYER'>(), deposit.into());

        starknet::testing::set_contract_address(starknet::contract_address_const::<'BUYER'>());
        let order_id = IEscrowDispatcher { contract_address: escrow }
            .deposit(sway, deposit.into(), withdraw_hook, deposit_hook);
        starknet::testing::set_contract_address(dispatcher);
        return (order_id, deposit);
    }

    fn call_escrow_deposit(
        dispatcher: ContractAddress, escrow: ContractAddress, sway: ContractAddress,
        buyer_crew: Entity, market: Entity, destination: Entity, price: u64, amount: u64
    ) -> Result<Span<felt252>, Array<felt252>> {
        let (deposit, _) = required_deposit(price * amount, 200, FixedTrait::ONE(), FixedTrait::ONE());
        let (deposit_hook, withdraw_hook) = buy_order_hooks(dispatcher, buyer_crew, market, destination, price, amount);
        let deposit: u256 = deposit.into();
        let mut calldata: Array<felt252> = Default::default();
        Serde::<ContractAddress>::serialize(@sway, ref calldata);
        Serde::<u256>::serialize(@deposit, ref calldata);
        Serde::<Hook>::serialize(@withdraw_hook, ref calldata);
        Serde::<Hook>::serialize(@deposit_hook, ref calldata);

        starknet::testing::set_contract_address(starknet::contract_address_const::<'BUYER'>());
        let result = call_contract_syscall(escrow, selector!("deposit"), calldata.span());
        starknet::testing::set_contract_address(dispatcher);
        return result;
    }

    fn withdraw_escrow_order(
        dispatcher: ContractAddress, escrow: ContractAddress, sway: ContractAddress,
        buyer_crew: Entity, market: Entity, destination: Entity, price: u64, amount: u64,
        origin: Entity, origin_slot: u64, caller_crew: Entity, caller: ContractAddress,
        withdrawals: Span<Withdrawal>
    ) {
        let (_, withdraw_hook) = buy_order_hooks(dispatcher, buyer_crew, market, destination, price, amount);
        let mut withdraw_calldata: Array<felt252> = array![amount.into()];
        Serde::<Entity>::serialize(@origin, ref withdraw_calldata);
        withdraw_calldata.append(origin_slot.into());
        Serde::<Entity>::serialize(@caller_crew, ref withdraw_calldata);

        starknet::testing::set_contract_address(caller);
        IEscrowDispatcher { contract_address: escrow }.withdraw(
            starknet::contract_address_const::<'BUYER'>(), sway, withdraw_hook, withdraw_calldata, withdrawals
        );
        starknet::testing::set_contract_address(dispatcher);
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
    #[should_panic(expected: ('E6057: order already exists', ))]
    #[available_gas(100000000)]
    fn test_redeposit_rejects_existing_open_order() {
        let (crew, market, destination) = setup();
        let mut state = CreateBuyOrder::contract_state_for_testing();

        // Depositing for an existing open buy order would pool escrow under the same order
        // id (caller, token, hook) while overwriting the order component, stranding the
        // first deposit; the second placement is rejected instead. Orders cannot be grown
        // or modified after placement: cancel and re-list with different parameters
        place_buy_order(ref state, crew, market, destination, 1000, 200);
        place_buy_order(ref state, crew, market, destination, 500, 200);
    }

    #[test]
    #[should_panic(expected: ('E6057: order already exists', ))]
    #[available_gas(150000000)]
    fn test_partial_fill_rejects_redeposit_at_same_order_key() {
        let (crew, market, destination) = setup();
        set_zero_taker_fee(market);
        let mut create_state = CreateBuyOrder::contract_state_for_testing();
        place_buy_order(ref create_state, crew, market, destination, 1000, 200);

        let (seller_crew, source) = mocks::market_order_seller_fixture(market, 400);
        let mut fill_state = FillBuyOrder::contract_state_for_testing();
        fill_buy_order(ref fill_state, crew, market, destination, 1, 400, seller_crew, source, 200);

        let order_data = components::get::<Order>(order_path_of(crew, market, destination)).unwrap();
        assert(order_data.status == order_statuses::OPEN, 'partial fill closed order');
        assert(order_data.amount == 600, 'partial fill amount wrong');

        place_buy_order(ref create_state, crew, market, destination, 500, 200);
    }

    #[test]
    #[available_gas(150000000)]
    fn test_relist_after_settled_order() {
        let (crew, market, destination) = setup();
        set_zero_taker_fee(market);
        let mut create_state = CreateBuyOrder::contract_state_for_testing();
        place_buy_order(ref create_state, crew, market, destination, 1000, 200);

        let (seller_crew, source) = mocks::market_order_seller_fixture(market, 1000);
        let mut fill_state = FillBuyOrder::contract_state_for_testing();
        fill_buy_order(ref fill_state, crew, market, destination, 1, 1000, seller_crew, source, 200);

        let path = order_path_of(crew, market, destination);
        let filled_order = components::get::<Order>(path).unwrap();
        assert(filled_order.status == order_statuses::FILLED, 'order not filled');
        assert(filled_order.amount == 0, 'filled order amount not zero');

        let delivery = components::get::<Delivery>(EntityTrait::new(entities::DELIVERY, 1).path()).unwrap();
        assert(delivery.status == delivery_statuses::SENT, 'delivery not pending');
        assert(delivery.dest == destination, 'delivery destination wrong');
        assert(reserved_mass_of(destination) == 1000 * 1000, 'delivery reservation lost');

        // A settled order at the same path does not block a fresh listing; only open
        // orders do
        place_buy_order(ref create_state, crew, market, destination, 500, 200);

        let order_data = components::get::<Order>(path).unwrap();
        assert(order_data.status == order_statuses::OPEN, 'wrong status');
        assert(order_data.amount == 500, 'wrong amount');

        // The old delivery and fresh order both retain their reservations
        assert(reserved_mass_of(destination) == 1500 * 1000, 'wrong reserved mass');
    }

    #[test]
    #[available_gas(200000000)]
    fn test_cancel_then_relist_refunds_escrow_and_resets_reservation() {
        let (dispatcher, escrow, sway, crew, market, destination) = mocks::market_order_escrow_fixture(
            CreateBuyOrder::TEST_CLASS_HASH, FillBuyOrder::TEST_CLASS_HASH
        );
        let (order_id, deposit) = deposit_escrow_order(
            dispatcher, escrow, sway, crew, market, destination, 1, 1000
        );

        let refund_withdrawals = array![
            Withdrawal {
                recipient: starknet::contract_address_const::<'BUYER'>(), amount: deposit.into()
            },
            Withdrawal {
                recipient: starknet::contract_address_const::<'MARKET'>(), amount: 0
            }
        ];
        withdraw_escrow_order(
            dispatcher,
            escrow,
            sway,
            crew,
            market,
            destination,
            1,
            0,
            EntityTrait::new(0, 0),
            0,
            crew,
            starknet::contract_address_const::<'BUYER'>(),
            refund_withdrawals.span()
        );

        let token = IERC20Dispatcher { contract_address: sway };
        let escrow_contract = IEscrowDispatcher { contract_address: escrow };
        assert(token.balanceOf(starknet::contract_address_const::<'BUYER'>()) == deposit.into(), 'refund missing');
        assert(token.balanceOf(escrow) == 0, 'escrow tokens uncleared');
        assert(escrow_contract.balance_of(order_id) == 0, 'escrow order uncleared');

        let path = order_path_of(crew, market, destination);
        let cancelled_order = components::get::<Order>(path).unwrap();
        assert(cancelled_order.status == order_statuses::CANCELLED, 'order not cancelled');
        assert(reserved_mass_of(destination) == 0, 'cancel reservation remains');

        let (relisted_order_id, new_deposit) = deposit_escrow_order(
            dispatcher, escrow, sway, crew, market, destination, 1, 500
        );
        let relisted_order = components::get::<Order>(path).unwrap();
        assert(relisted_order_id == order_id, 'escrow order key changed');
        assert(relisted_order.status == order_statuses::OPEN, 'relisted order not open');
        assert(relisted_order.amount == 500, 'relisted amount wrong');
        assert(reserved_mass_of(destination) == 500 * 1000, 'relisted reservation wrong');
        assert(escrow_contract.balance_of(relisted_order_id) == new_deposit.into(), 'relisted escrow balance wrong');
    }

    #[test]
    #[available_gas(200000000)]
    fn test_escrow_duplicate_order_rejection_preserves_state() {
        let (dispatcher, escrow, sway, crew, market, destination) = mocks::market_order_escrow_fixture(
            CreateBuyOrder::TEST_CLASS_HASH, FillBuyOrder::TEST_CLASS_HASH
        );
        let (order_id, _) = deposit_escrow_order(dispatcher, escrow, sway, crew, market, destination, 1, 1000);
        let (duplicate_deposit, _) = required_deposit(500, 200, FixedTrait::ONE(), FixedTrait::ONE());
        let token = IERC20Dispatcher { contract_address: sway };
        token.mint(starknet::contract_address_const::<'BUYER'>(), duplicate_deposit.into());

        let buyer_balance_before = token.balanceOf(starknet::contract_address_const::<'BUYER'>());
        let escrow_token_balance_before = token.balanceOf(escrow);
        let escrow_order_balance_before = IEscrowDispatcher { contract_address: escrow }.balance_of(order_id);
        let order_before = components::get::<Order>(order_path_of(crew, market, destination)).unwrap();
        let reserved_mass_before = reserved_mass_of(destination);
        let reserved_volume_before = reserved_volume_of(destination);
        let exchange_orders_before = components::get::<Exchange>(market.path()).unwrap().orders;

        //TODO: E6057 gets swallowed in the call chain so we can't verify against that without modifying run_system unwrapping.
        let has_expected_error = match call_escrow_deposit(
            dispatcher, escrow, sway, crew, market, destination, 1, 500
        ) {
            Result::Ok(_) => false,
            Result::Err(error) => helpers::error_contains(error, 'ENTRYPOINT_FAILED')
        };
        assert(has_expected_error, 'expected ENTRYPOINT_FAILED');

        let order_after = components::get::<Order>(order_path_of(crew, market, destination)).unwrap();
        assert(token.balanceOf(starknet::contract_address_const::<'BUYER'>()) == buyer_balance_before,
            'buyer balance changed');
        assert(token.balanceOf(escrow) == escrow_token_balance_before, 'escrow token balance changed');
        assert(IEscrowDispatcher { contract_address: escrow }.balance_of(order_id) == escrow_order_balance_before,
            'escrow order balance changed');
        assert(order_after.status == order_before.status, 'original order status changed');
        assert(order_after.amount == order_before.amount, 'original order amount changed');
        assert(order_after.maker_fee == order_before.maker_fee, 'original order fee changed');
        assert(order_after.valid_time == order_before.valid_time, 'valid time changed');
        assert(reserved_mass_of(destination) == reserved_mass_before, 'inventory reservation changed');
        assert(reserved_volume_of(destination) == reserved_volume_before, 'reserved volume changed');
        assert(components::get::<Exchange>(market.path()).unwrap().orders == exchange_orders_before,
            'exchange order count changed');
    }

    #[test]
    #[available_gas(150000000)]
    fn test_distinct_order_keys_allow_buy_orders() {
        let (crew, market, destination) = setup();
        let mut state = CreateBuyOrder::contract_state_for_testing();

        place_buy_order(ref state, crew, market, destination, 1000, 200);
        place_buy_order_at(ref state, crew, market, destination, 2, 500, 200);

        let other_destination = mocks::public_warehouse(crew, 4);
        let (asteroid_id, market_lot) = market.to_position();
        components::set::<Location>(
            other_destination.path(), LocationTrait::new(EntityTrait::from_position(asteroid_id, market_lot))
        );
        place_buy_order_at(ref state, crew, market, other_destination, 1, 300, 200);

        let original = components::get::<Order>(order_path_at(crew, market, destination, 1)).unwrap();
        let different_price = components::get::<Order>(order_path_at(crew, market, destination, 2)).unwrap();
        let different_destination = components::get::<Order>(order_path_at(crew, market, other_destination, 1)).unwrap();
        assert(original.amount == 1000, 'original order changed');
        assert(different_price.amount == 500, 'different-price order missing');
        assert(different_destination.amount == 300, 'destination key missing');
        assert(reserved_mass_of(destination) == 1500 * 1000, 'first reserve wrong');
        assert(reserved_mass_of(other_destination) == 300 * 1000, 'second reserve wrong');
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
