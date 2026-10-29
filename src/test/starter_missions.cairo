use influence::components::process_type::types as processes;
use influence::components::building_type::types as buildings;
use influence::contracts::crewmate::ICrewmateDispatcherTrait;
use array::{ArrayTrait, SpanTrait};
use serde::Serde;
use traits::{Into, TryInto};
use option::OptionTrait;
use cubit::f64::{Fixed, FixedTrait};
use influence::{components, config};
use influence::common::{missions, mission_eligibility as eligibility, inventory, random};
use influence::common::missions::Assignment;
use influence::components::{
    Crew, CrewTrait, Control, ControlTrait, Location, LocationTrait, Building, BuildingTypeTrait,
    ProcessTypeTrait, Inventory, InventoryTrait, Extractor, Processor, Deposit, Delivery, Celestial,
    ProductTypeTrait
};
use influence::components::modifier_type::types as modifiers;
use influence::components::inventory_type::types as inventories;
use influence::types::{
    Entity, EntityTrait, InventoryItem, InventoryItemTrait, InventoryContentsTrait
};
use influence::config::entities;
use influence::contracts::dispatcher::Dispatcher;
use influence::contracts::sway::{ISwayDispatcher, ISwayDispatcherTrait};
use influence::systems::missions::{
    AcceptMission, MissionValidate, ClaimMissionReward, RegisterMissionCampaign
};
use influence::systems::missions::starter::{StarterMissionCampaign, ConfigureStarterMissions};
use influence::systems::construction::{ConstructionPlan, ConstructionStart, ConstructionFinish};
use influence::systems::production::{
    ExtractResourceStart, ExtractResourceFinish, ProcessProductsStart, ProcessProductsFinish
};
use influence::systems::deposits::{SampleDepositStart, SampleDepositFinish};
use influence::systems::deliveries::{SendDelivery, ReceiveDelivery};
use influence::test::{helpers, mocks, mission_fixtures};

fn encode<T, impl S: Serde<T>, impl D: Drop<T>>(value: @T) -> Array<felt252> {
    let mut args = array![];
    Serde::<T>::serialize(value, ref args);
    args
}

fn dispatch<T, impl S: Serde<T>, impl D: Drop<T>>(name: felt252, value: @T) {
    let mut dispatcher = Dispatcher::contract_state_for_testing();
    Dispatcher::run_system(ref dispatcher, name, encode(value));
}

fn act<T, impl S: Serde<T>, impl D: Drop<T>>(a: Assignment, name: felt252, value: @T) {
    observe(a, name, encode(value).span());
}

fn accept(a: Assignment, step: u32) {
    dispatch('AcceptMission', @Assignment { mission: step, ..a });
}

fn ready(crew: Entity) {
    let mut data = components::get::<Crew>(crew.path()).unwrap();
    let now = starknet::get_block_timestamp();
    if data.ready_at > now {
        starknet::testing::set_block_timestamp(data.ready_at);
    }
    // Random-event resolution is exercised separately by gameplay tests.
    data.action_type = 0;
    components::set::<Crew>(crew.path(), data);
}

fn setup() -> (Assignment, Entity) {
    starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
    starknet::testing::set_block_timestamp(100);
    helpers::init();
    mocks::constants();
    mission_fixtures::configs();
    helpers::deploy_system('AcceptMission', AcceptMission::TEST_CLASS_HASH);
    helpers::deploy_system(
        'MissionObserver', influence::systems::missions::observer::MissionObserver::TEST_CLASS_HASH
    );
    helpers::deploy_system('MissionValidate', MissionValidate::TEST_CLASS_HASH);
    helpers::deploy_system('ClaimMissionReward', ClaimMissionReward::TEST_CLASS_HASH);
    helpers::deploy_system('ConstructionPlan', ConstructionPlan::TEST_CLASS_HASH);
    helpers::deploy_system('ConstructionStart', ConstructionStart::TEST_CLASS_HASH);
    helpers::deploy_system('ConstructionFinish', ConstructionFinish::TEST_CLASS_HASH);
    helpers::deploy_system('ExtractResourceStart', ExtractResourceStart::TEST_CLASS_HASH);
    helpers::deploy_system('ExtractResourceFinish', ExtractResourceFinish::TEST_CLASS_HASH);
    helpers::deploy_system('ProcessProductsStart', ProcessProductsStart::TEST_CLASS_HASH);
    helpers::deploy_system('ProcessProductsFinish', ProcessProductsFinish::TEST_CLASS_HASH);
    helpers::deploy_system('SampleDepositStart', SampleDepositStart::TEST_CLASS_HASH);
    helpers::deploy_system('SampleDepositFinish', SampleDepositFinish::TEST_CLASS_HASH);
    helpers::deploy_system('SendDelivery', SendDelivery::TEST_CLASS_HASH);
    helpers::deploy_system('ReceiveDelivery', ReceiveDelivery::TEST_CLASS_HASH);
    helpers::deploy_system('StarterTemplateFixture', StarterMissionCampaign::TEST_CLASS_HASH);
    let mut registry = RegisterMissionCampaign::contract_state_for_testing();
    RegisterMissionCampaign::run(
        ref registry,
        'Starter',
        StarterMissionCampaign::TEST_CLASS_HASH.try_into().unwrap(),
        8,
        mocks::context('ADMIN')
    );
    let mut configure = ConfigureStarterMissions::contract_state_for_testing();
    ConfigureStarterMissions::run(ref configure, 'Starter', 100, mocks::context('ADMIN'));
    let crew = mocks::delegated_crew(101, 'PLAYER');
    let asteroid = mocks::adalia_prime();
    components::set::<Control>(asteroid.path(), ControlTrait::new(crew));
    let station = mocks::public_habitat(crew, 10001);
    components::set::<
        Location
    >(station.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1758637)));
    components::set::<Location>(crew.path(), LocationTrait::new(station));
    let mut celestial = components::get::<Celestial>(asteroid.path()).unwrap();
    celestial.scan_status = influence::components::celestial::statuses::RESOURCE_SCANNED;
    celestial.abundances = 163694267033613831154047584829516;
    components::set::<Celestial>(asteroid.path(), celestial);
    let mut types = array![
        modifiers::CORE_SAMPLE_TIME,
        modifiers::CORE_SAMPLE_QUALITY,
        modifiers::INVENTORY_MASS_CAPACITY,
        modifiers::INVENTORY_VOLUME_CAPACITY,
        modifiers::HOPPER_TRANSPORT_TIME,
        modifiers::FREE_TRANSPORT_DISTANCE,
        modifiers::CONSTRUCTION_TIME,
        modifiers::EXTRACTION_TIME,
        modifiers::SECONDARY_REFINING_YIELD,
        modifiers::REFINING_TIME,
        modifiers::MANUFACTURING_TIME,
        modifiers::REACTION_TIME
    ]
        .span();
    loop {
        match types.pop_front() {
            Option::Some(t) => { mocks::modifier_type(*t); },
            Option::None(_) => { break; }
        }
    };
    mocks::inventory_type(inventories::WAREHOUSE_PRIMARY);
    mocks::product_type(influence::components::product_type::types::CORE_DRILL);
    starknet::testing::set_caller_address(starknet::contract_address_const::<'PLAYER'>());
    (Assignment { campaign: 'Starter', subject: crew, mission: 0 }, asteroid)
}

fn supply(building: Entity, slot: u64, items: Span<InventoryItem>) {
    let path = array![building.into(), slot.into()].span();
    let mut inv = components::get::<Inventory>(path).unwrap();
    inventory::add_unchecked(ref inv, items);
    components::set::<Inventory>(path, inv);
}

fn construct(a: Assignment, asteroid: Entity, kind: u64) -> Entity {
    ready(a.subject);
    let lot = EntityTrait::from_position(asteroid.id, 1758636 + kind);
    act(a, 'ConstructionPlan', @(kind, lot));
    let building = EntityTrait::new(
        entities::BUILDING, influence::entities::current_id(entities::BUILDING.into())
    );
    let cfg = BuildingTypeTrait::by_type(kind);
    supply(building, cfg.site_slot, ProcessTypeTrait::by_type(cfg.process_type).inputs);
    ready(a.subject);
    act(a, 'ConstructionStart', @building);
    let data = components::get::<Building>(building.path()).unwrap();
    starknet::testing::set_block_timestamp(data.finish_time);
    act(a, 'ConstructionFinish', @building);
    building
}

fn sample(a: Assignment, asteroid: Entity, warehouse: Entity) -> Entity {
    ready(a.subject);
    let lot = EntityTrait::from_position(asteroid.id, 1758637);
    supply(
        warehouse,
        2,
        array![InventoryItemTrait::new(influence::components::product_type::types::CORE_DRILL, 1)]
            .span()
    );
    act(a, 'SampleDepositStart', @(lot, product_types::CARBON_MONOXIDE, warehouse, 2_u64));
    let deposit = EntityTrait::new(
        entities::DEPOSIT, influence::entities::current_id(entities::DEPOSIT.into())
    );
    starknet::testing::set_block_timestamp(starknet::get_block_timestamp() + 20000);
    random::entropy::generate();
    ready(a.subject);
    act(a, 'SampleDepositFinish', @deposit);
    deposit
}

fn process(a: Assignment, building: Entity, warehouse: Entity, id: u64) -> u64 {
    ready(a.subject);
    let cfg = ProcessTypeTrait::by_type(id);
    supply(warehouse, 2, cfg.inputs);
    let output = *cfg.outputs.at(0);
    act(
        a,
        'ProcessProductsStart',
        @(
            building,
            1_u64,
            id,
            output.product,
            FixedTrait::ONE(),
            warehouse,
            2_u64,
            warehouse,
            2_u64
        )
    );
    let processor = components::get::<Processor>(array![building.into(), 1].span()).unwrap();
    starknet::testing::set_block_timestamp(processor.finish_time);
    act(a, 'ProcessProductsFinish', @(building, 1_u64));
    output.product
}

fn landfall() -> (Assignment, Entity, Entity) {
    let (a, asteroid) = setup();
    accept(a, 0);
    assert(!eligibility::participated(a.subject), 'acceptance contaminated');
    let warehouse = construct(a, asteroid, buildings::WAREHOUSE);
    assert(missions::flag(a, 1), 'landfall incomplete');
    assert(eligibility::participated(a.subject), 'participation missing');
    (a, asteroid, warehouse)
}

#[test]
#[available_gas(2000000000)]
fn starter_missions_full_progression() {
    let (a, asteroid, warehouse) = landfall();
    assert(!missions::flag(Assignment { mission: 3, ..a }, 1), 'construction credited storage');
    let mut n = 0;
    let mut deposit = EntityTrait::new(0, 0);
    loop {
        if n == 3 {
            break;
        }
        deposit = sample(a, asteroid, warehouse);
        assert(
            components::get::<Deposit>(deposit.path()).unwrap().initial_yield >= 500000,
            'fixture sample below threshold'
        );
        n += 1;
    };
    assert(!missions::flag(Assignment { mission: 1, ..a }, 1), 'unaccepted mission complete');
    accept(a, 1);
    assert(missions::flag(Assignment { mission: 1, ..a }, 1), 'early samples lost');
    let extractor = construct(a, asteroid, buildings::EXTRACTOR);
    // Extraction fixture at the deposit lot; real permission/location checks still run.
    components::set::<
        Location
    >(extractor.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1758637)));
    ready(a.subject);
    act(a, 'ExtractResourceStart', @(deposit, 100000_u64, extractor, 1_u64, warehouse, 2_u64));
    assert(!missions::flag(Assignment { mission: 2, ..a }, 1), 'start credited extraction');
    let data = components::get::<Extractor>(array![extractor.into(), 1].span()).unwrap();
    starknet::testing::set_block_timestamp(data.finish_time);
    act(a, 'ExtractResourceFinish', @(extractor, 1_u64));
    accept(a, 2);
    accept(a, 3);
    assert(missions::flag(Assignment { mission: 3, ..a }, 1), 'storage not complete');
    let refinery = construct(a, asteroid, buildings::REFINERY);
    let bio = construct(a, asteroid, buildings::BIOREACTOR);
    let factory = construct(a, asteroid, buildings::FACTORY);
    process(a, refinery, warehouse, processes::WATER_VACUUM_EVAPORATION_DESALINATION);
    accept(a, 4);
    process(a, bio, warehouse, processes::SOYBEAN_GROWING);
    accept(a, 5);
    process(a, factory, warehouse, processes::QUARTZ_FILAMENT_DRAWING_AND_WRAPPING);
    accept(a, 6);
    accept(a, 7);
    let product = process(a, refinery, warehouse, processes::WATER_ELECTROLYSIS);
    assert(!missions::flag(Assignment { mission: 7, ..a }, 1), 'stockholding credited capstone');
    let other_store = mocks::public_warehouse(a.subject, 20001);
    components::set::<
        Location
    >(other_store.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1758638)));
    ready(a.subject);
    act(
        a,
        'SendDelivery',
        @(warehouse, 2_u64, array![InventoryItemTrait::new(product, 1)].span(), other_store, 2_u64)
    );
    assert(!missions::flag(Assignment { mission: 7, ..a }, 1), 'inflight delivery credited');
    let delivery = EntityTrait::new(
        entities::DELIVERY, influence::entities::current_id('Delivery')
    );
    starknet::testing::set_block_timestamp(
        components::get::<Delivery>(delivery.path()).unwrap().finish_time
    );
    act(a, 'ReceiveDelivery', @delivery);
    assert(missions::flag(Assignment { mission: 7, ..a }, 1), 'capstone incomplete');
    let token = ISwayDispatcher { contract_address: helpers::deploy_sway() };
    starknet::testing::set_contract_address(starknet::contract_address_const::<'ADMIN'>());
    token.mint(starknet::contract_address_const::<'DISPATCHER'>(), 225000000000);
    starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
    // Entitlements survive invalidation and pay the current delegate.
    eligibility::invalidate(a.subject);
    let mut crew = components::get::<Crew>(a.subject.path()).unwrap();
    crew.delegated_to = starknet::contract_address_const::<'NEW_DELEGATE'>();
    components::set::<Crew>(a.subject.path(), crew);
    let mut step = 0;
    loop {
        if step == 8 {
            break;
        }
        dispatch('ClaimMissionReward', @Assignment { mission: step, ..a });
        if step == 3 {
            assert(token.balance_of(crew.delegated_to) == 75000000000, 'Explorer total');
        }
        if step == 4 {
            assert(token.balance_of(crew.delegated_to) == 125000000000, 'Strategist total');
        }
        step += 1;
    };
    assert(token.balance_of(crew.delegated_to) == 225000000000, 'Industrialist total');
    assert(
        token.balance_of(starknet::contract_address_const::<'PLAYER'>()) == 0,
        'paid former delegate'
    );
}

#[test]
#[available_gas(300000000)]
fn starter_missions_lifecycle_packing_and_namespaces() {
    let (a, _) = setup();
    let b = Assignment { campaign: 'OtherCampaign', ..a };
    let other = Assignment { subject: EntityTrait::new(entities::ASTEROID, a.subject.id), ..a };
    let mut index = 0;
    loop {
        if index == 70 {
            break;
        }
        let step = Assignment { mission: index, ..a };
        missions::set_flag(step, 0);
        missions::set_flag(step, 0);
        if index % 2 == 0 {
            missions::set_flag(step, 1);
        }
        if index % 3 == 0 {
            missions::set_flag(step, 2);
        }
        index += 1;
    };
    index = 0;
    loop {
        if index == 70 {
            break;
        }
        let step = Assignment { mission: index, ..a };
        assert(missions::flag(step, 0), 'acceptance bit lost');
        assert(missions::flag(step, 1) == (index % 2 == 0), 'completion bit collision');
        assert(missions::flag(step, 2) == (index % 3 == 0), 'payout bit collision');
        assert(!missions::flag(Assignment { mission: index, ..b }, 0), 'campaign collision');
        assert(!missions::flag(Assignment { mission: index, ..other }, 0), 'subject collision');
        index += 1;
    };
    missions::set_state(a, 42, 123);
    assert(
        missions::state(Assignment { mission: 7, ..a }, 42) == 123, 'evidence not campaign shared'
    );
    assert(
        missions::state(b, 42) == 0 && missions::state(other, 42) == 0,
        'evidence namespace collision'
    );
}

#[test]
#[available_gas(100000000)]
fn starter_missions_contamination_model() {
    let (a, _) = setup();
    let b = mocks::delegated_crew(102, 'PLAYER');
    let c = mocks::delegated_crew(103, 'PLAYER');
    accept(a, 0);
    eligibility::exchange(
        a.subject, array![101].span(), array![102].span(), b, array![102].span(), array![101].span()
    );
    assert(
        !eligibility::invalid(a.subject) && !eligibility::invalid(b), 'unused exchange contaminated'
    );
    eligibility::participate(a.subject);
    eligibility::exchange(
        a.subject,
        array![101, 104].span(),
        array![104, 101].span(),
        b,
        array![102].span(),
        array![102].span()
    );
    assert(!eligibility::invalid(a.subject), 'reorder contaminated');
    eligibility::exchange(
        a.subject,
        array![101, 104].span(),
        array![104].span(),
        b,
        array![102].span(),
        array![102, 101].span()
    );
    assert(
        eligibility::invalid(a.subject) && eligibility::invalid(b), 'participation not contagious'
    );
    eligibility::exchange(
        b,
        array![102, 101].span(),
        array![101].span(),
        c,
        array![103].span(),
        array![103, 102].span()
    );
    assert(eligibility::invalid(c), 'onward contamination missing');
}

#[test]
#[available_gas(100000000)]
fn starter_missions_ordinary_exchange_invalidates() {
    let (a, _) = setup();
    let b = mocks::delegated_crew(102, 'PLAYER');
    components::set::<Location>(b.path(), components::get::<Location>(a.subject.path()).unwrap());
    let token = influence::contracts::crewmate::ICrewmateDispatcher {
        contract_address: helpers::deploy_crewmate()
    };
    starknet::testing::set_contract_address(starknet::contract_address_const::<'ADMIN'>());
    token.add_grant(starknet::contract_address_const::<'ADMIN'>(), 2);
    token.mint_with_id(starknet::contract_address_const::<'PLAYER'>(), 101);
    token.mint_with_id(starknet::contract_address_const::<'PLAYER'>(), 102);
    starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
    eligibility::participate(a.subject);
    let mut exchange =
        influence::systems::crew::exchange_crew::ExchangeCrew::contract_state_for_testing();
    influence::systems::crew::exchange_crew::ExchangeCrew::run(
        ref exchange, a.subject, array![102].span(), b, array![101].span(), mocks::context('PLAYER')
    );
    assert(eligibility::invalid(a.subject) && eligibility::invalid(b), 'ordinary path bypass');
}

#[test]
#[available_gas(100000000)]
fn starter_missions_legacy_crew_contaminates_new_crew() {
    let (a, _) = setup();
    let legacy = EntityTrait::new(entities::CREW, 100);
    eligibility::exchange(
        legacy,
        array![1].span(),
        array![101].span(),
        a.subject,
        array![101].span(),
        array![1].span()
    );
    assert(eligibility::invalid(a.subject), 'legacy recycling allowed');
}

#[test]
#[available_gas(100000000)]
#[should_panic]
fn starter_missions_cutoff_rejected() {
    let (a, _) = setup();
    let old = mocks::delegated_crew(100, 'PLAYER');
    accept(Assignment { subject: old, ..a }, 0);
}

#[test]
#[available_gas(100000000)]
#[should_panic]
fn starter_missions_unauthorized_acceptance() {
    let (a, _) = setup();
    starknet::testing::set_caller_address(starknet::contract_address_const::<'OTHER'>());
    accept(a, 0);
}

#[test]
#[available_gas(100000000)]
#[should_panic]
fn starter_missions_prerequisite_required() {
    let (a, _) = setup();
    accept(a, 1);
}

#[test]
#[available_gas(100000000)]
#[should_panic]
fn starter_missions_reacceptance_rejected() {
    let (a, _) = setup();
    accept(a, 0);
    accept(a, 0);
}

#[test]
#[available_gas(100000000)]
#[should_panic(expected: ('campaign not accepted', 'ENTRYPOINT_FAILED'))]
fn starter_missions_unaccepted_action_not_credited() {
    let (a, ast) = setup();
    act(
        a, 'ConstructionPlan', @(buildings::WAREHOUSE, EntityTrait::from_position(ast.id, 1758637))
    );
    assert(!missions::flag(a, 1) && missions::state(a, 0) == 0, 'unaccepted action credited');
}

#[test]
#[available_gas(100000000)]
#[should_panic(expected: ('definition immutable',))]
fn starter_missions_definition_immutable() {
    let (a, _) = setup();
    let mut registry = RegisterMissionCampaign::contract_state_for_testing();
    RegisterMissionCampaign::run(
        ref registry,
        a.campaign,
        StarterMissionCampaign::TEST_CLASS_HASH.try_into().unwrap(),
        8,
        mocks::context('ADMIN')
    );
}

#[test]
#[available_gas(150000000)]
#[should_panic]
fn starter_missions_invalidated_progress_rejected() {
    let (a, _, _) = landfall();
    eligibility::invalidate(a.subject);
    accept(a, 1);
}

#[test]
#[available_gas(100000000)]
#[should_panic]
fn starter_missions_incomplete_claim_rejected() {
    let (a, _) = setup();
    accept(a, 0);
    dispatch('ClaimMissionReward', @a);
}

#[test]
#[available_gas(150000000)]
#[should_panic]
fn starter_missions_duplicate_reward_rejected() {
    let (a, _, _) = landfall();
    let token = ISwayDispatcher { contract_address: helpers::deploy_sway() };
    starknet::testing::set_contract_address(starknet::contract_address_const::<'ADMIN'>());
    token.mint(starknet::contract_address_const::<'DISPATCHER'>(), 10000000000);
    starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
    dispatch('ClaimMissionReward', @a);
    assert(
        token.balance_of(starknet::contract_address_const::<'PLAYER'>()) == 5000000000,
        'first reward missing'
    );
    dispatch('ClaimMissionReward', @a);
}

fn route(first: u64, second: u64, kind1: u64, kind2: u64, reverse: bool) {
    let (a, ast, warehouse) = landfall();
    let building1 = construct(a, ast, kind1);
    let building2 = if kind1 == kind2 {
        building1
    } else {
        construct(a, ast, kind2)
    };
    if reverse {
        process(a, building2, warehouse, second);
        process(a, building1, warehouse, first);
    } else {
        process(a, building1, warehouse, first);
        process(a, building2, warehouse, second);
    }
    let cfg = ProcessTypeTrait::by_type(second);
    let product = *cfg.outputs.at(0);
    let other = mocks::public_warehouse(a.subject, 20001);
    components::set::<
        Location
    >(other.path(), LocationTrait::new(EntityTrait::from_position(ast.id, 1758638)));
    ready(a.subject);
    act(
        a,
        'SendDelivery',
        @(
            warehouse,
            2_u64,
            array![InventoryItemTrait::new(product.product, 1)].span(),
            other,
            2_u64
        )
    );
    let delivery = EntityTrait::new(
        entities::DELIVERY, influence::entities::current_id('Delivery')
    );
    starknet::testing::set_block_timestamp(
        components::get::<Delivery>(delivery.path()).unwrap().finish_time
    );
    // Permissionless native completion can be reconciled from immutable delivery state.
    let mut receive = ReceiveDelivery::contract_state_for_testing();
    ReceiveDelivery::run(ref receive, delivery, a.subject, mocks::context('PLAYER'));
    dispatch('MissionValidate', @(a, encode(@delivery).span()));
    let earned: u128 = missions::state(a, 0).try_into().unwrap();
    assert((earned / 128 % 2 == 1) == !reverse, 'route ordering incorrect');
}

#[test]
#[available_gas(750000000)]
fn starter_missions_water_route() {
    route(
        processes::WATER_VACUUM_EVAPORATION_DESALINATION,
        processes::WATER_ELECTROLYSIS,
        buildings::REFINERY,
        buildings::REFINERY,
        false
    );
}

#[test]
#[available_gas(750000000)]
fn starter_missions_cement_route() {
    route(
        processes::CALCITE_CALCINATION,
        processes::SALTY_CEMENT_MIXING,
        buildings::REFINERY,
        buildings::REFINERY,
        false
    );
}

#[test]
#[available_gas(750000000)]
fn starter_missions_naphtha_route() {
    route(
        processes::BITUMEN_HYDRO_CRACKING,
        processes::NAPHTHA_STEAM_CRACKING,
        buildings::REFINERY,
        buildings::REFINERY,
        false
    );
}

#[test]
#[available_gas(750000000)]
fn starter_missions_quartz_route() {
    route(
        processes::SILICA_FUSING,
        processes::QUARTZ_FILAMENT_DRAWING_AND_WRAPPING,
        buildings::FACTORY,
        buildings::FACTORY,
        false
    );
}

#[test]
#[available_gas(750000000)]
fn starter_missions_food_route() {
    route(
        processes::SOYBEAN_GROWING,
        processes::BASIC_FOOD_COOKING_AND_PACKAGING,
        buildings::BIOREACTOR,
        buildings::FACTORY,
        false
    );
}

#[test]
#[available_gas(750000000)]
fn starter_missions_reverse_route_not_credited() {
    route(
        processes::WATER_VACUUM_EVAPORATION_DESALINATION,
        processes::WATER_ELECTROLYSIS,
        buildings::REFINERY,
        buildings::REFINERY,
        true
    );
}

#[test]
#[available_gas(150000000)]
#[should_panic]
fn starter_missions_fractional_biological_batch_rejected() {
    let (a, ast, warehouse) = landfall();
    let bio = construct(a, ast, buildings::BIOREACTOR);
    ready(a.subject);
    let cfg = ProcessTypeTrait::by_type(processes::SOYBEAN_GROWING);
    supply(warehouse, 2, cfg.inputs);
    act(
        a,
        'ProcessProductsStart',
        @(
            bio,
            1_u64,
            processes::SOYBEAN_GROWING,
            product_types::SOYBEANS,
            FixedTrait::new(2147483648, false),
            warehouse,
            2_u64,
            warehouse,
            2_u64
        )
    );
}

#[test]
#[available_gas(150000000)]
#[should_panic]
fn starter_missions_unconstructed_building_rejected() {
    let (a, ast, warehouse) = landfall();
    let refinery = mocks::public_refinery(a.subject, 20001);
    components::set::<
        Location
    >(refinery.path(), LocationTrait::new(EntityTrait::from_position(ast.id, 1758637)));
    process(a, refinery, warehouse, processes::WATER_VACUUM_EVAPORATION_DESALINATION);
}

#[test]
#[available_gas(200000000)]
#[should_panic]
fn starter_missions_duplicate_sample_rejected() {
    let (a, ast, warehouse) = landfall();
    let deposit = sample(a, ast, warehouse);
    act(a, 'SampleDepositFinish', @deposit);
}

#[test]
#[available_gas(200000000)]
#[should_panic]
fn starter_missions_duplicate_process_rejected() {
    let (a, ast, warehouse) = landfall();
    let refinery = construct(a, ast, buildings::REFINERY);
    process(a, refinery, warehouse, processes::WATER_VACUUM_EVAPORATION_DESALINATION);
    act(a, 'ProcessProductsFinish', @(refinery, 1_u64));
}

#[test]
#[available_gas(100000000)]
fn starter_missions_each_sample_must_meet_threshold() {
    let (a, _) = setup();
    influence::systems::missions::starter::record_sample(a, 499999);
    influence::systems::missions::starter::record_sample(a, 500000);
    influence::systems::missions::starter::record_sample(a, 500000);
    assert(!influence::systems::missions::starter::earned(a, 1), 'small sample counted');
    influence::systems::missions::starter::record_sample(a, 500000);
    assert(influence::systems::missions::starter::earned(a, 1), 'inclusive threshold failed');
    let state = missions::state(a, 0);
    influence::systems::missions::starter::record_sample(a, 999999);
    assert(missions::state(a, 0) == state, 'counter did not saturate');
}

#[test]
#[available_gas(150000000)]
fn starter_missions_storage_requires_actual_mass() {
    let (a, _, warehouse) = landfall();
    let path = array![warehouse.into(), 2].span();
    let mut inv = components::get::<Inventory>(path).unwrap();
    let goods = array![InventoryItemTrait::new(product_types::WATER, 100000)].span();
    inventory::reserve(ref inv, goods, FixedTrait::ONE(), FixedTrait::ONE());
    components::set::<Inventory>(path, inv);
    influence::systems::missions::starter::storage_received(a, warehouse, 2);
    assert(!influence::systems::missions::starter::earned(a, 3), 'reservation counted');
    inventory::unreserve(ref inv, goods);
    inventory::add_unchecked(
        ref inv, array![InventoryItemTrait::new(product_types::WATER, 99999)].span()
    );
    components::set::<Inventory>(path, inv);
    influence::systems::missions::starter::storage_received(a, warehouse, 2);
    assert(!influence::systems::missions::starter::earned(a, 3), 'below threshold counted');
    inventory::add_unchecked(
        ref inv, array![InventoryItemTrait::new(product_types::CARBON_MONOXIDE, 1)].span()
    );
    components::set::<Inventory>(path, inv);
    influence::systems::missions::starter::storage_received(a, warehouse, 2);
    assert(influence::systems::missions::starter::earned(a, 3), 'mixed exact mass not counted');
}

#[test]
#[available_gas(200000000)]
#[should_panic(expected: ('extraction below threshold',))]
fn starter_missions_extraction_threshold_enforced() {
    let (a, ast, warehouse) = landfall();
    let extractor = construct(a, ast, buildings::EXTRACTOR);
    let deposit = mocks::controlled_deposit(a.subject, 1, product_types::WATER);
    let args = encode(@(deposit, 99999_u64, extractor, 1_u64, warehouse, 2_u64));
    influence::systems::missions::starter::pre(
        a, 'ExtractResourceStart', args.span(), mocks::context('PLAYER')
    );
}

#[test]
#[available_gas(300000000)]
#[should_panic(expected: ('unbound process',))]
fn starter_missions_unwrapped_restart_cannot_reuse_evidence() {
    let (a, ast, warehouse) = landfall();
    let refinery = construct(a, ast, buildings::REFINERY);
    ready(a.subject);
    let cfg = ProcessTypeTrait::by_type(processes::WATER_VACUUM_EVAPORATION_DESALINATION);
    supply(warehouse, 2, cfg.inputs);
    act(
        a,
        'ProcessProductsStart',
        @(
            refinery,
            1_u64,
            processes::WATER_VACUUM_EVAPORATION_DESALINATION,
            product_types::DEIONIZED_WATER,
            FixedTrait::ONE(),
            warehouse,
            2_u64,
            warehouse,
            2_u64
        )
    );
    let old = components::get::<Processor>(array![refinery.into(), 1].span()).unwrap();
    starknet::testing::set_block_timestamp(old.finish_time);
    let mut finish = ProcessProductsFinish::contract_state_for_testing();
    ProcessProductsFinish::run(ref finish, refinery, 1, a.subject, mocks::context('PLAYER'));
    ready(a.subject);
    supply(warehouse, 2, cfg.inputs);
    let mut start = ProcessProductsStart::contract_state_for_testing();
    ProcessProductsStart::run(
        ref start,
        refinery,
        1,
        processes::WATER_VACUUM_EVAPORATION_DESALINATION,
        product_types::DEIONIZED_WATER,
        FixedTrait::ONE(),
        warehouse,
        2,
        warehouse,
        2,
        a.subject,
        mocks::context('PLAYER')
    );
    let current = components::get::<Processor>(array![refinery.into(), 1].span()).unwrap();
    assert(current.finish_time > old.finish_time, 'run identity reused');
    starknet::testing::set_block_timestamp(current.finish_time);
    influence::systems::missions::starter::pre(
        a, 'ProcessProductsFinish', encode(@(refinery, 1_u64)).span(), mocks::context('PLAYER')
    );
}

#[starknet::contract]
mod AsteroidMissionFixture {
    use array::SpanTrait;
    use starknet::ContractAddress;
    use influence::common::missions;
    use influence::common::missions::Assignment;
    use influence::types::Context;
    #[storage]
    struct Storage {}
    #[external(v0)]
    fn evaluate(
        ref self: ContractState,
        a: Assignment,
        operation: u32,
        action: felt252,
        args: Span<felt252>,
        context: Context
    ) -> (ContractAddress, u128) {
        assert(a.subject.label == influence::config::entities::ASTEROID, 'not asteroid');
        if operation == 0 {
            assert(
                context.caller == starknet::contract_address_const::<'PLAYER'>(), 'not authorized'
            );
        }
        if operation == 2 && !args.is_empty() {
            if *args.at(0) == 0 {
                missions::validate(a, args, context);
            }
            missions::set_state(a, 9, *args.at(0));
            missions::set_flag(a, 1);
        }
        (starknet::contract_address_const::<'PLAYER'>(), 1000000)
    }
}

#[test]
#[available_gas(100000000)]
fn starter_missions_framework_reused_for_asteroid_template() {
    let (a, ast) = setup();
    helpers::deploy_system('AsteroidTemplateFixture', AsteroidMissionFixture::TEST_CLASS_HASH);
    let mut register = RegisterMissionCampaign::contract_state_for_testing();
    RegisterMissionCampaign::run(
        ref register,
        'AsteroidFixture',
        AsteroidMissionFixture::TEST_CLASS_HASH.try_into().unwrap(),
        1,
        mocks::context('ADMIN')
    );
    let other = Assignment { campaign: 'AsteroidFixture', subject: ast, mission: 0 };
    accept(other, 0);
    dispatch('MissionValidate', @(other, array![77_felt252].span()));
    assert(missions::flag(other, 1) && missions::state(other, 9) == 77, 'generic template failed');
    assert(!missions::flag(a, 1) && missions::state(a, 9) == 0, 'starter state affected');
}

#[test]
#[available_gas(100000000)]
#[should_panic]
fn starter_missions_wrapper_reentry_rejected() {
    let (_, ast) = setup();
    helpers::deploy_system('AsteroidTemplateFixture', AsteroidMissionFixture::TEST_CLASS_HASH);
    let mut register = RegisterMissionCampaign::contract_state_for_testing();
    RegisterMissionCampaign::run(
        ref register,
        'AsteroidFixture',
        AsteroidMissionFixture::TEST_CLASS_HASH.try_into().unwrap(),
        1,
        mocks::context('ADMIN')
    );
    let other = Assignment { campaign: 'AsteroidFixture', subject: ast, mission: 0 };
    accept(other, 0);
    dispatch('MissionValidate', @(other, array![0_felt252].span()));
}

use influence::components::order::{statuses as order_statuses, types as order_types, Order};
use influence::systems::orders::helpers::order_path;
use influence::systems::orders::fill_sell::FillSellOrder;
use influence::types::SpanHashTrait;
use influence::components::modifier_type::types as modifier_types;
use influence::components::product_type::types as product_types;

fn market_fill() {
    starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
    let (a, _) = setup();
    accept(a, 0);
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
    ISwayDispatcher { contract_address: sway_address }
        .mint(starknet::contract_address_const::<'PLAYER'>(), amount);
    starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());

    // Setup product
    mocks::product_type(product_types::WATER);

    // Create entities
    let asteroid = influence::test::mocks::asteroid();
    let crew = influence::test::mocks::delegated_crew(101, 'PLAYER');
    let seller_crew = influence::test::mocks::delegated_crew(102, 'SELLER');
    let market_crew = influence::test::mocks::delegated_crew(103, 'MARKET');

    // Setup station
    let station = influence::test::mocks::public_habitat(market_crew, 1);
    components::set::<
        Location
    >(station.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1)));
    components::set::<Location>(crew.path(), LocationTrait::new(station));
    components::set::<Location>(seller_crew.path(), LocationTrait::new(station));
    components::set::<Location>(market_crew.path(), LocationTrait::new(station));

    // Setup marketplace
    let market = influence::test::mocks::public_marketplace(market_crew, 2);
    components::set::<
        Location
    >(market.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 500)));
    components::set::<Control>(market.path(), ControlTrait::new(market_crew));

    // Exercise both campaigns on one native fill. Enrollment/scan are isolated
    // fixtures here; the colonization suite executes those systems end to end.
    influence::config::set('COLONIZATION_CAMPAIGN', 'ColonyTrade');
    let colony = influence::systems::missions::colonization::assignment(asteroid);
    missions::set_flag(colony, 0);
    influence::systems::missions::colonization::earn(colony, 0);
    influence::systems::missions::colonization::after(
        'ConstructionStart', colony, market, 0, mocks::context('MARKET')
    );
    assert(
        !influence::systems::missions::colonization::earned(colony, 3),
        'construction credited commerce'
    );

    // Setup warehouse
    let warehouse = influence::test::mocks::public_warehouse(crew, 3);
    components::set::<
        Location
    >(warehouse.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1000)));
    components::set::<Control>(warehouse.path(), ControlTrait::new(crew));
    // This fixture isolates marketplace receipts; construction is exercised in the full campaign.
    missions::set_state(a, 1, warehouse.id.into());
    let b = components::get::<Building>(warehouse.path()).unwrap();
    let fingerprint = influence::systems::missions::starter::building_fingerprint(warehouse, b);
    let key = influence::systems::missions::starter::key('Built', warehouse, 0);
    missions::set_state(a, key, fingerprint);
    supply(warehouse, 2, array![InventoryItemTrait::new(product_types::WATER, 99999)].span());
    let inventory_path = array![warehouse.into(), 2].span();
    let mut inventory_data = components::get::<Inventory>(inventory_path).unwrap();
    let supplies = array![InventoryItemTrait::new(product_types::WATER, 1000)].span();
    inventory::reserve(ref inventory_data, supplies, FixedTrait::ONE(), FixedTrait::ONE());
    components::set::<Inventory>(inventory_path, inventory_data);

    // Setup order
    let order_path = order_path(
        seller_crew, market, order_types::LIMIT_SELL, product_types::WATER, 100000, warehouse, 2
    );

    components::set::<
        Order
    >(
        order_path,
        Order { status: order_statuses::OPEN, amount: 1000, valid_time: 0, maker_fee: 100 }
    );

    components::set::<Control>(order_path, ControlTrait::new(seller_crew));

    // Send payments
    starknet::testing::set_contract_address(starknet::contract_address_const::<'PLAYER'>());
    ISwayDispatcher { contract_address: sway_address }
        .transfer_with_confirmation(
            starknet::contract_address_const::<'SELLER'>(),
            49500000,
            order_path.hash(),
            starknet::contract_address_const::<'DISPATCHER'>()
        );

    ISwayDispatcher { contract_address: sway_address }
        .transfer_with_confirmation(
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
    let sale = Assignment { subject: seller_crew, ..a };
    starknet::testing::set_caller_address(starknet::contract_address_const::<'SELLER'>());
    accept(sale, 0);
    influence::systems::missions::starter::record_final_product(sale, product_types::WATER);
    influence::systems::missions::starter::record_final_product(a, product_types::WATER);
    starknet::testing::set_caller_address(starknet::contract_address_const::<'PLAYER'>());
    observe(a, 'FillSellOrder', args.span());
    assert(influence::systems::missions::colonization::earned(colony, 3), 'commerce not credited');
    assert(!influence::systems::missions::starter::earned(sale, 7), 'sale credited capstone');
    assert(!influence::systems::missions::starter::earned(a, 7), 'purchase credited capstone');

    // Check order
    let order_data = components::get::<Order>(order_path).unwrap();
    assert(order_data.amount == 500, 'wrong order amount');
    assert(!influence::systems::missions::starter::earned(a, 3), 'reserved purchase counted');
    let delivery = EntityTrait::new(
        entities::DELIVERY, influence::entities::current_id('Delivery')
    );
    starknet::testing::set_block_timestamp(
        components::get::<Delivery>(delivery.path()).unwrap().finish_time
    );
    act(a, 'ReceiveDelivery', @delivery);
    assert(influence::systems::missions::starter::earned(a, 3), 'received purchase not credited');
    assert(
        !influence::systems::missions::starter::earned(sale, 7), 'sale delivery credited seller'
    );
    assert(!influence::systems::missions::starter::earned(a, 7), 'purchase receipt credited');
}

#[test]
#[available_gas(200000000)]
fn starter_missions_receive_from_nonparticipating_sender() {
    let (a, ast, warehouse) = landfall();
    let other = mocks::delegated_crew(102, 'SENDER');
    components::set::<
        Location
    >(other.path(), components::get::<Location>(a.subject.path()).unwrap());
    let source = mocks::public_warehouse(other, 20001);
    components::set::<
        Location
    >(source.path(), LocationTrait::new(EntityTrait::from_position(ast.id, 1758638)));
    supply(source, 2, array![InventoryItemTrait::new(product_types::WATER, 100000)].span());
    components::set::<
        influence::components::PublicPolicy
    >(
        influence::systems::policies::helpers::policy_path(
            warehouse, influence::config::permissions::ADD_PRODUCTS
        ),
        influence::components::PublicPolicy { public: true }
    );
    let mut send = SendDelivery::contract_state_for_testing();
    SendDelivery::run(
        ref send,
        source,
        2,
        array![InventoryItemTrait::new(product_types::WATER, 100000)].span(),
        warehouse,
        2,
        other,
        mocks::context('SENDER')
    );
    let delivery = EntityTrait::new(
        entities::DELIVERY, influence::entities::current_id('Delivery')
    );
    assert(!influence::systems::missions::starter::earned(a, 3), 'inflight receipt counted');
    starknet::testing::set_block_timestamp(
        components::get::<Delivery>(delivery.path()).unwrap().finish_time
    );
    act(a, 'ReceiveDelivery', @delivery);
    assert(influence::systems::missions::starter::earned(a, 3), 'incoming delivery not credited');
    assert(!eligibility::participated(other), 'sender enrolled');
}

#[test]
#[available_gas(150000000)]
fn starter_missions_actual_market_purchase_receipt() {
    market_fill();
}

#[test]
#[available_gas(350000000)]
fn starter_missions_construction_consumes_final_product() {
    let (a, ast, warehouse) = landfall();
    let refinery = construct(a, ast, buildings::REFINERY);
    process(a, refinery, warehouse, processes::CALCITE_CALCINATION);
    process(a, refinery, warehouse, processes::SALTY_CEMENT_MIXING);
    assert(!influence::systems::missions::starter::earned(a, 7), 'holding cement counted');
    construct(a, ast, buildings::EXTRACTOR);
    assert(influence::systems::missions::starter::earned(a, 7), 'construction not credited');
}

#[test]
#[available_gas(250000000)]
fn starter_missions_recipe_change_preserves_pending_run() {
    let (a, ast, warehouse) = landfall();
    let refinery = construct(a, ast, buildings::REFINERY);
    ready(a.subject);
    let id = processes::WATER_VACUUM_EVAPORATION_DESALINATION;
    let mut cfg = ProcessTypeTrait::by_type(id);
    supply(warehouse, 2, cfg.inputs);
    act(
        a,
        'ProcessProductsStart',
        @(
            refinery,
            1_u64,
            id,
            product_types::DEIONIZED_WATER,
            FixedTrait::ONE(),
            warehouse,
            2_u64,
            warehouse,
            2_u64
        )
    );
    let processor = components::get::<Processor>(array![refinery.into(), 1].span()).unwrap();
    cfg.setup_time += 1;
    cfg.recipe_time += 1;
    components::set::<influence::components::ProcessType>(array![id.into()].span(), cfg);
    starknet::testing::set_block_timestamp(processor.finish_time);
    act(a, 'ProcessProductsFinish', @(refinery, 1_u64));
    assert(influence::systems::missions::starter::earned(a, 4), 'refining not credited');
    assert(influence::systems::missions::starter::earned(a, 10), 'route stage not credited');
}

fn observe(a: Assignment, name: felt252, args: Span<felt252>) {
    let mut data = array![];
    for word in args {
        data.append(*word);
    };
    if name != 'FillSellOrder' {
        Serde::serialize(@a.subject, ref data);
    }
    let mut targets = array![
        a.campaign, influence::systems::missions::observer::encode_target(a, 255)
    ];
    if name == 'FillSellOrder' && config::get('COLONIZATION_CAMPAIGN') != 0 {
        let market: Entity = influence::common::mission_evidence::parse(
            influence::common::mission_evidence::segment(args, 2, 2)
        );
        let (id, _) = market.to_position();
        let colony = influence::systems::missions::colonization::assignment(
            EntityTrait::new(entities::ASTEROID, id)
        );
        targets.append(colony.campaign);
        targets.append(influence::systems::missions::observer::encode_target(colony, 8));
    }
    influence::test::mission_observer::observed(name, data, targets.span());
}
