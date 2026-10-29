// Experimental tests only; not a production mission implementation.
#[starknet::contract]
mod Forwarder {
    use array::ArrayTrait;
    use serde::Serde;
    use starknet::SyscallResultTrait;
    use influence::{systems, types::Context};
    #[storage]
    struct Storage {}
    #[external(v0)]
    fn run(ref self: ContractState, system: felt252, mut args: Array<felt252>, context: Context) -> Span<felt252> {
        Serde::<Context>::serialize(@context, ref args);
        starknet::syscalls::library_call_syscall(systems::get(system), selector!("run"), args.span()).unwrap_syscall()
    }
}

#[starknet::contract]
mod ContextProbe {
    use array::ArrayTrait;
    use traits::Into;
    use influence::types::Context;
    #[storage]
    struct Storage {}
    #[external(v0)]
    fn run(ref self: ContractState, context: Context) -> Span<felt252> {
        array![context.caller.into(), context.now.into(), context.payment_to.into(), context.payment_amount.into(),
            starknet::get_caller_address().into(), starknet::get_contract_address().into()].span()
    }
}

#[starknet::contract]
mod ReceiptConsumer {
    use array::ArrayTrait;
    use starknet::ContractAddress;
    use influence::{contracts, types::Context};
    use influence::contracts::sway::{ISwayDispatcher, ISwayDispatcherTrait};
    #[storage]
    struct Storage {}
    #[external(v0)]
    fn run(ref self: ContractState, recipient: ContractAddress, amount: u128, memo: felt252, context: Context) {
        ISwayDispatcher { contract_address: contracts::get('Sway') }.confirm_receipt(context.caller, recipient, amount, memo);
    }
}

use array::{ArrayTrait, SpanTrait};
use serde::Serde;
use traits::{Into, TryInto};
use option::OptionTrait;
use influence::{components, contracts};
use influence::contracts::dispatcher::Dispatcher;
use influence::contracts::sway::{ISwayDispatcher, ISwayDispatcherTrait};
use influence::test::{helpers, mocks};
use influence::components::{Crew, CrewTrait, Control, ControlTrait, Name};
use influence::types::{Entity, EntityTrait};
use influence::config::entities;
use influence::systems::change_name::ChangeName;

fn setup() {
    starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
    helpers::init();
    helpers::deploy_system('SpikeForwarder', Forwarder::TEST_CLASS_HASH);
    helpers::deploy_system('SpikeProbe', ContextProbe::TEST_CLASS_HASH);
}

fn wrapped(system: felt252, args: Array<felt252>) -> Array<felt252> {
    let mut result = array![system];
    Serde::<Array<felt252>>::serialize(@args, ref result);
    result
}

#[test]
#[available_gas(15000000)]
fn mission_spike_normal_context() {
    setup();
    starknet::testing::set_caller_address(starknet::contract_address_const::<'PLAYER'>());
    starknet::testing::set_block_timestamp(1234);
    let mut state = Dispatcher::contract_state_for_testing();
    let mut raw = Dispatcher::run_system(ref state, 'SpikeForwarder', wrapped('SpikeProbe', array![]));
    let mut child_return = Serde::<Span<felt252>>::deserialize(ref raw).unwrap();
    let values = Serde::<Span<felt252>>::deserialize(ref child_return).unwrap();
    assert(*values.at(0) == 'PLAYER', 'context caller');
    assert(*values.at(1) == 1234, 'context time');
    assert(*values.at(2) == 0 && *values.at(3) == 0, 'unexpected payment');
    assert(*values.at(4) == 'PLAYER', 'syscall caller');
    assert(*values.at(5) == 'DISPATCHER', 'execution address');
}

#[test]
#[available_gas(15000000)]
fn mission_spike_paid_context_authorized_boundary() {
    setup();
    contracts::set('SWAY', starknet::contract_address_const::<'PAYMENT'>());
    starknet::testing::set_caller_address(starknet::contract_address_const::<'PAYMENT'>());
    let mut state = Dispatcher::contract_state_for_testing();
    let mut raw = Dispatcher::run_system_with_payment(ref state, 'SpikeForwarder', wrapped('SpikeProbe', array![]), array!['PLAYER', 'SELLER', 123]);
    let mut child_return = Serde::<Span<felt252>>::deserialize(ref raw).unwrap();
    let values = Serde::<Span<felt252>>::deserialize(ref child_return).unwrap();
    assert(*values.at(0) == 'PLAYER', 'paid sender');
    assert(*values.at(2) == 'SELLER' && *values.at(3) == 123, 'paid details');
    assert(*values.at(4) == 'PAYMENT', 'immediate caller');
    assert(*values.at(5) == 'DISPATCHER', 'paid address');
}

#[test]
#[available_gas(15000000)]
#[should_panic(expected: ('must be called from SWAY',))]
fn mission_spike_paid_context_rejects_account() {
    setup();
    contracts::set('SWAY', starknet::contract_address_const::<'PAYMENT'>());
    starknet::testing::set_caller_address(starknet::contract_address_const::<'PLAYER'>());
    let mut state = Dispatcher::contract_state_for_testing();
    Dispatcher::run_system_with_payment(ref state, 'SpikeForwarder', wrapped('SpikeProbe', array![]), array!['PLAYER', 'SELLER', 123]);
}

#[test]
#[available_gas(20000000)]
fn mission_spike_existing_gameplay_nested_storage() {
    setup();
    helpers::deploy_system('ChangeName', ChangeName::TEST_CLASS_HASH);
    let crew = EntityTrait::new(entities::CREW, 1);
    let asteroid = EntityTrait::new(entities::ASTEROID, 1);
    components::set::<Crew>(crew.path(), CrewTrait::new(starknet::contract_address_const::<'PLAYER'>()));
    components::set::<Control>(asteroid.path(), ControlTrait::new(crew));
    let mut args = array![];
    Serde::<Entity>::serialize(@asteroid, ref args);
    args.append('Mission Spike');
    Serde::<Entity>::serialize(@crew, ref args);
    starknet::testing::set_caller_address(starknet::contract_address_const::<'PLAYER'>());
    let mut state = Dispatcher::contract_state_for_testing();
    Dispatcher::run_system(ref state, 'SpikeForwarder', wrapped('ChangeName', args));
    assert(components::get::<Name>(asteroid.path()).is_some(), 'missing shared state');
}

fn consume_receipt_twice(twice: bool) {
    setup();
    helpers::deploy_system('SpikeReceipt', ReceiptConsumer::TEST_CLASS_HASH);
    let token = ISwayDispatcher { contract_address: helpers::deploy_sway() };
    let player = starknet::contract_address_const::<'PLAYER'>();
    let seller = starknet::contract_address_const::<'SELLER'>();
    let dispatcher = starknet::contract_address_const::<'DISPATCHER'>();
    starknet::testing::set_contract_address(starknet::contract_address_const::<'ADMIN'>());
    token.mint(player, 1000);
    starknet::testing::set_contract_address(player);
    token.transfer_with_confirmation(seller, 123, 'spike_receipt', dispatcher);
    starknet::testing::set_contract_address(dispatcher);
    starknet::testing::set_caller_address(player);
    let mut state = Dispatcher::contract_state_for_testing();
    Dispatcher::run_system(ref state, 'SpikeForwarder', wrapped('SpikeReceipt', array!['SELLER', 123, 'spike_receipt']));
    assert(token.balance_of(seller) == 123, 'seller balance');
    if twice {
        Dispatcher::run_system(ref state, 'SpikeForwarder', wrapped('SpikeReceipt', array!['SELLER', 123, 'spike_receipt']));
    }
}

#[test]
#[available_gas(30000000)]
fn mission_spike_real_sway_receipt() { consume_receipt_twice(false); }

#[test]
#[available_gas(30000000)]
#[should_panic(expected: ('SWAY: invalid receipt', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
fn mission_spike_real_sway_receipt_replay() { consume_receipt_twice(true); }

use cubit::f64::FixedTrait;
use influence::common::inventory;
use influence::components::{Inventory, InventoryTrait, Location, LocationTrait,
    modifier_type::types as modifier_types, process_type::types as process_types,
    product_type::types as product_types,
    deposit::{statuses as deposit_statuses, Deposit},
    extractor::{statuses as extractor_statuses, Extractor},
    processor::{statuses as processor_statuses, Processor}};
use influence::types::{InventoryItemTrait, InventoryContentsTrait};
use influence::systems::production::{ExtractResourceStart, ExtractResourceFinish, ProcessProductsStart, ProcessProductsFinish};

#[test]
#[available_gas(100000000)]
    fn mission_spike_test_extraction_restart() {
        helpers::init();
        mocks::constants();

        let asteroid = influence::test::mocks::asteroid();
        let crew = influence::test::mocks::delegated_crew(1, 'PLAYER');

        // Setup modifiers
        mocks::modifier_type(modifier_types::EXTRACTION_TIME);
        mocks::modifier_type(modifier_types::HOPPER_TRANSPORT_TIME);
        mocks::modifier_type(modifier_types::FREE_TRANSPORT_DISTANCE);
        mocks::modifier_type(modifier_types::INVENTORY_MASS_CAPACITY);
        mocks::modifier_type(modifier_types::INVENTORY_VOLUME_CAPACITY);

        // Setup product configs
        mocks::product_type(product_types::WATER);

        // Setup station
        let station = influence::test::mocks::public_habitat(crew, 1);
        components::set::<Location>(station.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1)));
        components::set::<Location>(crew.path(), LocationTrait::new(station));

        // Setup warehouse
        let warehouse = influence::test::mocks::public_warehouse(crew, 3);
        components::set::<Location>(warehouse.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1000)));

        // Create extractor
        let extractor = influence::test::mocks::public_extractor(crew, 4);
        components::set::<Location>(extractor.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 500)));

        // Create deposit
        let deposit = influence::test::mocks::controlled_deposit(crew, 1, product_types::WATER);
        components::set::<Location>(deposit.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 500)));

        let mut start_state = ExtractResourceStart::contract_state_for_testing();
        ExtractResourceStart::run(
            ref start_state,
            deposit: deposit,
            yield: 500000,
            extractor: extractor,
            extractor_slot: 1,
            destination: warehouse,
            destination_slot: 2,
            caller_crew: crew,
            context: mocks::context('PLAYER')
        ); // 31k

        // Check that the extractor and deposit are updated
        let extractor_path = array![extractor.into(), 1].span();
        let mut extractor_data = components::get::<Extractor>(extractor_path).unwrap();
        assert(extractor_data.status == extractor_statuses::RUNNING, 'extractor status');
        assert(extractor_data.output_product == product_types::WATER, 'extractor output product');
        assert(extractor_data.yield == 500000, 'extractor yield');
        assert(extractor_data.finish_time > 0, 'extractor finish time');

        let original_finish = extractor_data.finish_time;
        let mut deposit_data = components::get::<Deposit>(deposit.path()).unwrap();
        assert(deposit_data.status == deposit_statuses::USED, 'deposit status');
        assert(deposit_data.remaining_yield == 500000, 'deposit remaining yield');

        // Update timings
        starknet::testing::set_block_timestamp(original_finish);

        // Finish the extraction
        let mut finish_state = ExtractResourceFinish::contract_state_for_testing();
        ExtractResourceFinish::run(
            ref finish_state,
            extractor: extractor,
            extractor_slot: 1,
            caller_crew: crew,
            context: mocks::context('PLAYER')
        ); // 11k

        // Check that the extractor is reset
        extractor_data = components::get::<Extractor>(extractor_path).unwrap();
        assert(extractor_data.status == extractor_statuses::IDLE, 'extractor status');
        assert(extractor_data.output_product == 0, 'extractor output product');
        assert(extractor_data.yield == 0, 'extractor yield');

        // Check destination inventory
        let mut destination_path = array![warehouse.into(), 2].span();
        let mut destination_data = components::get::<Inventory>(destination_path).unwrap();
        assert(destination_data.contents.amount_of(product_types::WATER) == 500000, 'destination product');

        let other = mocks::delegated_crew(2, 'OTHER');
        components::set::<Location>(other.path(), LocationTrait::new(station));
        components::set::<Control>(extractor.path(), ControlTrait::new(other));
        components::set::<Control>(deposit.path(), ControlTrait::new(other));
        components::set::<Control>(warehouse.path(), ControlTrait::new(other));
        let mut restart = ExtractResourceStart::contract_state_for_testing();
        ExtractResourceStart::run(ref restart, deposit, 500000, extractor, 1, warehouse, 2, other, mocks::context('OTHER'));
        let replacement = components::get::<Extractor>(extractor_path).unwrap();
        assert(replacement.finish_time > original_finish, 'finish identity reused');
        assert(replacement.yield == 500000, 'different recipe amount');
    }

#[test]
#[available_gas(100000000)]
    fn mission_spike_test_process_products_restart() {
        helpers::init();
        mocks::constants();

        let asteroid = influence::test::mocks::asteroid();
        let crew = influence::test::mocks::delegated_crew(1, 'PLAYER');

        // Setup modifiers
        mocks::modifier_type(modifier_types::SECONDARY_REFINING_YIELD);
        mocks::modifier_type(modifier_types::INVENTORY_MASS_CAPACITY);
        mocks::modifier_type(modifier_types::INVENTORY_VOLUME_CAPACITY);
        mocks::modifier_type(modifier_types::HOPPER_TRANSPORT_TIME);
        mocks::modifier_type(modifier_types::FREE_TRANSPORT_DISTANCE);
        mocks::modifier_type(modifier_types::REFINING_TIME);
        mocks::modifier_type(modifier_types::MANUFACTURING_TIME);

        // Setup product configs
        mocks::product_type(product_types::HYDROGEN);
        mocks::product_type(product_types::AMMONIA);
        mocks::product_type(product_types::PURE_NITROGEN);

        // Setup station
        let station = influence::test::mocks::public_habitat(crew, 1);
        components::set::<Location>(station.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1)));
        components::set::<Location>(crew.path(), LocationTrait::new(station));

        // Setup refinery
        let refinery = influence::test::mocks::public_refinery(crew, 2);
        components::set::<Location>(refinery.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 500)));

        // Setup warehouse
        let warehouse = influence::test::mocks::public_warehouse(crew, 3);
        components::set::<Location>(warehouse.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1000)));
        let inventory_path = array![warehouse.into(), 2].span();
        let mut inventory_data = components::get::<Inventory>(inventory_path).unwrap();
        let supplies = array![InventoryItemTrait::new(product_types::AMMONIA, 50000)].span();

        inventory::add_unchecked(ref inventory_data, supplies);
        components::set::<Inventory>(inventory_path, inventory_data);
        mocks::process_type(process_types::AMMONIA_CATALYTIC_CRACKING);

        let mut state = ProcessProductsStart::contract_state_for_testing();
        ProcessProductsStart::run(
            ref state,
            processor: refinery,
            processor_slot: 1,
            process: process_types::AMMONIA_CATALYTIC_CRACKING,
            target_output: product_types::HYDROGEN,
            recipes: FixedTrait::new_unscaled(1000, false),
            origin: warehouse,
            origin_slot: 2,
            destination: warehouse,
            destination_slot: 2,
            caller_crew: crew,
            context: mocks::context('PLAYER')
        ); // 67.6k steps

        // Check inventory
        inventory_data = components::get::<Inventory>(inventory_path).unwrap();
        assert((*inventory_data.contents.at(0)).product == product_types::AMMONIA, 'incorrect product');
        assert((*inventory_data.contents.at(0)).amount == 10000, 'incorrect amount');

        // Check processor
        let processor_path = array![refinery.into(), 1].span();
        let mut processor_data = components::get::<Processor>(processor_path).unwrap();
        assert(processor_data.status == processor_statuses::RUNNING, 'incorrect status');
        assert(processor_data.running_process == process_types::AMMONIA_CATALYTIC_CRACKING, 'incorrect process');
        assert(processor_data.output_product == product_types::HYDROGEN, 'incorrect output');
        let original_finish = processor_data.finish_time;
        let finish_time = original_finish;

        // Finish processing
        starknet::testing::set_block_timestamp(finish_time);
        let mut state = ProcessProductsFinish::contract_state_for_testing();
        ProcessProductsFinish::run(
            ref state,
            processor: refinery,
            processor_slot: 1,
            caller_crew: crew,
            context: mocks::context('PLAYER')
        ); // 28.7k steps

        // Check inventory
        inventory_data = components::get::<Inventory>(inventory_path).unwrap();
        assert(inventory_data.amount_of(product_types::HYDROGEN) == 6000, 'incorrect amount');
        assert(inventory_data.amount_of(product_types::PURE_NITROGEN) == 8500, 'incorrect amount');
        assert(inventory_data.reserved_mass == 0, 'incorrect amount');
        assert(inventory_data.reserved_volume == 0, 'incorrect amount');

        processor_data = components::get::<Processor>(processor_path).unwrap();
        assert(processor_data.status == processor_statuses::IDLE, 'incorrect status');

        let mut inv = components::get::<Inventory>(inventory_path).unwrap();
        inventory::add_unchecked(ref inv, array![InventoryItemTrait::new(product_types::AMMONIA, 40000)].span());
        components::set::<Inventory>(inventory_path, inv);
        let other = mocks::delegated_crew(2, 'OTHER');
        components::set::<Location>(other.path(), LocationTrait::new(station));
        components::set::<Control>(refinery.path(), ControlTrait::new(other));
        components::set::<Control>(warehouse.path(), ControlTrait::new(other));
        let mut restart = ProcessProductsStart::contract_state_for_testing();
        ProcessProductsStart::run(ref restart, refinery, 1, process_types::AMMONIA_CATALYTIC_CRACKING,
            product_types::HYDROGEN, FixedTrait::new_unscaled(1000, false), warehouse, 2, warehouse, 2, other, mocks::context('OTHER'));
        let replacement = components::get::<Processor>(processor_path).unwrap();
        assert(replacement.finish_time > original_finish, 'process finish reused');
        assert(replacement.running_process == process_types::AMMONIA_CATALYTIC_CRACKING, 'different recipe');
    }

#[test]
#[available_gas(100000000)]
    fn mission_spike_zero_yield_can_repeat_finish_time() {
        helpers::init();
        mocks::constants();

        let asteroid = influence::test::mocks::asteroid();
        let crew = influence::test::mocks::delegated_crew(1, 'PLAYER');

        // Setup modifiers
        mocks::modifier_type(modifier_types::EXTRACTION_TIME);
        mocks::modifier_type(modifier_types::HOPPER_TRANSPORT_TIME);
        mocks::modifier_type(modifier_types::FREE_TRANSPORT_DISTANCE);
        mocks::modifier_type(modifier_types::INVENTORY_MASS_CAPACITY);
        mocks::modifier_type(modifier_types::INVENTORY_VOLUME_CAPACITY);

        // Setup product configs
        mocks::product_type(product_types::WATER);

        // Setup station
        let station = influence::test::mocks::public_habitat(crew, 1);
        components::set::<Location>(station.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1)));
        components::set::<Location>(crew.path(), LocationTrait::new(station));

        // Setup warehouse
        let warehouse = influence::test::mocks::public_warehouse(crew, 3);
        components::set::<Location>(warehouse.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1)));

        // Create extractor
        let extractor = influence::test::mocks::public_extractor(crew, 4);
        components::set::<Location>(extractor.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1)));

        // Create deposit
        let deposit = influence::test::mocks::controlled_deposit(crew, 1, product_types::WATER);
        components::set::<Location>(deposit.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1)));


        let mut start = ExtractResourceStart::contract_state_for_testing();
        let mut finish = ExtractResourceFinish::contract_state_for_testing();
        ExtractResourceStart::run(ref start, deposit, 0, extractor, 1, warehouse, 2, crew, mocks::context('PLAYER'));
        let path = array![extractor.into(), 1].span();
        let first = components::get::<Extractor>(path).unwrap();
        assert(first.finish_time == starknet::get_block_timestamp(), 'not zero duration');
        ExtractResourceFinish::run(ref finish, extractor, 1, crew, mocks::context('PLAYER'));
        ExtractResourceStart::run(ref start, deposit, 0, extractor, 1, warehouse, 2, crew, mocks::context('PLAYER'));
        let second = components::get::<Extractor>(path).unwrap();
        let mut encoded_first = array![];
        let mut encoded_second = array![];
        Serde::<Extractor>::serialize(@first, ref encoded_first);
        Serde::<Extractor>::serialize(@second, ref encoded_second);
        assert(encoded_first == encoded_second, 'snapshot did not repeat');
    }

use influence::components::order::{statuses as order_statuses, types as order_types, Order};
use influence::systems::orders::helpers::order_path;
use influence::systems::orders::fill_sell::FillSellOrder;
use influence::types::SpanHashTrait;
#[test]
#[available_gas(100000000)]
    fn mission_spike_actual_market_fill() {
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        setup();
        helpers::deploy_system('FillSellOrder', FillSellOrder::TEST_CLASS_HASH);
        mocks::constants();

        // Add modifiers
        mocks::modifier_type(modifier_types::INVENTORY_MASS_CAPACITY);
        mocks::modifier_type(modifier_types::INVENTORY_VOLUME_CAPACITY);
        mocks::modifier_type(modifier_types::MARKETPLACE_FEE_ENFORCEMENT);
        mocks::modifier_type(modifier_types::MARKETPLACE_FEE_REDUCTION);
        mocks::modifier_type(modifier_types::HOPPER_TRANSPORT_TIME);
        mocks::modifier_type(modifier_types::FREE_TRANSPORT_DISTANCE);

        // Deploy SWAY
        let sway_address = helpers::deploy_sway();
        let amount: u256 = (100 * 1000000).into();
        starknet::testing::set_contract_address(starknet::contract_address_const::<'ADMIN'>());
        ISwayDispatcher { contract_address: sway_address }.mint(starknet::contract_address_const::<'PLAYER'>(), amount);
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());

        // Setup product
        mocks::product_type(product_types::WATER);

        // Create entities
        let asteroid = influence::test::mocks::asteroid();
        let crew = influence::test::mocks::delegated_crew(1, 'PLAYER');
        let seller_crew = influence::test::mocks::delegated_crew(2, 'SELLER');
        let market_crew = influence::test::mocks::delegated_crew(3, 'MARKET');

        // Setup station
        let station = influence::test::mocks::public_habitat(market_crew, 1);
        components::set::<Location>(station.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1)));
        components::set::<Location>(crew.path(), LocationTrait::new(station));
        components::set::<Location>(seller_crew.path(), LocationTrait::new(station));
        components::set::<Location>(market_crew.path(), LocationTrait::new(station));

        // Setup marketplace
        let market = influence::test::mocks::public_marketplace(market_crew, 2);
        components::set::<Location>(market.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 500)));
        components::set::<Control>(market.path(), ControlTrait::new(market_crew));

        // Setup warehouse
        let warehouse = influence::test::mocks::public_warehouse(crew, 3);
        components::set::<Location>(warehouse.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1000)));
        components::set::<Control>(warehouse.path(), ControlTrait::new(crew));
        let inventory_path = array![warehouse.into(), 2].span();
        let mut inventory_data = components::get::<Inventory>(inventory_path).unwrap();
        let supplies = array![InventoryItemTrait::new(product_types::WATER, 1000)].span();
        inventory::reserve(ref inventory_data, supplies, FixedTrait::ONE(), FixedTrait::ONE());
        components::set::<Inventory>(inventory_path, inventory_data);

        // Setup order
        let order_path = order_path(
            seller_crew, market, order_types::LIMIT_SELL, product_types::WATER, 100000, warehouse, 2
        );

        components::set::<Order>(order_path, Order {
            status: order_statuses::OPEN,
            amount: 1000,
            valid_time: 0,
            maker_fee: 100
        });

        components::set::<Control>(order_path, ControlTrait::new(seller_crew));

        // Send payments
        starknet::testing::set_contract_address(starknet::contract_address_const::<'PLAYER'>());
        ISwayDispatcher { contract_address: sway_address }.transfer_with_confirmation(
            starknet::contract_address_const::<'SELLER'>(),
            49500000,
            order_path.hash(),
            starknet::contract_address_const::<'DISPATCHER'>()
        );

        ISwayDispatcher { contract_address: sway_address }.transfer_with_confirmation(
            starknet::contract_address_const::<'MARKET'>(),
            1335000,
            order_path.hash(),
            starknet::contract_address_const::<'DISPATCHER'>()
        );

        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        starknet::testing::set_caller_address(starknet::contract_address_const::<'PLAYER'>());
        let mut args = array![];
        Serde::<Entity>::serialize(@seller_crew, ref args);
        Serde::<Entity>::serialize(@market, ref args);
        args.append(product_types::WATER.into());
        args.append(500);
        args.append(100000);
        Serde::<Entity>::serialize(@warehouse, ref args);
        args.append(2);
        Serde::<Entity>::serialize(@warehouse, ref args);
        args.append(2);
        Serde::<Entity>::serialize(@crew, ref args);
        let mut state = Dispatcher::contract_state_for_testing();
        Dispatcher::run_system(ref state, 'SpikeForwarder', wrapped('FillSellOrder', args));

        // Check order
        let order_data = components::get::<Order>(order_path).unwrap();
        assert(order_data.amount == 500, 'wrong order amount');
    }
