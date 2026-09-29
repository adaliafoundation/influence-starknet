use array::ArrayTrait;
use option::OptionTrait;
use traits::{Into, TryInto};
use starknet::testing;

use influence::components;
use influence::components::{
    Building, Control, ControlTrait, Location, LocationTrait, PrepaidAgreement, PrepaidAgreementTrait,
    PrepaidAgreementAuction, PrepaidAgreementAuctionTrait, Unique,
    building::statuses, building_type::types as building_types
};
use influence::config::{entities, permissions};
use influence::contracts::sway::{ISwayDispatcher, ISwayDispatcherTrait};
use influence::systems::agreements::accept_prepaid::AcceptPrepaidAgreement;
use influence::systems::agreements::extend_prepaid::{
    ExtendPrepaidAgreement, IExtendPrepaidAgreementLibraryDispatcher, IExtendPrepaidAgreementDispatcherTrait
};
use influence::systems::agreements::helpers::{agreement_path, lot_use_path, use_lot_path};
use influence::systems::construction::construction_abandon::ConstructionAbandon;
use influence::systems::construction::construction_plan::ConstructionPlan;
use influence::systems::control::repossess_building::RepossessBuilding;
use influence::test::{helpers, mocks};
use influence::types::{ArrayHashTrait, Entity, EntityTrait};

#[derive(Copy, Drop)]
struct Fixture {
    lot: Entity,
    owner: Entity,
    tenant: Entity,
    stranger: Entity,
    building: Entity,
}

// Start with a real tenant-planned site, then advance past the lease's end.
fn expired_site() -> Fixture {
    testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
    helpers::init();
    mocks::constants();
    testing::set_block_timestamp(100);
    let asteroid = mocks::adalia_prime();
    let lot = EntityTrait::from_position(asteroid.id, 1001);
    let owner = mocks::delegated_crew(1, 'OWNER');
    let tenant = mocks::delegated_crew(2, 'TENANT');
    let stranger = mocks::delegated_crew(3, 'STRANGER');
    components::set::<Control>(asteroid.path(), ControlTrait::new(owner));
    components::set::<Location>(owner.path(), LocationTrait::new(lot));
    components::set::<Location>(tenant.path(), LocationTrait::new(lot));
    components::set::<Location>(stranger.path(), LocationTrait::new(lot));
    components::set::<Unique>(use_lot_path(lot), Unique { unique: tenant.into() });
    components::set::<PrepaidAgreement>(
        agreement_path(lot, permissions::USE_LOT, tenant.into()),
        PrepaidAgreementTrait::new(3600, 100, 20, 100, 200)
    );
    mocks::building_type(building_types::WAREHOUSE);
    let mut state = ConstructionPlan::contract_state_for_testing();
    ConstructionPlan::run(ref state, building_types::WAREHOUSE, lot, tenant, mocks::context('TENANT'));
    let building = components::get::<Unique>(lot_use_path(lot)).unwrap().unique.try_into().unwrap();
    testing::set_block_timestamp(201);
    Fixture { lot, owner, tenant, stranger, building }
}

fn owner_replacement() -> Fixture {
    let mut fixture = expired_site();
    let mut abandon = ConstructionAbandon::contract_state_for_testing();
    ConstructionAbandon::run(ref abandon, fixture.building, fixture.tenant, mocks::context('TENANT'));
    let mut plan = ConstructionPlan::contract_state_for_testing();
    ConstructionPlan::run(
        ref plan, building_types::WAREHOUSE, fixture.lot, fixture.owner, mocks::context('OWNER')
    );
    fixture.building = components::get::<Unique>(lot_use_path(fixture.lot)).unwrap().unique.try_into().unwrap();
    fixture
}

fn legacy_owner_replacement() -> Fixture {
    let fixture = owner_replacement();
    // Reproduce owner sites created before ConstructionPlan cleared the stale tenant.
    components::set::<Unique>(use_lot_path(fixture.lot), Unique { unique: fixture.tenant.into() });
    fixture
}

fn set_status(fixture: Fixture, status: u64) {
    let mut building = components::get::<Building>(fixture.building.path()).unwrap();
    building.status = status;
    components::set::<Building>(fixture.building.path(), building);
}

fn repossess(fixture: Fixture, caller: Entity, delegate: felt252) {
    let mut state = RepossessBuilding::contract_state_for_testing();
    RepossessBuilding::run(ref state, fixture.building, caller, mocks::context(delegate));
    let control = components::get::<Control>(fixture.building.path()).unwrap();
    assert(control.controller == caller, 'wrong building controller');
}

fn restore(fixture: Fixture, permitted: Entity, delegate: felt252) {
    restore_to(fixture, permitted, delegate, 'OWNER');
}

fn restore_to(fixture: Fixture, permitted: Entity, delegate: felt252, recipient: felt252) {
    let building_controller = components::get::<Control>(fixture.building.path()).unwrap().controller;
    let sway = ISwayDispatcher { contract_address: helpers::deploy_sway() };
    let payer = delegate.try_into().unwrap();
    testing::set_contract_address(starknet::contract_address_const::<'ADMIN'>());
    sway.mint(payer, 3600);
    testing::set_contract_address(payer);
    let memo = array![fixture.lot.into(), permissions::USE_LOT.into(), permitted.into()];
    sway.transfer_with_confirmation(
        recipient.try_into().unwrap(), 3600, memo.hash(),
        starknet::contract_address_const::<'DISPATCHER'>()
    );
    testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
    IExtendPrepaidAgreementLibraryDispatcher {
        class_hash: ExtendPrepaidAgreement::TEST_CLASS_HASH.try_into().unwrap()
    }.run(fixture.lot, permissions::USE_LOT, permitted, 3600, permitted, mocks::context(delegate));
    let agreement = components::get::<PrepaidAgreement>(
        agreement_path(fixture.lot, permissions::USE_LOT, permitted.into())
    ).unwrap();
    let now = starknet::get_block_timestamp();
    assert(agreement.start_time == now, 'wrong restored start');
    assert(agreement.end_time == now + 3600, 'wrong restored end');
    assert(agreement.rate == 3600, 'changed lease rate');
    assert(components::get::<Unique>(use_lot_path(fixture.lot)).unwrap().unique == permitted.into(), 'wrong tenant');
    assert(components::get::<PrepaidAgreementAuction>(fixture.lot.path()).is_none(), 'auction still active');
    assert(components::get::<Control>(fixture.building.path()).unwrap().controller == building_controller, 'building owner changed');
}

#[test]
#[available_gas(50000000)]
fn owner_replacement_clears_stale_tenant() {
    let fixture = owner_replacement();
    assert(components::get::<Unique>(use_lot_path(fixture.lot)).is_none(), 'stale tenant retained');
    assert(components::get::<Control>(fixture.building.path()).unwrap().controller == fixture.owner, 'wrong owner');
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('in grace period', ))]
fn former_tenant_cannot_take_owner_replacement_during_grace() {
    let fixture = owner_replacement();
    repossess(fixture, fixture.tenant, 'TENANT');
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('not planned status', ))]
fn former_tenant_cannot_take_completed_owner_replacement() {
    let fixture = owner_replacement();
    set_status(fixture, statuses::OPERATIONAL);
    repossess(fixture, fixture.tenant, 'TENANT');
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('in grace period', ))]
fn legacy_tenant_cannot_bypass_owner_site_grace() {
    let fixture = legacy_owner_replacement();
    repossess(fixture, fixture.tenant, 'TENANT');
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('not planned status', ))]
fn legacy_tenant_cannot_take_completed_owner_building() {
    let fixture = legacy_owner_replacement();
    set_status(fixture, statuses::OPERATIONAL);
    repossess(fixture, fixture.tenant, 'TENANT');
}

#[test]
#[available_gas(50000000)]
fn expired_tenant_can_restore_original_site_during_auction() {
    let fixture = expired_site();
    components::set::<PrepaidAgreementAuction>(fixture.lot.path(), PrepaidAgreementAuctionTrait::new(201));
    restore(fixture, fixture.tenant, 'TENANT');
    assert(components::get::<Control>(fixture.building.path()).unwrap().controller == fixture.tenant, 'owner changed');
}

#[test]
#[available_gas(50000000)]
fn expired_tenant_can_restore_completed_building() {
    let fixture = expired_site();
    set_status(fixture, statuses::OPERATIONAL);
    restore(fixture, fixture.tenant, 'TENANT');
}

#[test]
#[available_gas(50000000)]
fn building_controller_can_restore_expired_lease() {
    let fixture = expired_site();
    components::set::<Control>(fixture.building.path(), ControlTrait::new(fixture.stranger));
    restore(fixture, fixture.stranger, 'STRANGER');
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('E2002: access denied', 'ENTRYPOINT_FAILED'))]
fn stranger_cannot_restore_expired_lease() {
    let fixture = expired_site();
    restore(fixture, fixture.stranger, 'STRANGER');
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('E2002: access denied', 'ENTRYPOINT_FAILED'))]
fn former_tenant_cannot_restore_after_new_tenant_takes_over() {
    let fixture = expired_site();
    components::set::<Control>(fixture.building.path(), ControlTrait::new(fixture.stranger));
    components::set::<Unique>(use_lot_path(fixture.lot), Unique { unique: fixture.stranger.into() });
    components::set::<PrepaidAgreement>(
        agreement_path(fixture.lot, permissions::USE_LOT, fixture.stranger.into()),
        PrepaidAgreementTrait::new(3600, 100, 20, 201, 400)
    );
    restore(fixture, fixture.tenant, 'TENANT');
}

#[test]
#[available_gas(50000000)]
fn restored_tenant_can_repossess_building() {
    let fixture = expired_site();
    set_status(fixture, statuses::OPERATIONAL);
    components::set::<Control>(fixture.building.path(), ControlTrait::new(fixture.stranger));
    restore(fixture, fixture.tenant, 'TENANT');
    repossess(fixture, fixture.tenant, 'TENANT');
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('not planned status', ))]
fn expired_tenant_must_restore_before_taking_completed_building() {
    let fixture = expired_site();
    set_status(fixture, statuses::OPERATIONAL);
    components::set::<Control>(fixture.building.path(), ControlTrait::new(fixture.stranger));
    repossess(fixture, fixture.tenant, 'TENANT');
}

#[test]
#[available_gas(50000000)]
fn active_tenant_can_repossess_at_permission_expiry_boundary() {
    let fixture = expired_site();
    testing::set_block_timestamp(200);
    set_status(fixture, statuses::OPERATIONAL);
    components::set::<Control>(fixture.building.path(), ControlTrait::new(fixture.stranger));
    repossess(fixture, fixture.tenant, 'TENANT');
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('blocked by lot user', ))]
fn owner_cannot_repossess_active_tenant_building() {
    let fixture = expired_site();
    testing::set_block_timestamp(200);
    repossess(fixture, fixture.owner, 'OWNER');
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('blocked by lot user', ))]
fn stranger_cannot_repossess_active_tenant_site_after_grace() {
    let fixture = expired_site();
    components::set::<PrepaidAgreement>(
        agreement_path(fixture.lot, permissions::USE_LOT, fixture.tenant.into()),
        PrepaidAgreementTrait::new(3600, 100, 20, 100, 300000)
    );
    testing::set_block_timestamp(200000);
    repossess(fixture, fixture.stranger, 'STRANGER');
}

#[test]
#[available_gas(50000000)]
fn stranger_can_repossess_lapsed_tenant_site_after_grace() {
    let fixture = expired_site();
    testing::set_block_timestamp(200000);
    repossess(fixture, fixture.stranger, 'STRANGER');
}

#[test]
#[available_gas(50000000)]
fn stranger_can_repossess_owner_site_without_tenant_after_grace() {
    let fixture = owner_replacement();
    testing::set_block_timestamp(200000);
    repossess(fixture, fixture.stranger, 'STRANGER');
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('E1021: unique not found', 'ENTRYPOINT_FAILED'))]
fn tenant_cannot_restore_after_owner_repossesses() {
    let fixture = expired_site();
    repossess(fixture, fixture.owner, 'OWNER');
    restore(fixture, fixture.tenant, 'TENANT');
}

#[test]
#[available_gas(50000000)]
fn former_tenant_has_only_normal_outsider_rights_after_grace() {
    let fixture = legacy_owner_replacement();
    testing::set_block_timestamp(201 + 172800);
    repossess(fixture, fixture.tenant, 'TENANT');
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('in grace period', ))]
fn legacy_tenant_cannot_take_site_just_before_grace_ends() {
    let fixture = legacy_owner_replacement();
    testing::set_block_timestamp(201 + 172800 - 1);
    repossess(fixture, fixture.tenant, 'TENANT');
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('not planned status', ))]
fn legacy_tenant_cannot_take_owner_building_under_construction_after_grace() {
    let fixture = legacy_owner_replacement();
    set_status(fixture, statuses::UNDER_CONSTRUCTION);
    testing::set_block_timestamp(201 + 172800);
    repossess(fixture, fixture.tenant, 'TENANT');
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('E1021: unique not found', 'ENTRYPOINT_FAILED'))]
fn former_tenant_cannot_restore_over_new_owner_replacement() {
    let fixture = owner_replacement();
    restore(fixture, fixture.tenant, 'TENANT');
}

#[test]
#[available_gas(50000000)]
fn tenant_can_restore_at_lease_expiry_boundary() {
    let fixture = expired_site();
    testing::set_block_timestamp(200);
    restore(fixture, fixture.tenant, 'TENANT');
}

#[test]
#[available_gas(50000000)]
fn tenant_can_restore_building_under_construction() {
    let fixture = expired_site();
    set_status(fixture, statuses::UNDER_CONSTRUCTION);
    restore(fixture, fixture.tenant, 'TENANT');
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('E6020: agreement cancelled', 'ENTRYPOINT_FAILED'))]
fn cancelled_tenant_cannot_restore_terminated_lease() {
    let fixture = expired_site();
    let path = agreement_path(fixture.lot, permissions::USE_LOT, fixture.tenant.into());
    let mut agreement = components::get::<PrepaidAgreement>(path).unwrap();
    agreement.notice_time = 180;
    components::set::<PrepaidAgreement>(path, agreement);
    restore(fixture, fixture.tenant, 'TENANT');
}

#[test]
#[available_gas(50000000)]
fn tenant_keeps_repossession_rights_through_notice_period() {
    let fixture = expired_site();
    let path = agreement_path(fixture.lot, permissions::USE_LOT, fixture.tenant.into());
    let mut agreement = components::get::<PrepaidAgreement>(path).unwrap();
    agreement.notice_time = 190;
    components::set::<PrepaidAgreement>(path, agreement);
    testing::set_block_timestamp(210);
    set_status(fixture, statuses::OPERATIONAL);
    components::set::<Control>(fixture.building.path(), ControlTrait::new(fixture.stranger));
    repossess(fixture, fixture.tenant, 'TENANT');
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('not planned status', ))]
fn tenant_loses_repossession_rights_after_notice_period() {
    let fixture = expired_site();
    let path = agreement_path(fixture.lot, permissions::USE_LOT, fixture.tenant.into());
    let mut agreement = components::get::<PrepaidAgreement>(path).unwrap();
    agreement.notice_time = 190;
    components::set::<PrepaidAgreement>(path, agreement);
    testing::set_block_timestamp(211);
    set_status(fixture, statuses::OPERATIONAL);
    components::set::<Control>(fixture.building.path(), ControlTrait::new(fixture.stranger));
    repossess(fixture, fixture.tenant, 'TENANT');
}

#[test]
#[available_gas(50000000)]
fn owner_can_repossess_lapsed_tenant_building_and_clear_tenancy() {
    let fixture = expired_site();
    set_status(fixture, statuses::OPERATIONAL);
    repossess(fixture, fixture.owner, 'OWNER');
    assert(components::get::<Unique>(use_lot_path(fixture.lot)).is_none(), 'stale tenant retained');
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('E1021: unique not found', 'ENTRYPOINT_FAILED'))]
fn abandoned_empty_site_requires_new_lease_instead_of_restoration() {
    let fixture = expired_site();
    let mut abandon = ConstructionAbandon::contract_state_for_testing();
    ConstructionAbandon::run(ref abandon, fixture.building, fixture.tenant, mocks::context('TENANT'));
    restore(fixture, fixture.tenant, 'TENANT');
}

#[test]
#[available_gas(50000000)]
fn tenant_can_restore_when_original_building_controller_crew_is_missing() {
    let fixture = expired_site();
    components::set::<Control>(fixture.building.path(), ControlTrait::new(EntityTrait::new(entities::CREW, 99)));
    restore(fixture, fixture.tenant, 'TENANT');
    repossess(fixture, fixture.tenant, 'TENANT');
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('lot controlled by asteroid', ))]
fn former_tenant_cannot_accept_new_lease_over_owner_replacement() {
    let fixture = owner_replacement();
    let mut state = AcceptPrepaidAgreement::contract_state_for_testing();
    AcceptPrepaidAgreement::run(
        ref state, fixture.lot, permissions::USE_LOT, fixture.tenant, 3600, fixture.tenant, mocks::context('TENANT')
    );
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('lot controlled by asteroid', ))]
fn former_tenant_cannot_accept_new_lease_over_owner_sibling_crew_building() {
    let fixture = legacy_owner_replacement();
    let sibling = mocks::delegated_crew(4, 'OWNER');
    components::set::<Control>(fixture.building.path(), ControlTrait::new(sibling));
    let mut state = AcceptPrepaidAgreement::contract_state_for_testing();
    AcceptPrepaidAgreement::run(
        ref state, fixture.lot, permissions::USE_LOT, fixture.tenant, 3600, fixture.tenant, mocks::context('TENANT')
    );
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('E6053: agreement expired', 'ENTRYPOINT_FAILED'))]
fn building_controller_cannot_restore_over_another_tenants_active_lease() {
    let fixture = expired_site();
    components::set::<Unique>(use_lot_path(fixture.lot), Unique { unique: fixture.stranger.into() });
    components::set::<PrepaidAgreement>(
        agreement_path(fixture.lot, permissions::USE_LOT, fixture.stranger.into()),
        PrepaidAgreementTrait::new(3600, 100, 20, 201, 400)
    );
    restore(fixture, fixture.tenant, 'TENANT');
}

#[test]
#[available_gas(50000000)]
fn legitimate_tenant_can_restore_after_becoming_asteroid_controller() {
    let fixture = expired_site();
    let asteroid = EntityTrait::new(entities::ASTEROID, 1);
    components::set::<Control>(asteroid.path(), ControlTrait::new(fixture.tenant));
    restore_to(fixture, fixture.tenant, 'TENANT', 'TENANT');
}

#[test]
#[available_gas(50000000)]
fn legitimate_tenant_can_restore_when_asteroid_and_building_share_delegate() {
    let fixture = expired_site();
    let sibling = mocks::delegated_crew(4, 'TENANT');
    let asteroid = EntityTrait::new(entities::ASTEROID, 1);
    components::set::<Control>(asteroid.path(), ControlTrait::new(sibling));
    restore_to(fixture, fixture.tenant, 'TENANT', 'TENANT');
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('E1021: unique not found', 'ENTRYPOINT_FAILED'))]
fn cleaned_legacy_tenant_cannot_restore_after_asteroid_changes_hands() {
    let fixture = legacy_owner_replacement();
    components::set::<Unique>(use_lot_path(fixture.lot), Unique { unique: 0 });
    let asteroid = EntityTrait::new(entities::ASTEROID, 1);
    components::set::<Control>(asteroid.path(), ControlTrait::new(fixture.stranger));
    restore_to(fixture, fixture.tenant, 'TENANT', 'STRANGER');
}

#[test]
#[available_gas(50000000)]
fn cleanup_script_storage_vectors_match_contract_layout() {
    let fixture = expired_site();
    let unique_base = components::resolve('Unique', use_lot_path(fixture.lot));
    let unique_key: felt252 = unique_base.into();
    assert(unique_key == 0x6db83780c4781b5cd7df5a6a395df96d0b89e034e1c3f92db4764b714e76278, 'wrong unique storage key');
    let agreement_base = components::resolve(
        'PrepaidAgreement', agreement_path(fixture.lot, permissions::USE_LOT, fixture.tenant.into())
    );
    let agreement_key: felt252 = agreement_base.into();
    assert(agreement_key == 0x265f758e03d26d386c92d3717f24c5fe8edac4ee5af096115b02104a76acd4f, 'wrong agreement storage key');
    let packed = starknet::Store::<felt252>::read(0, agreement_base).unwrap();
    assert(packed == 4676805239492917574943984346243430628471523843771920, 'wrong agreement packing');
}
