use starknet::ContractAddress;

// Because this system should be called by the Escrow contract as a hook, it also needs to handle the
// cancellation of the order (in case the depositor is trying to withdraw their funds)
#[starknet::contract]
mod FillBuyOrder {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use starknet::contract_address::ContractAddress;
    use traits::{Into, TryInto};

    use cubit::f64::{Fixed, FixedTrait, ONE};

    use influence::{components, config, contracts};
    use influence::common::{crew::CrewDetailsTrait, inventory, position};
    use influence::components::{Building, BuildingTrait, Celestial, Control, Crew, CrewTrait, Exchange, Location,
        LocationTrait, Inventory, Ship, ShipTrait,
        modifier_type::types as modifier_types,
        delivery::{statuses as delivery_statuses, Delivery},
        order::{statuses as order_statuses, types as order_types, Order}};
    use influence::config::{entities, errors, permissions};
    use influence::entities::next_id;
    use influence::interfaces::escrow::Withdrawal;
    use influence::systems::orders::helpers::{required_withdrawals, value_with_maker_fee, order_path};
    use influence::types::{SpanTraitExt, Context, Entity, EntityTrait, InventoryItem, InventoryItemTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct BuyOrderFilled {
        buyer_crew: Entity,
        exchange: Entity,
        product: u64,
        amount: u64,
        price: u64,
        storage: Entity,
        storage_slot: u64,
        origin: Entity,
        origin_slot: u64,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[derive(Copy, Drop, starknet::Event)]
    struct BuyOrderCancelled {
        buyer_crew: Entity,
        exchange: Entity,
        product: u64,
        amount: u64,
        price: u64,
        storage: Entity,
        storage_slot: u64,
        caller_crew: Entity,
        caller: ContractAddress
    }

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
        BuyOrderFilled: BuyOrderFilled,
        BuyOrderCancelled: BuyOrderCancelled,
        DeliverySent: DeliverySent
    }

    #[external(v0)]
    fn run(
        ref self: ContractState,
        buyer_crew: Entity,
        exchange: Entity,
        product: u64,
        price: u64,
        storage: Entity,
        storage_slot: u64,
        amount: u64,
        origin: Entity,
        origin_slot: u64,
        caller_crew: Entity,
        escrow_caller: ContractAddress,
        escrow_type: u64,
        escrow_token: ContractAddress,
        escrow_withdrawals: Span<Withdrawal>,
        mut context: Context
    ) {
        // Check that this call is originating from the escrow contract and extract actual caller
        assert(context.caller == contracts::get('Escrow'), errors::INCORRECT_CALLER);
        context.caller = escrow_caller; // map escrow caller to actual caller

        // Ensure Sway is being withdrawn from escrow
        assert(escrow_type == 2, errors::NOT_ESCROW_WITHDRAW); // 2 = WITHDRAW
        assert(escrow_token.into() == contracts::get('Sway'), errors::INCORRECT_TOKEN);

        // Check that crew is delegated, and ready
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_all_but_ready(context.caller, context.now);
        let mut crew_data = crew_details.component;

        // Get the order data and validate
        let order_path = order_path(
            buyer_crew, exchange, order_types::LIMIT_BUY, product, price, storage, storage_slot
        );

        let mut order_data = components::get::<Order>(order_path).expect(errors::ORDER_NOT_FOUND);
        assert(order_data.status == order_statuses::OPEN, errors::INCORRECT_STATUS);
        assert(order_data.valid_time <= context.now, 'order not available yet');

        // Extract payments from withdrawals
        assert(escrow_withdrawals.len() == 2, errors::INVALID_ESCROW_WITHDRAWAL);
        let to_seller: u256 = *escrow_withdrawals.at(0).amount;
        let to_marketplace: u256 = *escrow_withdrawals.at(1).amount;

        // Cancellation is identified by the actual refund, independent of the supplied fill amount.
        // Including the recipient lets administrators fill zero-fee orders paid to their own wallet.
        let minimum_refund = value_with_maker_fee(order_data.amount * price, order_data.maker_fee);
        let buyer_account = CrewDetailsTrait::new(buyer_crew).component.delegated_to;
        let is_refund = to_seller >= minimum_refund.into() && to_marketplace == 0
            && buyer_account == *escrow_withdrawals.at(0).recipient;
        let can_cancel = buyer_crew == caller_crew || caller_crew.controls(storage) || caller_crew.controls(exchange);

        // If buyer and seller share a wallet, preserve the existing refund-first behavior.
        if can_cancel && is_refund {
            // The buyer, storage controller, or marketplace controller is cancelling the remaining order.
            order_data.status = order_statuses::CANCELLED;
            components::set::<Order>(order_path, order_data);

            let mut exchange_data = components::get::<Exchange>(exchange.path()).expect(errors::EXCHANGE_NOT_FOUND);
            assert(exchange_data.orders > 0, 'invalid order count');
            exchange_data.orders -= 1;
            components::set::<Exchange>(exchange.path(), exchange_data);

            // Remove reservation from destination inventory
            let mut storage_path: Array<felt252> = Default::default();
            storage_path.append(storage.into());
            storage_path.append(storage_slot.into());
            let mut storage_data = components::get::<Inventory>(storage_path.span())
                .expect(errors::INVENTORY_NOT_FOUND);

            let mut products: Array<InventoryItem> = Default::default();
            products.append(InventoryItemTrait::new(product, order_data.amount));
            inventory::unreserve(ref storage_data, products.span());
            components::set::<Inventory>(storage_path.span(), storage_data);

            self.emit(BuyOrderCancelled {
                buyer_crew: buyer_crew,
                exchange: exchange,
                product: product,
                amount: order_data.amount,
                price: price,
                storage: storage,
                storage_slot: storage_slot,
                caller_crew: caller_crew,
                caller: context.caller
            });

            return;
        } else {
            // Make sure the caller crew has permission to fill the order
            caller_crew.assert_can(exchange, permissions::SELL);
        }

        // Check that the exchange is ready
        components::get::<Building>(exchange.path()).expect(errors::BUILDING_NOT_FOUND).assert_operational();
        let mut exchange_data = components::get::<Exchange>(exchange.path()).expect(errors::EXCHANGE_NOT_FOUND);

        // Check that the origin exists and is ready to send
        if origin.label == entities::BUILDING {
            components::get::<Building>(origin.path()).expect(errors::BUILDING_NOT_FOUND).assert_operational();
        } else if origin.label == entities::SHIP {
            components::get::<Ship>(origin.path()).expect(errors::SHIP_NOT_FOUND).assert_stationary();
            let location = components::get::<Location>(origin.path()).expect(errors::LOCATION_NOT_FOUND);

            match components::get::<Building>(location.location.path()) {
                Option::Some(building_data) => building_data.assert_operational(),
                Option::None(_) => ()
            };
        }

        caller_crew.assert_can(origin, permissions::REMOVE_PRODUCTS);

        // Check that the destination exists and is ready to receive
        // - Don't check permission for the destination as it was created by the buy order creator
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

        // Collect crew modifiers
        let market_crew = components::get::<Control>(exchange.path()).expect(errors::CONTROL_NOT_FOUND).controller;
        let mut market_crew_details = CrewDetailsTrait::new(market_crew);
        let mut market_crew_data = market_crew_details.component;

        // Extract fees from withdrawals
        assert(escrow_withdrawals.len() == 2, errors::INVALID_ESCROW_WITHDRAWAL);
        assert(*escrow_withdrawals.at(0).recipient == crew_data.delegated_to, errors::INCORRECT_RECIPIENT);
        assert(*escrow_withdrawals.at(1).recipient == market_crew_data.delegated_to, errors::INCORRECT_RECIPIENT);

        // Validate that calculated payments with those amounts match
        let taker_eff = crew_details.bonus(modifier_types::MARKETPLACE_FEE_REDUCTION, context.now);
        let enforce_eff = market_crew_details.bonus(modifier_types::MARKETPLACE_FEE_ENFORCEMENT, context.now);
        let (computed_to_marketplace, computed_to_seller) = required_withdrawals(
            amount * price, order_data.maker_fee, exchange_data.taker_fee, taker_eff, enforce_eff
        );

        assert(to_marketplace == computed_to_marketplace.into(), errors::INCORRECT_AMOUNT);
        assert(to_seller == computed_to_seller.into(), errors::INCORRECT_AMOUNT);

        // Make sure the buyer actually wants (at least) this much, and reduce the order amount
        assert(order_data.amount >= amount, errors::INSUFFICIENT_AMOUNT);
        order_data.amount -= amount;

        if order_data.amount == 0 {
            order_data.status = order_statuses::FILLED;
            assert(exchange_data.orders > 0, 'invalid order count');
            exchange_data.orders -= 1;
            components::set::<Exchange>(exchange.path(), exchange_data);
        }

        components::set::<Order>(order_path, order_data);

        // Remove products from origin inventory
        let mut origin_path: Array<felt252> = Default::default();
        origin_path.append(origin.into());
        origin_path.append(origin_slot.into());

        let mut origin_data = components::get::<Inventory>(origin_path.span()).expect(errors::INVENTORY_NOT_FOUND);
        let mut products: Array<InventoryItem> = Default::default();

        products.append(InventoryItemTrait::new(product, amount));
        inventory::remove(ref origin_data, products.span());
        components::set::<Inventory>(origin_path.span(), origin_data);

        // Calculate surface transfer time for valid at
        let (origin_ast, origin_lot) = origin.to_position();
        let (dest_ast, dest_lot) = storage.to_position();
        assert(origin_ast == dest_ast, errors::DIFFERENT_ASTEROIDS);
        assert(origin_lot != 0, errors::IN_ORBIT);
        let hopper_eff = crew_details.bonus(modifier_types::HOPPER_TRANSPORT_TIME, context.now);
        let dist_eff = crew_details.bonus(modifier_types::FREE_TRANSPORT_DISTANCE, context.now);
        let ast = components::get::<Celestial>(EntityTrait::new(entities::ASTEROID, origin_ast).path())
            .expect(errors::CELESTIAL_NOT_FOUND);

        let (_exchange_ast, exchange_lot) = exchange.to_position();
        let origin_to_exchange = position::hopper_travel_time(
            origin_lot, exchange_lot, ast.radius, hopper_eff, dist_eff
        );

        let exchange_to_dest = position::hopper_travel_time(exchange_lot, dest_lot, ast.radius, hopper_eff, dist_eff);

        // Create delivery
        // - Don't need to reserve space at destination because it's already reserved by the order
        let delivery = EntityTrait::new(entities::DELIVERY, next_id('Delivery'));
        let finish_time = context.now + origin_to_exchange + exchange_to_dest; // trip via marketplace
        components::set::<Delivery>(delivery.path(), Delivery {
            status: delivery_statuses::SENT,
            origin: exchange,
            origin_slot: 0,
            dest: storage,
            dest_slot: storage_slot,
            finish_time: finish_time,
            contents: products.span()
        });

        // Make sure the crew is on the same asteroid
        assert(crew_details.asteroid_id() == origin_ast, errors::DIFFERENT_ASTEROIDS);
        assert(crew_details.lot_id() != 0, errors::IN_ORBIT);

        self.emit(BuyOrderFilled {
            buyer_crew: buyer_crew,
            exchange: exchange,
            product: product,
            amount: amount,
            price: price,
            storage: storage,
            storage_slot: storage_slot,
            origin: origin,
            origin_slot: origin_slot,
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
            finish_time: finish_time, // trip via marketplace
            caller_crew: caller_crew,
            caller: context.caller
        });
    }
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use traits::{Into, TryInto};
    use result::ResultTrait;
    use starknet::{deploy_syscall, ClassHash};

    use cubit::f64::{Fixed, FixedTrait, ONE, HALF};
    use cubit::f64::test::helpers::assert_relative;

    use influence::{config, components, contracts};
    use influence::common::inventory;
    use influence::components::{Control, ControlTrait, Crew, Exchange, Inventory, InventoryTrait, Location, LocationTrait,
        modifier_type::types as modifier_types,
        product_type::{types as product_types, ProductType},
        crewmate::{classes, departments, crewmate_traits},
        order::{statuses as order_statuses, types as order_types, Order}};
    use influence::config::entities;
    use influence::interfaces::escrow::Withdrawal;
    use influence::systems::orders::helpers::{order_path, required_deposit, required_withdrawals};
    use influence::types::{EntityTrait, InventoryItem, InventoryItemTrait};
    use influence::test::{helpers, mocks};

    use super::FillBuyOrder;

    fn add_modifiers() {
        mocks::modifier_type(modifier_types::INVENTORY_MASS_CAPACITY);
        mocks::modifier_type(modifier_types::INVENTORY_VOLUME_CAPACITY);
        mocks::modifier_type(modifier_types::MARKETPLACE_FEE_ENFORCEMENT);
        mocks::modifier_type(modifier_types::MARKETPLACE_FEE_REDUCTION);
        mocks::modifier_type(modifier_types::HOPPER_TRANSPORT_TIME);
        mocks::modifier_type(modifier_types::FREE_TRANSPORT_DISTANCE);
    }

    fn fill_and_cancel_buy_order(
        price: u64, initial_amount: u64, fill_amounts: Span<u64>, maker_fee: u64, refund_recipient: felt252, canceller: felt252, cancel_amount: u64
    ) {
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        helpers::init();
        mocks::constants();

        // "Deploy" Sway and Escrow
        contracts::set('Sway', starknet::contract_address_const::<'SWAY'>());
        contracts::set('Escrow', starknet::contract_address_const::<'ESCROW'>());

        mocks::product_type(product_types::WATER);
        add_modifiers();

        // Create entities
        let asteroid = influence::test::mocks::asteroid();
        let crew = influence::test::mocks::delegated_crew(1, 'PLAYER');
        let buyer_crew = influence::test::mocks::delegated_crew(2, 'BUYER');
        let market_crew = influence::test::mocks::delegated_crew(3, 'MARKET');

        // Setup station
        let station = influence::test::mocks::public_habitat(market_crew, 1);
        components::set::<Location>(station.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1)));
        components::set::<Location>(crew.path(), LocationTrait::new(station));
        components::set::<Location>(buyer_crew.path(), LocationTrait::new(station));
        components::set::<Location>(market_crew.path(), LocationTrait::new(station));

        // Setup marketplace
        let market = influence::test::mocks::public_marketplace(market_crew, 2);
        components::set::<Location>(market.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 500)));
        components::set::<Control>(market.path(), ControlTrait::new(market_crew));

        // Setup warehouse to market sell from
        let warehouse = influence::test::mocks::public_warehouse(crew, 3);
        components::set::<Location>(warehouse.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1000)));
        components::set::<Control>(warehouse.path(), ControlTrait::new(crew));
        let mut inventory_path = array![warehouse.into(), 2].span();
        let mut inventory_data = components::get::<Inventory>(inventory_path).unwrap();
        let mut supplies = array![InventoryItemTrait::new(product_types::WATER, initial_amount)].span();
        inventory::add_unchecked(ref inventory_data, supplies);
        components::set::<Inventory>(inventory_path, inventory_data);

        // Setup warehouse to receive delivery
        let destination = influence::test::mocks::public_warehouse(buyer_crew, 4);
        components::set::<Location>(destination.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1500)));
        components::set::<Control>(destination.path(), ControlTrait::new(buyer_crew));
        inventory_path = array![destination.into(), 2].span();
        inventory_data = components::get::<Inventory>(inventory_path).unwrap();
        supplies = array![InventoryItemTrait::new(product_types::WATER, initial_amount)].span();
        inventory::reserve(ref inventory_data, supplies, FixedTrait::ONE(), FixedTrait::ONE());
        components::set::<Inventory>(inventory_path, inventory_data);

        // Setup order
        let mut exchange_data = components::get::<Exchange>(market.path()).unwrap();
        exchange_data.orders = 1;
        exchange_data.taker_fee = 0;
        components::set::<Exchange>(market.path(), exchange_data);
        let order_path = order_path(
            buyer_crew, market, order_types::LIMIT_BUY, product_types::WATER, price, destination, 2
        );

        components::set::<Order>(order_path, Order {
            status: order_statuses::OPEN,
            amount: initial_amount,
            valid_time: 0,
            maker_fee: maker_fee
        });

        let (deposit, _) = required_deposit(price * initial_amount, maker_fee, FixedTrait::ONE(), FixedTrait::ONE());
        let mut balance: u256 = deposit.into();
        let mut remaining_amount = initial_amount;
        if canceller == 'market_fill' {
            components::set::<Control>(market.path(), ControlTrait::new(crew));
        }
        if canceller == 'shared_refund' || canceller == 'shared_fill' {
            let mut buyer_data = components::get::<Crew>(buyer_crew.path()).unwrap();
            buyer_data.delegated_to = starknet::contract_address_const::<'PLAYER'>();
            components::set::<Crew>(buyer_crew.path(), buyer_data);
        }
        let market_account = if canceller == 'market_fill' { 'PLAYER' } else { 'MARKET' };
        let mut state = FillBuyOrder::contract_state_for_testing();
        for fill_amount in fill_amounts {
            let (to_market, to_seller) = required_withdrawals(
                price * *fill_amount, maker_fee, 0, FixedTrait::ONE(), FixedTrait::ONE()
            );
            balance -= (to_market + to_seller).into();
            let withdrawals = array![
                Withdrawal { recipient: starknet::contract_address_const::<'PLAYER'>(), amount: to_seller.into() },
                Withdrawal { recipient: market_account.try_into().unwrap(), amount: to_market.into() }
            ];
            FillBuyOrder::run(
                ref state,
                buyer_crew: buyer_crew,
                exchange: market,
                product: product_types::WATER,
                price: price,
                storage: destination,
                storage_slot: 2,
                amount: *fill_amount,
                origin: warehouse,
                origin_slot: 2,
                caller_crew: crew,
                escrow_caller: starknet::contract_address_const::<'PLAYER'>(),
                escrow_type: 2,
                escrow_token: starknet::contract_address_const::<'SWAY'>(),
                escrow_withdrawals: withdrawals.span(),
                context: mocks::context('ESCROW')
            );
            if canceller == 'shared_refund' {
                assert(components::get::<Order>(order_path).unwrap().status == order_statuses::CANCELLED, 'refund must cancel');
                assert(components::get::<Exchange>(market.path()).unwrap().orders == 0, 'wrong order count');
                assert(components::get::<Inventory>(inventory_path).unwrap().reserved_mass == 0, 'reservation not released');
                let source = components::get::<Inventory>(array![warehouse.into(), 2].span()).unwrap();
                assert(source.mass == initial_amount * 1000, 'refund removed goods');
                break;
            }
            remaining_amount -= *fill_amount;
            assert(components::get::<Order>(order_path).unwrap().amount == remaining_amount, 'wrong order amount');
        };

        if canceller == 'shared_refund' { return; }

        if remaining_amount == 0 {
            assert(components::get::<Order>(order_path).unwrap().status == order_statuses::FILLED, 'order not filled');
            assert(components::get::<Exchange>(market.path()).unwrap().orders == 0, 'wrong order count');
            return;
        }

        // Keep the order creator distinct from the current storage or marketplace controller.
        let (caller_crew, caller_account) = if canceller == 'storage' {
            components::set::<Control>(destination.path(), ControlTrait::new(crew));
            (crew, 'PLAYER')
        } else if canceller == 'market' {
            (market_crew, 'MARKET')
        } else if canceller == 'unrelated' {
            (crew, 'PLAYER')
        } else if canceller == 'shared_fill' {
            (buyer_crew, 'PLAYER')
        } else {
            (buyer_crew, 'BUYER')
        };
        let mut caller_data = components::get::<Crew>(caller_crew.path()).unwrap();
        caller_data.ready_at = 999999;
        components::set::<Crew>(caller_crew.path(), caller_data);

        let invalid_refund = refund_recipient.try_into().unwrap()
            != components::get::<Crew>(buyer_crew.path()).unwrap().delegated_to;
        // Invalid refunds must also fail with a real, accessible source inventory.
        let cancellation_origin = if invalid_refund || canceller == 'unrelated' {
            components::set::<Control>(warehouse.path(), ControlTrait::new(caller_crew));
            warehouse
        } else if cancel_amount == 0 {
            EntityTrait::new(0, 0)
        } else {
            destination
        };

        // Cancel remainder of order
        let mut escrow_withdrawals: Array<Withdrawal> = Default::default();
        escrow_withdrawals.append(Withdrawal {
            recipient: refund_recipient.try_into().unwrap(),
            amount: balance
        });

        escrow_withdrawals.append(Withdrawal {
            recipient: starknet::contract_address_const::<'MARKET'>(),
            amount: 0
        });

        FillBuyOrder::run(
            ref state,
            buyer_crew: buyer_crew,
            exchange: market,
            product: product_types::WATER,
            price: price,
            storage: destination,
            storage_slot: 2,
            amount: cancel_amount,
            origin: cancellation_origin,
            origin_slot: if cancellation_origin.is_empty() { 0 } else { 2 },
            caller_crew: caller_crew,
            escrow_caller: caller_account.try_into().unwrap(),
            escrow_type: 2, // WITHDRAW
            escrow_token: starknet::contract_address_const::<'SWAY'>(),
            escrow_withdrawals: escrow_withdrawals.span(),
            context: mocks::context('ESCROW')
        );

        let order_data = components::get::<Order>(order_path).unwrap();
        assert(order_data.status == order_statuses::CANCELLED, 'order not cancelled');
        assert(components::get::<Exchange>(market.path()).unwrap().orders == 0, 'wrong order count');

        // Make sure storage reservation is cleared (not all of it since previous delivery still pending)
        inventory_data = components::get::<Inventory>(inventory_path).unwrap();
        assert(inventory_data.reserved_mass == (initial_amount - remaining_amount) * 1000, 'reserved mass not cleared');
    }

    #[test]
    #[available_gas(70000000)]
    fn test_legacy_positive_amount_buy_cancellation() {
        fill_and_cancel_buy_order(1, 101, array![].span(), 100, 'BUYER', 'buyer', 101);
    }

    #[test]
    #[available_gas(70000000)]
    fn test_legacy_cancellation_ignores_fill_amount_after_partial_fill() {
        fill_and_cancel_buy_order(1, 303, array![101].span(), 100, 'BUYER', 'buyer', 1);
    }

    #[test]
    #[available_gas(70000000)]
    fn test_marketplace_admin_positive_amount_buy_cancellation() {
        fill_and_cancel_buy_order(1, 101, array![].span(), 0, 'BUYER', 'market', 101);
    }

    #[test]
    #[available_gas(70000000)]
    fn test_storage_admin_positive_amount_buy_cancellation() {
        fill_and_cancel_buy_order(1, 101, array![].span(), 0, 'BUYER', 'storage', 101);
    }

    #[test]
    #[available_gas(70000000)]
    fn test_shared_wallet_full_refund_preserves_cancellation_precedence() {
        fill_and_cancel_buy_order(1, 101, array![101].span(), 0, 'PLAYER', 'shared_refund', 0);
    }

    #[test]
    #[available_gas(70000000)]
    fn test_shared_wallet_partial_fill_and_positive_amount_cancellation() {
        fill_and_cancel_buy_order(1, 101, array![50].span(), 0, 'PLAYER', 'shared_fill', 51);
    }

    #[test]
    #[available_gas(70000000)]
    fn test_marketplace_controller_can_partially_fill_zero_fee_buy_order() {
        fill_and_cancel_buy_order(1, 101, array![50].span(), 0, 'BUYER', 'market_fill', 51);
    }

    #[test]
    #[available_gas(70000000)]
    fn test_shared_wallet_full_fill_with_marketplace_fee() {
        fill_and_cancel_buy_order(1, 101, array![101].span(), 100, 'PLAYER', 'shared_fill', 0);
    }

    #[test]
    #[available_gas(70000000)]
    #[should_panic(expected: ('E3007: incorrect amount', ))]
    fn test_positive_amount_admin_cannot_redirect_refund_with_fees() {
        fill_and_cancel_buy_order(1, 101, array![].span(), 100, 'MARKET', 'market', 101);
    }

    #[test]
    #[available_gas(70000000)]
    fn test_marketplace_controller_can_fill_entire_zero_fee_buy_order() {
        fill_and_cancel_buy_order(1, 101, array![101].span(), 0, 'BUYER', 'market_fill', 0);
    }

    #[test]
    #[available_gas(70000000)]
    fn test_storage_controller_cancels_buy_order() {
        fill_and_cancel_buy_order(1, 101, array![].span(), 100, 'BUYER', 'storage', 0);
    }

    #[test]
    #[available_gas(70000000)]
    fn test_marketplace_controller_cancels_buy_order() {
        fill_and_cancel_buy_order(1, 303, array![101].span(), 100, 'BUYER', 'market', 0);
    }

    #[test]
    #[available_gas(70000000)]
    #[should_panic(expected: ('E3007: incorrect amount', ))]
    fn test_marketplace_controller_cannot_take_buy_refund() {
        fill_and_cancel_buy_order(1, 101, array![].span(), 100, 'MARKET', 'market', 0);
    }

    #[test]
    #[available_gas(70000000)]
    #[should_panic(expected: ('E3002: incorrect recipient', ))]
    fn test_unrelated_crew_cannot_cancel_buy_order() {
        fill_and_cancel_buy_order(1, 101, array![].span(), 100, 'BUYER', 'unrelated', 0);
    }

    #[test]
    #[available_gas(70000000)]
    fn test_fill_buy_order() {
        fill_and_cancel_buy_order(10000000, 1000, array![500].span(), 667, 'BUYER', 'buyer', 0);
    }

    #[test]
    #[available_gas(70000000)]
    fn test_cancel_fractional_maker_fee() {
        // Deposit is 102; the previous cancellation calculation required 103.
        fill_and_cancel_buy_order(1, 101, array![].span(), 100, 'BUYER', 'buyer', 0);
    }

    #[test]
    #[available_gas(70000000)]
    fn test_cancel_fractional_maker_fee_after_fill() {
        // Deposit 306 minus a fill of 102 leaves 204, not the previous refund of 205.
        fill_and_cancel_buy_order(1, 303, array![101].span(), 100, 'BUYER', 'buyer', 0);
    }

    #[test]
    #[available_gas(150000000)]
    fn test_cancel_refunds_partial_fill_dust() {
        // Deposit 303 minus three fills of 50 leaves 153. Recalculating the remaining
        // value and fee gives 151 rounded down or 152 rounded up, both leaving dust.
        fill_and_cancel_buy_order(1, 300, array![50, 50, 50].span(), 100, 'BUYER', 'buyer', 0);
    }

    #[test]
    #[should_panic(expected: ('E3002: incorrect recipient', ))]
    #[available_gas(70000000)]
    fn test_cancel_rejects_wrong_refund_recipient() {
        fill_and_cancel_buy_order(1, 101, array![].span(), 100, 'PLAYER', 'buyer', 0);
    }

    #[test]
    #[should_panic(expected: ('E2007: incorrect caller', ))]
    #[available_gas(37000000)]
    fn test_not_escrow_caller() {
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        helpers::init();
        config::set('TIME_ACCELERATION', 24);

        // "Deploy" Sway and Escrow
        contracts::set('Sway', starknet::contract_address_const::<'SWAY'>());
        contracts::set('Escrow', starknet::contract_address_const::<'ESCROW'>());

        mocks::product_type(product_types::WATER);

        // Create entities
        let asteroid = influence::test::mocks::asteroid();
        let crew = influence::test::mocks::delegated_crew(1, 'PLAYER');
        let buyer_crew = influence::test::mocks::delegated_crew(2, 'BUYER');
        let market_crew = influence::test::mocks::delegated_crew(3, 'MARKET');

        // Setup station
        let station = influence::test::mocks::public_habitat(market_crew, 1);
        components::set::<Location>(station.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1)));
        components::set::<Location>(crew.path(), LocationTrait::new(station));
        components::set::<Location>(buyer_crew.path(), LocationTrait::new(station));
        components::set::<Location>(market_crew.path(), LocationTrait::new(station));

        // Setup marketplace
        let market = influence::test::mocks::public_marketplace(market_crew, 2);
        components::set::<Location>(market.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 500)));
        components::set::<Control>(market.path(), ControlTrait::new(market_crew));

        // Setup warehouse to market sell from
        let warehouse = influence::test::mocks::public_warehouse(crew, 3);
        components::set::<Location>(warehouse.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1000)));
        components::set::<Control>(warehouse.path(), ControlTrait::new(crew));
        let mut inventory_path = array![warehouse.into(), 2].span();
        let mut inventory_data = components::get::<Inventory>(inventory_path).unwrap();
        let mut supplies = array![InventoryItemTrait::new(product_types::WATER, 1000)].span();
        inventory::add_unchecked(ref inventory_data, supplies);
        components::set::<Inventory>(inventory_path, inventory_data);

        // Setup warehouse to receive delivery
        let destination = influence::test::mocks::public_warehouse(buyer_crew, 4);
        components::set::<Location>(destination.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1500)));
        components::set::<Control>(destination.path(), ControlTrait::new(buyer_crew));
        inventory_path = array![destination.into(), 2].span();
        inventory_data = components::get::<Inventory>(inventory_path).unwrap();
        supplies = array![InventoryItemTrait::new(product_types::WATER, 1000)].span();
        inventory::reserve(ref inventory_data, supplies, FixedTrait::ONE(), FixedTrait::ONE());
        components::set::<Inventory>(inventory_path, inventory_data);

        // Setup order
        let mut exchange_data = components::get::<Exchange>(market.path()).unwrap();
        exchange_data.orders = 1;
        exchange_data.taker_fee = 0;
        components::set::<Exchange>(market.path(), exchange_data);
        let order_path = order_path(
            buyer_crew, market, order_types::LIMIT_BUY, product_types::WATER, 10000000, destination, 2
        );

        components::set::<Order>(order_path, Order {
            status: order_statuses::OPEN,
            amount: 1000,
            valid_time: 0,
            maker_fee: 667
        });

        // Setup escrow withdrawals
        let mut escrow_withdrawals: Array<Withdrawal> = Default::default();
        escrow_withdrawals.append(Withdrawal {
            recipient: starknet::contract_address_const::<'PLAYER'>(),
            amount: 10000000 * 500
        });

        escrow_withdrawals.append(Withdrawal {
            recipient: starknet::contract_address_const::<'MARKET'>(),
            amount: 333500000
        });

        let mut state = FillBuyOrder::contract_state_for_testing();
        FillBuyOrder::run(
            ref state,
            buyer_crew: buyer_crew,
            exchange: market,
            product: product_types::WATER,
            price: 10000000,
            storage: destination,
            storage_slot: 2,
            amount: 500,
            origin: warehouse,
            origin_slot: 2,
            caller_crew: crew,
            escrow_caller: starknet::contract_address_const::<'PLAYER'>(),
            escrow_type: 2, // WITHDRAW
            escrow_token: starknet::contract_address_const::<'SWAY'>(),
            escrow_withdrawals: escrow_withdrawals.span(),
            context: mocks::context('NOT_ESCROW')
        );
    }

    #[test]
    #[should_panic(expected: ('E3007: incorrect amount', ))]
    #[available_gas(45000000)]
    fn test_incorrect_withdrawals() {
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        helpers::init();
        mocks::constants();

        // "Deploy" Sway and Escrow
        contracts::set('Sway', starknet::contract_address_const::<'SWAY'>());
        contracts::set('Escrow', starknet::contract_address_const::<'ESCROW'>());

        mocks::product_type(product_types::WATER);
        add_modifiers();

        // Create entities
        let asteroid = influence::test::mocks::asteroid();
        let crew = influence::test::mocks::delegated_crew(1, 'PLAYER');
        let buyer_crew = influence::test::mocks::delegated_crew(2, 'BUYER');
        let market_crew = influence::test::mocks::delegated_crew(3, 'MARKET');

        // Setup station
        let station = influence::test::mocks::public_habitat(market_crew, 1);
        components::set::<Location>(station.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1)));
        components::set::<Location>(crew.path(), LocationTrait::new(station));
        components::set::<Location>(buyer_crew.path(), LocationTrait::new(station));
        components::set::<Location>(market_crew.path(), LocationTrait::new(station));

        // Setup marketplace
        let market = influence::test::mocks::public_marketplace(market_crew, 2);
        components::set::<Location>(market.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 500)));
        components::set::<Control>(market.path(), ControlTrait::new(market_crew));

        // Setup warehouse to market sell from
        let warehouse = influence::test::mocks::public_warehouse(crew, 3);
        components::set::<Location>(warehouse.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1000)));
        components::set::<Control>(warehouse.path(), ControlTrait::new(crew));
        let mut inventory_path = array![warehouse.into(), 2].span();
        let mut inventory_data = components::get::<Inventory>(inventory_path).unwrap();
        let mut supplies = array![InventoryItemTrait::new(product_types::WATER, 1000)].span();
        inventory::add_unchecked(ref inventory_data, supplies);
        components::set::<Inventory>(inventory_path, inventory_data);

        // Setup warehouse to receive delivery
        let destination = influence::test::mocks::public_warehouse(buyer_crew, 4);
        components::set::<Location>(destination.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1500)));
        components::set::<Control>(destination.path(), ControlTrait::new(buyer_crew));
        inventory_path = array![destination.into(), 2].span();
        inventory_data = components::get::<Inventory>(inventory_path).unwrap();
        supplies = array![InventoryItemTrait::new(product_types::WATER, 1000)].span();
        inventory::reserve(ref inventory_data, supplies, FixedTrait::ONE(), FixedTrait::ONE());
        components::set::<Inventory>(inventory_path, inventory_data);

        // Setup order
        let mut exchange_data = components::get::<Exchange>(market.path()).unwrap();
        exchange_data.orders = 1;
        exchange_data.taker_fee = 0;
        components::set::<Exchange>(market.path(), exchange_data);
        let order_path = order_path(
            buyer_crew, market, order_types::LIMIT_BUY, product_types::WATER, 10000000, destination, 2
        );

        components::set::<Order>(order_path, Order {
            status: order_statuses::OPEN,
            amount: 1000,
            valid_time: 0,
            maker_fee: 667
        });

        // Setup escrow withdrawals
        let mut escrow_withdrawals: Array<Withdrawal> = Default::default();
        escrow_withdrawals.append(Withdrawal {
            recipient: starknet::contract_address_const::<'PLAYER'>(),
            amount: 10000000 * 510
        });

        escrow_withdrawals.append(Withdrawal {
            recipient: starknet::contract_address_const::<'MARKET'>(),
            amount: 333500000
        });

        let mut state = FillBuyOrder::contract_state_for_testing();
        FillBuyOrder::run(
            ref state,
            buyer_crew: buyer_crew,
            exchange: market,
            product: product_types::WATER,
            price: 10000000,
            storage: destination,
            storage_slot: 2,
            amount: 500,
            origin: warehouse,
            origin_slot: 2,
            caller_crew: crew,
            escrow_caller: starknet::contract_address_const::<'PLAYER'>(),
            escrow_type: 2, // WITHDRAW
            escrow_token: starknet::contract_address_const::<'SWAY'>(),
            escrow_withdrawals: escrow_withdrawals.span(),
            context: mocks::context('ESCROW')
        );
    }

    #[test]
    #[available_gas(70000000)]
    fn test_cancel_hanging_order() {
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        helpers::init();
        mocks::constants();

        // "Deploy" Sway and Escrow
        contracts::set('Sway', starknet::contract_address_const::<'SWAY'>());
        contracts::set('Escrow', starknet::contract_address_const::<'ESCROW'>());

        mocks::product_type(product_types::WATER);
        add_modifiers();

        // Create entities
        let asteroid = influence::test::mocks::asteroid();
        let crew = influence::test::mocks::delegated_crew(1, 'PLAYER');
        let buyer_crew = influence::test::mocks::delegated_crew(2, 'BUYER');
        let market_crew = influence::test::mocks::delegated_crew(3, 'MARKET');

        // Setup station
        let station = influence::test::mocks::public_habitat(market_crew, 1);
        components::set::<Location>(station.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1)));
        components::set::<Location>(crew.path(), LocationTrait::new(station));
        components::set::<Location>(buyer_crew.path(), LocationTrait::new(station));
        components::set::<Location>(market_crew.path(), LocationTrait::new(station));

        // Setup marketplace
        let market = influence::test::mocks::public_marketplace(market_crew, 2);
        components::set::<Location>(market.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 500)));
        components::set::<Control>(market.path(), ControlTrait::new(market_crew));

        // Setup warehouse to market sell from
        let warehouse = influence::test::mocks::public_warehouse(crew, 3);
        components::set::<Location>(warehouse.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1000)));
        components::set::<Control>(warehouse.path(), ControlTrait::new(crew));
        let mut inventory_path = array![warehouse.into(), 2].span();
        let mut inventory_data = components::get::<Inventory>(inventory_path).unwrap();
        let mut supplies = array![InventoryItemTrait::new(product_types::WATER, 1000)].span();
        inventory::add_unchecked(ref inventory_data, supplies);
        components::set::<Inventory>(inventory_path, inventory_data);

        // Setup warehouse to receive delivery
        let destination = influence::test::mocks::public_warehouse(buyer_crew, 4);
        components::set::<Location>(destination.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1500)));
        components::set::<Control>(destination.path(), ControlTrait::new(buyer_crew));
        inventory_path = array![destination.into(), 2].span();
        inventory_data = components::get::<Inventory>(inventory_path).unwrap();
        supplies = array![InventoryItemTrait::new(product_types::WATER, 1000)].span();
        inventory::reserve(ref inventory_data, supplies, FixedTrait::ONE(), FixedTrait::ONE());
        components::set::<Inventory>(inventory_path, inventory_data);

        // Setup order
        let mut exchange_data = components::get::<Exchange>(market.path()).unwrap();
        exchange_data.orders = 1;
        exchange_data.taker_fee = 0;
        components::set::<Exchange>(market.path(), exchange_data);
        let order_path = order_path(
            buyer_crew, market, order_types::LIMIT_BUY, product_types::WATER, 10000000, destination, 2
        );

        components::set::<Order>(order_path, Order {
            status: order_statuses::OPEN,
            amount: 1000,
            valid_time: 0,
            maker_fee: 667
        });

        // Setup escrow withdrawals
        let mut escrow_withdrawals: Array<Withdrawal> = Default::default();
        escrow_withdrawals.append(Withdrawal {
            recipient: starknet::contract_address_const::<'PLAYER'>(),
            amount: 10000000 * 500
        });

        escrow_withdrawals.append(Withdrawal {
            recipient: starknet::contract_address_const::<'MARKET'>(),
            amount: 333500000
        });

        let mut state = FillBuyOrder::contract_state_for_testing();
        FillBuyOrder::run(
            ref state,
            buyer_crew: buyer_crew,
            exchange: market,
            product: product_types::WATER,
            price: 10000000,
            storage: destination,
            storage_slot: 2,
            amount: 500,
            origin: warehouse,
            origin_slot: 2,
            caller_crew: crew,
            escrow_caller: starknet::contract_address_const::<'PLAYER'>(),
            escrow_type: 2, // WITHDRAW
            escrow_token: starknet::contract_address_const::<'SWAY'>(),
            escrow_withdrawals: escrow_withdrawals.span(),
            context: mocks::context('ESCROW')
        );

        // Check order
        let mut order_data = components::get::<Order>(order_path).unwrap();
        assert(order_data.amount == 500, 'wrong order amount');

        // Cancel remainder of order as the controller of the warehouse rather than order placer
        components::set::<Control>(destination.path(), ControlTrait::new(crew));

        escrow_withdrawals = Default::default();
        escrow_withdrawals.append(Withdrawal {
            recipient: starknet::contract_address_const::<'BUYER'>(),
            amount: 5333500000
        });

        escrow_withdrawals.append(Withdrawal {
            recipient: starknet::contract_address_const::<'MARKET'>(),
            amount: 0
        });

        FillBuyOrder::run(
            ref state,
            buyer_crew: buyer_crew,
            exchange: market,
            product: product_types::WATER,
            price: 10000000,
            storage: destination,
            storage_slot: 2,
            amount: 0,
            origin: EntityTrait::new(0, 0),
            origin_slot: 0,
            caller_crew: crew,
            escrow_caller: starknet::contract_address_const::<'PLAYER'>(),
            escrow_type: 2, // WITHDRAW
            escrow_token: starknet::contract_address_const::<'SWAY'>(),
            escrow_withdrawals: escrow_withdrawals.span(),
            context: mocks::context('ESCROW')
        );

        order_data = components::get::<Order>(order_path).unwrap();
        assert(order_data.status == order_statuses::CANCELLED, 'order not cancelled');

        // Make sure storage reservation is cleared (not all of it since previous delivery still pending)
        inventory_data = components::get::<Inventory>(inventory_path).unwrap();
        assert(inventory_data.reserved_mass == 500000, 'reserved mass not cleared');
    }
}
