use array::{ArrayTrait, SpanTrait};
use traits::{Into, TryInto};
use influence::common::missions;
use influence::contracts::dispatcher::Dispatcher;

fn observed(name: felt252, data: Array<felt252>, targets: Span<felt252>) {
    let caller = starknet::get_caller_address();
    starknet::testing::set_account_contract_address(caller);
    let tx = missions::read(array!['ObserverTestTx'].span()) + 1;
    missions::write(array!['ObserverTestTx'].span(), tx);
    starknet::testing::set_transaction_hash(tx);
    let mut dispatcher = Dispatcher::contract_state_for_testing();
    Dispatcher::begin_observation(
        ref dispatcher,
        'MissionObserver',
        name,
        poseidon::poseidon_hash_span(data.span()),
        caller,
        targets
    );
    Dispatcher::run_system(ref dispatcher, name, data);
    Dispatcher::end_observation(ref dispatcher);
}

#[starknet::contract]
mod Policy {
    use array::ArrayTrait;
    use influence::common::missions;
    #[storage]
    struct Storage {}
    #[external(v0)]
    fn before(
        ref self: ContractState, name: felt252, data: Span<felt252>, targets: Span<felt252>
    ) -> Span<felt252> {
        missions::write(
            array!['BeforeCount'].span(), missions::read(array!['BeforeCount'].span()) + 1
        );
        missions::write(array!['PolicyData'].span(), poseidon::poseidon_hash_span(targets));
        array![123].span()
    }
    #[external(v0)]
    fn after(
        ref self: ContractState,
        name: felt252,
        data: Span<felt252>,
        snapshot: Span<felt252>,
        result: Span<felt252>
    ) {
        assert(*snapshot.at(0) == 123, 'lost snapshot');
        missions::write(
            array!['AfterCount'].span(), missions::read(array!['AfterCount'].span()) + 1
        );
    }
}
#[starknet::contract]
mod Action {
    use array::ArrayTrait;
    use influence::common::missions;
    use influence::types::Context;
    #[storage]
    struct Storage {}
    #[external(v0)]
    fn run(ref self: ContractState, value: felt252, context: Context) -> felt252 {
        missions::write(array!['NativeValue'].span(), value);
        value
    }
}
fn setup() -> Dispatcher::ContractState {
    influence::test::helpers::init();
    influence::test::helpers::deploy_system('Policy', Policy::TEST_CLASS_HASH);
    influence::test::helpers::deploy_system('Action', Action::TEST_CLASS_HASH);
    starknet::testing::set_caller_address(starknet::contract_address_const::<'ACCOUNT'>());
    starknet::testing::set_account_contract_address(
        starknet::contract_address_const::<'ACCOUNT'>()
    );
    starknet::testing::set_transaction_hash(1);
    Dispatcher::contract_state_for_testing()
}
fn arm(ref d: Dispatcher::ContractState) {
    Dispatcher::begin_observation(
        ref d,
        'Policy',
        'Action',
        poseidon::poseidon_hash_span(array![42].span()),
        starknet::contract_address_const::<'ACCOUNT'>(),
        array![].span()
    );
}
#[test]
#[available_gas(20000000)]
fn observer_exact_match_runs_once_and_preserves_return() {
    let mut d = setup();
    arm(ref d);
    let result = Dispatcher::run_system(ref d, 'Action', array![42]);
    assert(*result.at(0) == 42, 'native result changed');
    Dispatcher::end_observation(ref d);
    Dispatcher::run_system(ref d, 'Action', array![42]);
    assert(missions::read(array!['BeforeCount'].span()) == 1, 'pre replay');
    assert(missions::read(array!['AfterCount'].span()) == 1, 'post replay');
}
#[test]
#[available_gas(20000000)]
fn observer_ordinary_action_unchanged() {
    let mut d = setup();
    Dispatcher::run_system(ref d, 'Action', array![7]);
    assert(missions::read(array!['NativeValue'].span()) == 7, 'native not executed');
    assert(missions::read(array!['BeforeCount'].span()) == 0, 'ordinary observed');
}
#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('observation not consumed',))]
fn observer_wrong_arguments_cannot_finalize() {
    let mut d = setup();
    arm(ref d);
    Dispatcher::run_system(ref d, 'Action', array![43]);
    Dispatcher::end_observation(ref d);
}
#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('observation not consumed',))]
fn observer_wrong_immediate_caller_cannot_consume() {
    let mut d = setup();
    arm(ref d);
    starknet::testing::set_caller_address(starknet::contract_address_const::<'FORWARDER'>());
    Dispatcher::run_system(ref d, 'Action', array![42]);
    starknet::testing::set_caller_address(starknet::contract_address_const::<'ACCOUNT'>());
    Dispatcher::end_observation(ref d);
}
#[test]
#[available_gas(20000000)]
fn observer_stale_arm_cannot_capture_future_transaction() {
    let mut d = setup();
    arm(ref d);
    starknet::testing::set_transaction_hash(2);
    Dispatcher::run_system(ref d, 'Action', array![42]);
    assert(missions::read(array!['AfterCount'].span()) == 0, 'stale observation captured');
    arm(ref d);
    Dispatcher::run_system(ref d, 'Action', array![42]);
    Dispatcher::end_observation(ref d);
    assert(missions::read(array!['AfterCount'].span()) == 1, 'stale arm blocked fresh arm');
}
#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('only account may arm',))]
fn observer_forwarder_cannot_arm() {
    let mut d = setup();
    starknet::testing::set_caller_address(starknet::contract_address_const::<'FORWARDER'>());
    arm(ref d);
}
#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('already armed',))]
fn observer_cannot_overwrite_pending_arm() {
    let mut d = setup();
    arm(ref d);
    arm(ref d);
}

#[test]
#[available_gas(30000000)]
fn observer_starter_migration_preserves_progress_and_disables_wrapper() {
    let mut d = setup();
    influence::config::set('STARTER_MISSION_CAMPAIGN', 'Starter');
    missions::write(array!['Definition', 'Starter'].span(), 777);
    missions::write(array!['DefinitionCount', 'Starter'].span(), 8);
    missions::write(array!['Lifecycle', 'Starter', 101, 0].span(), 123);
    missions::write(array!['Evidence', 'Starter', 101, 'Pending'].span(), 456);
    influence::systems::set('StarterMissionCampaign', 888.try_into().unwrap());
    influence::systems::set('MissionObserver', 999.try_into().unwrap());
    influence::systems::set('MissionAction', 111.try_into().unwrap());
    let mut migration =
        influence::systems::missions::observer::MigrateStarterObserver::contract_state_for_testing();
    influence::systems::missions::observer::MigrateStarterObserver::run(
        ref migration,
        777.try_into().unwrap(),
        888.try_into().unwrap(),
        influence::test::mocks::context('ADMIN')
    );
    assert(missions::read(array!['Definition', 'Starter'].span()) == 888, 'not replaced');
    assert(
        missions::read(array!['Lifecycle', 'Starter', 101, 0].span()) == 123, 'lifecycle changed'
    );
    assert(
        missions::read(array!['Evidence', 'Starter', 101, 'Pending'].span()) == 456,
        'evidence changed'
    );
    assert(influence::systems::get('MissionAction').into() == 0, 'wrapper still active');
}

#[test]
#[available_gas(20000000)]
fn observer_sequential_groups_are_independent() {
    let mut d = setup();
    arm(ref d);
    Dispatcher::run_system(ref d, 'Action', array![42]);
    Dispatcher::end_observation(ref d);
    arm(ref d);
    Dispatcher::run_system(ref d, 'Action', array![42]);
    Dispatcher::end_observation(ref d);
    assert(missions::read(array!['AfterCount'].span()) == 2, 'second observation lost');
}

#[test]
#[available_gas(20000000)]
fn observer_policy_data_is_bound_to_arm() {
    let mut d = setup();
    Dispatcher::begin_observation(
        ref d,
        'Policy',
        'Action',
        poseidon::poseidon_hash_span(array![42].span()),
        starknet::contract_address_const::<'ACCOUNT'>(),
        array![789, 456].span()
    );
    Dispatcher::run_system(ref d, 'Action', array![42]);
    Dispatcher::end_observation(ref d);
    assert(
        missions::read(
            array!['PolicyData'].span()
        ) == poseidon::poseidon_hash_span(array![789, 456].span()),
        'policy data changed'
    );
    arm(ref d);
    Dispatcher::run_system(ref d, 'Action', array![42]);
    Dispatcher::end_observation(ref d);
    assert(
        missions::read(
            array!['PolicyData'].span()
        ) == poseidon::poseidon_hash_span(array![].span()),
        'stale policy data reused'
    );
}

#[test]
#[available_gas(20000000)]
fn observer_campaign_upgrade_preserves_all_progress() {
    setup();
    missions::write(array!['Definition', 'Colony'].span(), 777);
    missions::write(array!['DefinitionCount', 'Colony'].span(), 5);
    missions::write(array!['Lifecycle', 'Colony', 101, 0].span(), 123);
    missions::write(array!['Evidence', 'Colony', 101, 'ScanStarted'].span(), 456);
    influence::systems::set('ColonizationMissionCampaign', 888.try_into().unwrap());
    let mut upgrade =
        influence::systems::missions::UpgradeMissionCampaign::contract_state_for_testing();
    influence::systems::missions::UpgradeMissionCampaign::run(
        ref upgrade,
        'Colony',
        777.try_into().unwrap(),
        'ColonizationMissionCampaign',
        influence::test::mocks::context('ADMIN')
    );
    assert(missions::read(array!['Definition', 'Colony'].span()) == 888, 'not upgraded');
    assert(missions::read(array!['DefinitionCount', 'Colony'].span()) == 5, 'mission IDs changed');
    assert(
        missions::read(array!['Lifecycle', 'Colony', 101, 0].span()) == 123, 'lifecycle changed'
    );
    assert(
        missions::read(array!['Evidence', 'Colony', 101, 'ScanStarted'].span()) == 456,
        'pending evidence changed'
    );
}
