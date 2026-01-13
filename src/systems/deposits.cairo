mod abundance;
mod list_for_sale;
mod purchase;
mod sample_start;
mod sample_improve;
mod sample_finish;
mod unlist_for_sale;

use abundance::Abundance;
use list_for_sale::ListDepositForSale;
use purchase::PurchaseDeposit;
use sample_start::SampleDepositStart;
use sample_improve::SampleDepositImprove;
use sample_finish::SampleDepositFinish;
use unlist_for_sale::UnlistDepositForSale;

mod helpers {
    use array::{ArrayTrait, SpanTrait};
    use traits::{Into, TryInto};

    use influence::types::{ArrayHashTrait, Entity, EntityTrait};

    fn deposit_commit_hash(deposit: Entity, initial_yield: u64) -> felt252 {
        let mut to_hash: Array<felt252> = Default::default();
        to_hash.append('CoreSampling');
        to_hash.append(deposit.into());
        to_hash.append(initial_yield.into());
        return to_hash.hash();
    }
}

// Tests --------------------------------------------------------------------------------------------------------------

use influence::types::{Context, Entity};

#[starknet::interface]
trait IPurchaseDeposit<TContractState> {
    fn run(ref self: TContractState, deposit: Entity, caller_crew: Entity, context: Context);
}

#[cfg(test)]
mod tests {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use traits::{Into, TryInto};
    use starknet::ClassHash;

    use influence::{components, config};
    use influence::common::{inventory, random};
    use influence::components::{Control, ControlTrait, Crew, CrewTrait, Inventory, InventoryTrait, Location,
        LocationTrait, PrivateSale, PrivateSaleTrait,
        celestial::{statuses as celestial_statuses, Celestial, CelestialTrait},
        modifier_type::types as modifier_types,
        product_type::{types as product_types, ProductType},
        crewmate::{classes, crewmate_traits},
        deposit::{statuses as deposit_statuses, Deposit, DepositTrait}};
    use influence::config::entities;
    use influence::contracts::sway::{ISwayDispatcher, ISwayDispatcherTrait};
    use influence::types::{Entity, EntityTrait, InventoryItem, InventoryItemTrait, InventoryContentsTrait};
    use influence::test::{helpers, mocks};

    use super::{SampleDepositStart, SampleDepositImprove, SampleDepositFinish, ListDepositForSale,
        UnlistDepositForSale, PurchaseDeposit, IPurchaseDepositLibraryDispatcher, IPurchaseDepositDispatcherTrait};

    #[test]
    #[available_gas(120000000)]
    fn test_deposit_sampling() {
        helpers::init();
        mocks::constants();

        let asteroid = influence::test::mocks::adalia_prime();
        let crew = influence::test::mocks::delegated_crew(1, 'PLAYER');

        // Add modifier configs
        mocks::modifier_type(modifier_types::CORE_SAMPLE_TIME);
        mocks::modifier_type(modifier_types::CORE_SAMPLE_QUALITY);
        mocks::modifier_type(modifier_types::INVENTORY_MASS_CAPACITY);
        mocks::modifier_type(modifier_types::INVENTORY_VOLUME_CAPACITY);
        mocks::modifier_type(modifier_types::HOPPER_TRANSPORT_TIME);
        mocks::modifier_type(modifier_types::FREE_TRANSPORT_DISTANCE);

        // Setup products
        mocks::product_type(product_types::CORE_DRILL);
        mocks::product_type(product_types::CARBON_MONOXIDE);

        // Setup station
        let station = influence::test::mocks::public_habitat(crew, 1);
        components::set::<Location>(station.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1758637)));
        components::set::<Location>(crew.path(), LocationTrait::new(station));

        // Setup warehouse
        let warehouse = influence::test::mocks::public_warehouse(crew, 3);
        components::set::<Location>(warehouse.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1758404)));
        let inventory_path = array![warehouse.into(), 2].span();
        let mut inventory_data = components::get::<Inventory>(inventory_path).unwrap();
        let supplies = array![InventoryItemTrait::new(product_types::CORE_DRILL, 2)].span();
        inventory::add_unchecked(ref inventory_data, supplies);
        components::set::<Inventory>(inventory_path, inventory_data);

        // Set scanning info on asteroid
        let mut celestial_data = components::get::<Celestial>(asteroid.path()).unwrap();
        celestial_data.scan_status = celestial_statuses::RESOURCE_SCANNED;
        celestial_data.abundances = 163694267033613831154047584829516;
        components::set::<Celestial>(asteroid.path(), celestial_data);

        let mut start_state = SampleDepositStart::contract_state_for_testing();
        SampleDepositStart::run(
            ref start_state,
            lot: EntityTrait::from_position(asteroid.id, 1758637),
            resource: product_types::CARBON_MONOXIDE,
            origin: warehouse,
            origin_slot: 2,
            caller_crew: crew,
            context: mocks::context('PLAYER')
        );

        // Check deposit
        let mut deposit_data = components::get::<Deposit>(EntityTrait::new(entities::DEPOSIT, 1).path()).unwrap();
        assert(deposit_data.status == deposit_statuses::SAMPLING, 'incorrect status');
        assert(deposit_data.resource == product_types::CARBON_MONOXIDE, 'incorrect resource');

        // Check inventory
        let mut inventory_data = components::get::<Inventory>(inventory_path).unwrap();
        assert(inventory_data.amount_of(product_types::CORE_DRILL) == 1, 'core sampler not removed');

        // Update timing and round
        starknet::testing::set_block_timestamp(12000);
        random::entropy::generate();

        // Clear out potential random event
        let mut crew_data = components::get::<Crew>(crew.path()).unwrap();
        crew_data.action_type = 0;
        components::set::<Crew>(crew.path(), crew_data);

        // Finish sampling
        let mut finish_state = SampleDepositFinish::contract_state_for_testing();
        SampleDepositFinish::run(
            ref finish_state,
            deposit: EntityTrait::new(entities::DEPOSIT, 1),
            caller_crew: crew,
            context: mocks::context('PLAYER')
        );

        // Check deposit
        deposit_data = components::get::<Deposit>(EntityTrait::new(entities::DEPOSIT, 1).path()).unwrap();
        assert(deposit_data.status == deposit_statuses::SAMPLED, 'incorrect status');
        let intermediate_yield = deposit_data.initial_yield;
        assert(deposit_data.initial_yield > 0, 'incorrect yield');

        // Improve deposit
        let mut improve_state = SampleDepositImprove::contract_state_for_testing();
        SampleDepositImprove::run(
            ref improve_state,
            deposit: EntityTrait::new(entities::DEPOSIT, 1),
            origin: warehouse,
            origin_slot: 2,
            caller_crew: crew,
            context: mocks::context('PLAYER')
        );

        deposit_data = components::get::<Deposit>(EntityTrait::new(entities::DEPOSIT, 1).path()).unwrap();
        assert(deposit_data.status == deposit_statuses::SAMPLING, 'incorrect status');

        // Check inventory
        inventory_data = components::get::<Inventory>(inventory_path).unwrap();
        assert(inventory_data.amount_of(product_types::CORE_DRILL) == 0, 'core sampler not removed');

        // Update timing and round
        starknet::testing::set_block_timestamp(24000);
        random::entropy::generate();

        // Finish sampling
        SampleDepositFinish::run(
            ref finish_state,
            deposit: EntityTrait::new(entities::DEPOSIT, 1),
            caller_crew: crew,
            context: mocks::context('PLAYER')
        );

        // Check deposit
        deposit_data = components::get::<Deposit>(EntityTrait::new(entities::DEPOSIT, 1).path()).unwrap();
        assert(deposit_data.status == deposit_statuses::SAMPLED, 'incorrect status');
        assert(deposit_data.initial_yield > intermediate_yield, 'incorrect yield');
    }

    #[test]
    #[available_gas(10000000)]
    fn test_create_remove() {
        let asteroid = mocks::asteroid();
        let crew = mocks::delegated_crew(1, 'PLAYER');
        let deposit = mocks::controlled_deposit(crew, 1, 1);
        components::set::<Location>(crew.path(), LocationTrait::new(asteroid));
        components::set::<Location>(deposit.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1)));

        let mut state = ListDepositForSale::contract_state_for_testing();
        ListDepositForSale::run(ref state, deposit, 1000, crew, mocks::context('PLAYER'));

        let sale = components::get::<PrivateSale>(deposit.path()).unwrap();
        assert(sale.amount == 1000, 'wrong amount');

        let mut state = UnlistDepositForSale::contract_state_for_testing();
        UnlistDepositForSale::run(ref state, deposit, crew, mocks::context('PLAYER'));
        assert(components::get::<PrivateSale>(deposit.path()).is_none(), 'sale not removed');
    }

    #[test]
    #[available_gas(15000000)]
    fn test_purchase() {
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        helpers::init();
        config::set('TIME_ACCELERATION', 24);

        // Deploy SWAY
        let sway_address = helpers::deploy_sway();
        let amount: u256 = (100 * 1000000).into();
        starknet::testing::set_contract_address(starknet::contract_address_const::<'ADMIN'>());
        ISwayDispatcher { contract_address: sway_address }.mint(starknet::contract_address_const::<'PLAYER'>(), amount);
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());

        // Create entities
        let asteroid = mocks::asteroid();
        let crew = mocks::delegated_crew(1, 'PLAYER');
        let seller_crew = mocks::delegated_crew(2, 'SELLER');
        let deposit = mocks::controlled_deposit(seller_crew, 1, 1);
        components::set::<Location>(crew.path(), LocationTrait::new(asteroid));
        components::set::<Location>(seller_crew.path(), LocationTrait::new(asteroid));
        components::set::<Location>(deposit.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1)));

        // Create sale
        let mut state = ListDepositForSale::contract_state_for_testing();
        ListDepositForSale::run(ref state, deposit, 1000, seller_crew, mocks::context('SELLER'));

        // Send payments
        starknet::testing::set_contract_address(starknet::contract_address_const::<'PLAYER'>());
        ISwayDispatcher { contract_address: sway_address }.transfer_with_confirmation(
            starknet::contract_address_const::<'SELLER'>(),
            1000,
            deposit.into(),
            starknet::contract_address_const::<'DISPATCHER'>()
        );

        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        let class_hash: ClassHash = PurchaseDeposit::TEST_CLASS_HASH.try_into().unwrap();
        IPurchaseDepositLibraryDispatcher { class_hash: class_hash }.run(
            deposit: deposit,
            caller_crew: crew,
            context: mocks::context('PLAYER')
        );

        // Confirm sale
        let control_data = components::get::<Control>(deposit.path()).unwrap();
        assert(control_data.controller == crew, 'wrong crew');
        assert(components::get::<PrivateSale>(deposit.path()).is_none(), 'sale not removed');
    }
}
