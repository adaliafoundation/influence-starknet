use array::{ArrayTrait, SpanTrait};
use option::OptionTrait;
use traits::{Into, TryInto};
use serde::Serde;
use influence::{components, config};
use influence::common::{missions, random};
use influence::common::missions::Assignment;
use influence::components::{
    Celestial, Control, ControlTrait, Location, LocationTrait, Building, Crew, BuildingTypeTrait,
    ProcessType
};
use influence::components::building_type::types as buildings;
use influence::components::building::statuses;
use influence::components::celestial::statuses as scans;
use influence::components::modifier_type::types as modifiers;
use influence::types::{Entity, EntityTrait, Context};
use influence::config::entities;
use influence::contracts::asteroid::{IAsteroidDispatcher, IAsteroidDispatcherTrait};
use influence::contracts::sway::{ISwayDispatcher, ISwayDispatcherTrait};
use influence::systems::missions::{
    RegisterMissionCampaign, AcceptMission, MissionValidate, ClaimMissionReward
};
use influence::systems::missions::colonization;
use influence::systems::missions::colonization::{
    ColonizationMissionCampaign, ConfigureColonizationMissions
};
use influence::systems::missions::observer::MissionObserver;
use influence::systems::scanning::{ScanSurfaceStart, ScanSurfaceFinish};
use influence::systems::construction::{ConstructionPlan, ConstructionStart, ConstructionFinish};
use influence::systems::crew::station_crew::StationCrew;
use influence::contracts::dispatcher::Dispatcher;
use influence::test::{helpers, mocks, mission_observer, starter_missions};

fn dispatch<T, impl S: Serde<T>, impl D: Drop<T>>(name: felt252, value: @T) {
    let mut state = Dispatcher::contract_state_for_testing();
    Dispatcher::run_system(ref state, name, starter_missions::encode(value));
}
fn observe<T, impl S: Serde<T>, impl D: Drop<T>>(name: felt252, value: @T) {
    let data = starter_missions::encode(value);
    let target: Entity = influence::common::mission_evidence::parse(
        influence::common::mission_evidence::segment(data.span(), 0, 2)
    );
    let ast = if target.label == entities::ASTEROID {
        target
    } else {
        let (id, _) = target.to_position();
        EntityTrait::new(entities::ASTEROID, id)
    };
    let a = colonization::assignment(ast);
    mission_observer::observed(
        name,
        data,
        array![a.campaign, influence::systems::missions::observer::encode_target(a, 31)].span()
    );
}
fn setup() -> (Assignment, Entity) {
    starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
    starknet::testing::set_block_timestamp(100);
    helpers::init();
    mocks::constants();
    helpers::deploy_system('MissionObserver', MissionObserver::TEST_CLASS_HASH);
    helpers::deploy_system('AcceptMission', AcceptMission::TEST_CLASS_HASH);
    helpers::deploy_system('MissionValidate', MissionValidate::TEST_CLASS_HASH);
    helpers::deploy_system('ClaimMissionReward', ClaimMissionReward::TEST_CLASS_HASH);
    helpers::deploy_system('ScanSurfaceStart', ScanSurfaceStart::TEST_CLASS_HASH);
    helpers::deploy_system('ScanSurfaceFinish', ScanSurfaceFinish::TEST_CLASS_HASH);
    helpers::deploy_system('ConstructionPlan', ConstructionPlan::TEST_CLASS_HASH);
    helpers::deploy_system('ConstructionStart', ConstructionStart::TEST_CLASS_HASH);
    helpers::deploy_system('ConstructionFinish', ConstructionFinish::TEST_CLASS_HASH);
    helpers::deploy_system('StationCrew', StationCrew::TEST_CLASS_HASH);
    helpers::deploy_system(
        'ColonizationMissionCampaign', ColonizationMissionCampaign::TEST_CLASS_HASH
    );
    let mut registry = RegisterMissionCampaign::contract_state_for_testing();
    RegisterMissionCampaign::run(
        ref registry,
        'Colony',
        ColonizationMissionCampaign::TEST_CLASS_HASH.try_into().unwrap(),
        5,
        mocks::context('ADMIN')
    );
    let mut configure = ConfigureColonizationMissions::contract_state_for_testing();
    ConfigureColonizationMissions::run(ref configure, 'Colony', mocks::context('ADMIN'));
    let ast = mocks::asteroid();
    let crew = mocks::delegated_crew(1, 'OWNER');
    components::set::<Location>(crew.path(), LocationTrait::new(ast));
    components::set::<Control>(ast.path(), ControlTrait::new(crew));
    let nft = IAsteroidDispatcher { contract_address: helpers::deploy_asteroid() };
    starknet::testing::set_contract_address(starknet::contract_address_const::<'ADMIN'>());
    nft.add_grant(starknet::contract_address_const::<'ADMIN'>(), 2);
    nft.mint_with_id(starknet::contract_address_const::<'OWNER'>(), ast.id.into());
    starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
    starknet::testing::set_caller_address(starknet::contract_address_const::<'OWNER'>());
    (colonization::assignment(ast), crew)
}
fn enroll(a: Assignment) {
    dispatch('AcceptMission', @a);
}
fn scan(a: Assignment, crew: Entity) {
    observe('ScanSurfaceStart', @(a.subject, crew));
    let end = components::get::<Celestial>(a.subject.path()).unwrap().scan_finish_time;
    starknet::testing::set_block_timestamp(end + 1);
    random::entropy::generate();
    observe('ScanSurfaceFinish', @(a.subject, crew));
}
fn scanned() -> (Assignment, Entity) {
    let (a, crew) = setup();
    enroll(a);
    scan(a, crew);
    (a, crew)
}
fn transfer(a: Assignment, from: felt252, to: felt252) {
    let nft = IAsteroidDispatcher { contract_address: influence::contracts::get('Asteroid') };
    starknet::testing::set_contract_address(from.try_into().unwrap());
    nft.transfer_from(from.try_into().unwrap(), to.try_into().unwrap(), a.subject.id.into());
    starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
}
fn fund() -> ISwayDispatcher {
    let token = ISwayDispatcher { contract_address: helpers::deploy_sway() };
    starknet::testing::set_contract_address(starknet::contract_address_const::<'ADMIN'>());
    token.mint(starknet::contract_address_const::<'DISPATCHER'>(), 1500000000000);
    starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
    token
}

#[test]
#[available_gas(150000000)]
fn colony_enroll_scan_and_reward() {
    let (a, crew) = setup();
    enroll(a);
    assert(!missions::flag(a, 1), 'enrollment completed scan');
    scan(a, crew);
    assert(missions::flag(a, 1), 'scan incomplete');
    let token = fund();
    dispatch('ClaimMissionReward', @a);
    assert(
        token.balance_of(starknet::contract_address_const::<'OWNER'>()) == 150000000000,
        'wrong scan payout'
    );
}
#[test]
#[available_gas(100000000)]
#[should_panic(expected: ('scan already started', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
fn colony_cannot_enroll_after_scan_started() {
    let (a, crew) = setup();
    dispatch('ScanSurfaceStart', @(a.subject, crew));
    enroll(a);
}
#[test]
#[available_gas(100000000)]
#[should_panic(expected: ('scan already started', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
fn colony_cannot_enroll_legacy_scanned() {
    let (a, _) = setup();
    let mut celestial = components::get::<Celestial>(a.subject.path()).unwrap();
    celestial.scan_status = scans::SURFACE_SCANNED;
    components::set::<Celestial>(a.subject.path(), celestial);
    enroll(a);
}
#[test]
#[available_gas(100000000)]
#[should_panic(expected: ('not owner', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
fn colony_non_owner_cannot_enroll() {
    let (a, _) = setup();
    starknet::testing::set_caller_address(starknet::contract_address_const::<'OTHER'>());
    enroll(a);
}
#[test]
#[available_gas(100000000)]
#[should_panic(expected: ('mission already accepted', 'ENTRYPOINT_FAILED'))]
fn colony_cannot_enroll_twice() {
    let (a, _) = setup();
    enroll(a);
    enroll(a);
}
#[test]
#[available_gas(150000000)]
#[should_panic(expected: ('unobserved scan start', 'ENTRYPOINT_FAILED'))]
fn colony_unobserved_scan_start_rejected() {
    let (a, crew) = setup();
    enroll(a);
    dispatch('ScanSurfaceStart', @(a.subject, crew));
    starknet::testing::set_block_timestamp(10000);
    random::entropy::generate();
    observe('ScanSurfaceFinish', @(a.subject, crew));
}
#[test]
#[available_gas(150000000)]
#[should_panic(expected: ('not owner', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
fn colony_sale_blocks_claim() {
    let (a, _) = scanned();
    transfer(a, 'OWNER', 'OTHER');
    fund();
    dispatch('ClaimMissionReward', @a);
}
#[test]
#[available_gas(150000000)]
#[should_panic(expected: ('not colonizer', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
fn colony_buyer_does_not_inherit_reward() {
    let (a, _) = scanned();
    transfer(a, 'OWNER', 'OTHER');
    fund();
    starknet::testing::set_caller_address(starknet::contract_address_const::<'OTHER'>());
    dispatch('ClaimMissionReward', @a);
}
#[test]
#[available_gas(150000000)]
fn colony_reacquisition_restores_claims() {
    let (a, _) = scanned();
    transfer(a, 'OWNER', 'OTHER');
    transfer(a, 'OTHER', 'OWNER');
    fund();
    dispatch('ClaimMissionReward', @a);
    assert(missions::flag(a, 2), 'reacquired claim failed');
}
#[test]
#[available_gas(150000000)]
#[should_panic(expected: ('reward already paid', 'ENTRYPOINT_FAILED'))]
fn colony_duplicate_claim_rejected() {
    let (a, _) = scanned();
    fund();
    dispatch('ClaimMissionReward', @a);
    dispatch('ClaimMissionReward', @a);
}

// Isolated provenance fixtures exercise the policy's state checks independently
// of native gameplay. The full native construction/usage tests below cover routing.
fn building_fixture(a: Assignment, kind: u64, id: u64) -> Entity {
    let entity = EntityTrait::new(entities::BUILDING, id);
    components::set::<
        Location
    >(entity.path(), LocationTrait::new(EntityTrait::from_position(a.subject.id, 1)));
    components::set::<
        Building
    >(
        entity.path(),
        Building {
            building_type: kind, status: statuses::OPERATIONAL, planned_at: 100, finish_time: 200
        }
    );
    entity
}
fn record_building(a: Assignment, kind: u64, id: u64) -> Entity {
    let entity = building_fixture(a, kind, id);
    colonization::after('ConstructionStart', a, entity, 0, mocks::context('BUILDER'));
    colonization::record_use(a, entity);
    entity
}
fn full_colony() -> (Assignment, Entity) {
    let (a, _) = scanned();
    record_building(a, buildings::MARKETPLACE, 103);
    record_building(a, buildings::SPACEPORT, 102);
    let habitat = record_building(a, buildings::HABITAT, 101);
    let mut i = 1;
    loop {
        if i == 5 {
            break;
        }
        dispatch('AcceptMission', @Assignment { mission: i, ..a });
        i += 1;
    };
    (a, habitat)
}
#[test]
#[available_gas(300000000)]
fn colony_all_rewards_and_early_branch_progress() {
    let (a, _) = full_colony();
    let token = fund();
    let mut i = 0;
    loop {
        if i == 5 {
            break;
        }
        dispatch('ClaimMissionReward', @Assignment { mission: i, ..a });
        i += 1;
    };
    assert(
        token.balance_of(starknet::contract_address_const::<'OWNER'>()) == 1500000000000,
        'wrong colony total'
    );
}
#[test]
#[available_gas(300000000)]
#[should_panic(expected: ('colony not operational', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
fn colony_capstone_rechecks_operational_state_after_completion() {
    let (a, habitat) = full_colony();
    assert(missions::flag(Assignment { mission: 4, ..a }, 1), 'capstone not cached');
    let mut data = components::get::<Building>(habitat.path()).unwrap();
    data.status = statuses::PLANNED;
    components::set::<Building>(habitat.path(), data);
    fund();
    dispatch('ClaimMissionReward', @Assignment { mission: 4, ..a });
}
#[test]
#[available_gas(300000000)]
fn colony_replacement_building_restores_capstone() {
    let (a, habitat) = full_colony();
    let mut data = components::get::<Building>(habitat.path()).unwrap();
    data.status = statuses::PLANNED;
    components::set::<Building>(habitat.path(), data);
    assert(!colonization::operational_colony(a), 'demolished colony accepted');
    record_building(a, buildings::HABITAT, 104);
    assert(colonization::operational_colony(a), 'replacement not selected');
    fund();
    dispatch('ClaimMissionReward', @Assignment { mission: 4, ..a });
}
#[test]
#[available_gas(300000000)]
fn colony_valid_selection_survives_other_building_use_and_demolition() {
    let (a, habitat) = full_colony();
    colonization::record_use(a, habitat);
    let second = record_building(a, buildings::HABITAT, 104);
    assert(missions::state(a, 1) == habitat.id.into(), 'valid selection replaced');
    let mut data = components::get::<Building>(second.path()).unwrap();
    data.status = statuses::PLANNED;
    components::set::<Building>(second.path(), data);
    assert(colonization::operational_colony(a), 'original selection lost');
    fund();
    dispatch('ClaimMissionReward', @Assignment { mission: 4, ..a });
}

#[test]
#[available_gas(250000000)]
fn colony_construction_at_scan_completion_timestamp_qualifies() {
    let (a, crew) = scanned();
    let building = construction_setup(a, crew, buildings::HABITAT);
    finish_construction(building, crew);
    observe('StationCrew', @(building, crew));
    assert(colonization::earned(a, 1), 'equal timestamp proof lost');
}

#[test]
#[available_gas(150000000)]
fn colony_old_building_and_rebuild_cannot_reuse_proof() {
    let (a, _) = scanned();
    let building = building_fixture(a, buildings::HABITAT, 101);
    assert(!colonization::qualifying(a, building), 'old building qualified');
    record_building(a, buildings::HABITAT, 101);
    let mut data = components::get::<Building>(building.path()).unwrap();
    data.finish_time += 1;
    components::set::<Building>(building.path(), data);
    assert(!colonization::qualifying(a, building), 'rebuild reused proof');
}

fn construction_setup(a: Assignment, crew: Entity, kind: u64) -> Entity {
    let station = mocks::public_habitat(crew, 10001);
    components::set::<
        Location
    >(station.path(), LocationTrait::new(EntityTrait::from_position(a.subject.id, 1)));
    components::set::<Location>(crew.path(), LocationTrait::new(station));
    for modifier in array![
        modifiers::HOPPER_TRANSPORT_TIME,
        modifiers::FREE_TRANSPORT_DISTANCE,
        modifiers::CONSTRUCTION_TIME
    ] {
        mocks::modifier_type(modifier);
    };
    mocks::building_type(kind);
    let cfg = BuildingTypeTrait::by_type(kind);
    mocks::inventory_type(cfg.site_type);
    components::set::<
        ProcessType
    >(
        array![cfg.process_type.into()].span(),
        ProcessType {
            setup_time: 3600,
            recipe_time: 0,
            batched: false,
            processor_type: 0,
            inputs: array![].span(),
            outputs: array![].span()
        }
    );
    dispatch('ConstructionPlan', @(kind, EntityTrait::from_position(a.subject.id, kind + 1), crew));
    EntityTrait::new(entities::BUILDING, influence::entities::current_id(entities::BUILDING.into()))
}
fn finish_construction(building: Entity, crew: Entity) {
    observe('ConstructionStart', @(building, crew));
    let end = components::get::<Building>(building.path()).unwrap().finish_time;
    starknet::testing::set_block_timestamp(end);
    observe('ConstructionFinish', @(building, crew));
}
#[test]
#[available_gas(250000000)]
fn colony_native_third_party_construction_and_stationing() {
    let (a, crew) = scanned();
    let building = construction_setup(a, crew, buildings::HABITAT);
    let builder = mocks::delegated_crew(2, 'BUILDER');
    components::set::<Location>(builder.path(), components::get::<Location>(crew.path()).unwrap());
    components::set::<Control>(building.path(), ControlTrait::new(builder));
    starknet::testing::set_caller_address(starknet::contract_address_const::<'BUILDER'>());
    finish_construction(building, builder);
    assert(!colonization::earned(a, 1), 'construction alone credited');
    observe('StationCrew', @(building, builder));
    assert(colonization::earned(a, 1), 'third party use missing');
    starknet::testing::set_caller_address(starknet::contract_address_const::<'OWNER'>());
    dispatch('AcceptMission', @Assignment { mission: 1, ..a });
    fund();
    dispatch('ClaimMissionReward', @Assignment { mission: 1, ..a });
}
#[test]
#[available_gas(250000000)]
fn colony_native_docking() {
    let (a, crew) = scanned();
    let building = construction_setup(a, crew, buildings::SPACEPORT);
    finish_construction(building, crew);
    helpers::deploy_system('DockShip', influence::systems::ship::DockShip::TEST_CLASS_HASH);
    mocks::dock_type(influence::components::dock_type::types::BASIC);
    let mut celestial = components::get::<Celestial>(a.subject.path()).unwrap();
    celestial.scan_status = scans::RESOURCE_SCANNED;
    components::set::<Celestial>(a.subject.path(), celestial);
    let ship = mocks::controlled_light_transport(crew, 1);
    components::set::<Location>(crew.path(), LocationTrait::new(ship));
    components::set::<Location>(ship.path(), LocationTrait::new(a.subject));
    starter_missions::ready(crew);
    observe('DockShip', @(building, false, crew));
    assert(colonization::earned(a, 2), 'docking not credited');
    assert(
        components::get::<Location>(ship.path()).unwrap().location == building, 'ship not docked'
    );
}
#[test]
#[available_gas(200000000)]
fn colony_pre_scan_construction_does_not_qualify() {
    let (a, crew) = setup();
    enroll(a);
    let building = construction_setup(a, crew, buildings::HABITAT);
    observe('ConstructionStart', @(building, crew));
    starter_missions::ready(crew);
    scan(a, crew);
    let end = components::get::<Building>(building.path()).unwrap().finish_time;
    if end > starknet::get_block_timestamp() {
        starknet::testing::set_block_timestamp(end);
    }
    observe('ConstructionFinish', @(building, crew));
    assert(!colonization::qualifying(a, building), 'old start qualified');
}
#[test]
#[available_gas(150000000)]
fn colony_wrong_asteroid_does_not_qualify() {
    let (a, _) = scanned();
    let building = record_building(a, buildings::HABITAT, 101);
    let other = mocks::adalia_prime();
    components::set::<
        Location
    >(building.path(), LocationTrait::new(EntityTrait::from_position(other.id, 1)));
    assert(!colonization::qualifying(a, building), 'wrong asteroid qualified');
}


#[test]
#[available_gas(150000000)]
fn colony_candidates_only_validate_selected_missions() {
    let (a, _) = scanned();
    for mission in array![
        1_u32, 2_u32
    ] {
        dispatch('AcceptMission', @Assignment { mission, ..a });
        colonization::earn(a, mission);
    };
    influence::systems::missions::observer::validate(a, 2);
    assert(missions::flag(Assignment { mission: 1, ..a }, 1), 'selected mission incomplete');
    assert(!missions::flag(Assignment { mission: 2, ..a }, 1), 'omitted mission evaluated');
    let args: Array<felt252> = array![];
    dispatch('MissionValidate', @(Assignment { mission: 2, ..a }, args.span()));
    assert(missions::flag(Assignment { mission: 2, ..a }, 1), 'shared evidence lost');
}

#[test]
#[available_gas(100000000)]
#[should_panic(expected: ('wrong colony target', 'ENTRYPOINT_FAILED'))]
fn colony_candidate_cannot_redirect_scan_evidence() {
    let (a, crew) = setup();
    enroll(a);
    let other = Assignment { subject: EntityTrait::new(entities::ASTEROID, a.subject.id + 1), ..a };
    missions::set_flag(other, 0);
    mission_observer::observed(
        'ScanSurfaceStart',
        starter_missions::encode(@(a.subject, crew)),
        array![other.campaign, influence::systems::missions::observer::encode_target(other, 1)]
            .span()
    );
}

#[test]
#[available_gas(100000000)]
#[should_panic(expected: ('duplicate mission target', 'ENTRYPOINT_FAILED'))]
fn colony_duplicate_candidate_groups_rejected() {
    let (a, crew) = setup();
    enroll(a);
    let packed = influence::systems::missions::observer::encode_target(a, 1);
    mission_observer::observed(
        'ScanSurfaceStart',
        starter_missions::encode(@(a.subject, crew)),
        array![a.campaign, packed, a.campaign, packed].span()
    );
}

#[test]
#[available_gas(100000000)]
#[should_panic(expected: ('invalid mission mask', 'ENTRYPOINT_FAILED'))]
fn colony_out_of_range_candidate_rejected() {
    let (a, crew) = setup();
    enroll(a);
    mission_observer::observed(
        'ScanSurfaceStart',
        starter_missions::encode(@(a.subject, crew)),
        array![a.campaign, influence::systems::missions::observer::encode_target(a, 32)].span()
    );
}
