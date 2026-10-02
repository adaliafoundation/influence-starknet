use array::ArrayTrait;
use option::OptionTrait;
use traits::{Into, TryInto};
use starknet::{ClassHash, testing, syscalls::deploy_syscall};

use influence::components;
use influence::components::{
    Building, Control, ControlTrait, Location, LocationTrait, PrepaidAgreement, PrepaidAgreementTrait,
    WhitelistAgreement, WhitelistAgreementTrait, PublicPolicy, PublicPolicyTrait,
    ContractAgreement, ContractAgreementTrait, Unique,
    building::statuses, building_type::types as building_types
};
use influence::config::{entities, permissions};
use influence::contracts::contract_policy::ContractPolicy;
use influence::systems::agreements::helpers::{agreement_path, lot_use_path, use_lot_path};
use influence::systems::agreements::extend_prepaid::ExtendPrepaidAgreement;
use influence::systems::agreements::whitelist::Whitelist;
use influence::systems::agreements::whitelist_account::WhitelistAccount;
use influence::systems::policies::helpers::policy_path;
use influence::systems::construction::construction_plan::ConstructionPlan;
use influence::systems::construction::construction_abandon::ConstructionAbandon;
use influence::systems::control::repossess_building::RepossessBuilding;
use influence::test::{helpers, mocks};
use influence::types::{Entity, EntityTrait};

#[derive(Copy, Drop)]
struct Fixture {
    asteroid: Entity,
    lot: Entity,
    owner: Entity,
    tenant: Entity,
    builder: Entity,
    other: Entity,
}

fn setup() -> Fixture {
    testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
    helpers::init();
    mocks::constants();
    testing::set_block_timestamp(201);
    let asteroid = mocks::asteroid();
    let lot = EntityTrait::from_position(asteroid.id, 1001);
    let owner = mocks::delegated_crew(1, 'OWNER');
    let tenant = mocks::delegated_crew(2, 'TENANT');
    let builder = mocks::delegated_crew(3, 'BUILDER');
    let other = mocks::delegated_crew(4, 'OTHER');
    components::set::<Control>(asteroid.path(), ControlTrait::new(owner));
    components::set::<Location>(owner.path(), LocationTrait::new(lot));
    components::set::<Location>(tenant.path(), LocationTrait::new(lot));
    components::set::<Location>(builder.path(), LocationTrait::new(lot));
    components::set::<Location>(other.path(), LocationTrait::new(lot));
    mocks::building_type(building_types::WAREHOUSE);
    Fixture { asteroid, lot, owner, tenant, builder, other }
}

fn grant_crew(f: Fixture) {
    let mut state = Whitelist::contract_state_for_testing();
    Whitelist::run(ref state, f.asteroid, permissions::USE_LOT, f.builder, f.owner, mocks::context('OWNER'));
}

fn grant_account(f: Fixture) {
    let mut state = WhitelistAccount::contract_state_for_testing();
    WhitelistAccount::run(
        ref state, f.asteroid, permissions::USE_LOT, starknet::contract_address_const::<'BUILDER'>(),
        f.owner, mocks::context('OWNER')
    );
}

fn whitelist(target: Entity, permitted: felt252, enabled: bool) {
    components::set::<WhitelistAgreement>(
        agreement_path(target, permissions::USE_LOT, permitted), WhitelistAgreementTrait::new(enabled)
    );
}

fn public(target: Entity) {
    components::set::<PublicPolicy>(policy_path(target, permissions::USE_LOT), PublicPolicyTrait::new(true));
}

fn lease(f: Fixture, end_time: u64) {
    components::set::<Unique>(use_lot_path(f.lot), Unique { unique: f.tenant.into() });
    components::set::<PrepaidAgreement>(
        agreement_path(f.lot, permissions::USE_LOT, f.tenant.into()),
        PrepaidAgreementTrait::new(1, 100, 20, 1, end_time)
    );
}

fn contract_grant(target: Entity, permitted: Entity, allowed: bool) {
    let class_hash: ClassHash = ContractPolicy::TEST_CLASS_HASH.try_into().unwrap();
    let calldata = array![if allowed { 1 } else { 0 }];
    let (address, _) = deploy_syscall(class_hash, 0, calldata.span(), false).unwrap();
    components::set::<ContractAgreement>(
        agreement_path(target, permissions::USE_LOT, permitted.into()), ContractAgreementTrait::new(address)
    );
}

fn plan(f: Fixture, caller: Entity, delegate: felt252) -> Entity {
    let mut state = ConstructionPlan::contract_state_for_testing();
    ConstructionPlan::run(ref state, building_types::WAREHOUSE, f.lot, caller, mocks::context(delegate));
    let building: Entity = components::get::<Unique>(lot_use_path(f.lot)).unwrap().unique.try_into().unwrap();
    assert(components::get::<Control>(building.path()).unwrap().controller == caller, 'wrong building controller');
    assert(components::get::<Building>(building.path()).unwrap().status == statuses::PLANNED, 'not planned');
    assert(components::get::<Location>(building.path()).unwrap().location == f.lot, 'wrong location');
    building
}

fn assert_no_tenant(f: Fixture) {
    assert(components::get::<Unique>(use_lot_path(f.lot)).is_none(), 'unexpected tenant');
}

#[test]
#[available_gas(50000000)]
fn test_asteroid_crew_grant_without_lease() {
    let f = setup();
    grant_crew(f);
    plan(f, f.builder, 'BUILDER');
    assert_no_tenant(f);
}

#[test]
#[available_gas(50000000)]
fn test_asteroid_account_grant_without_lease() {
    let f = setup();
    grant_account(f);
    plan(f, f.builder, 'BUILDER');
    assert_no_tenant(f);
}

#[test]
#[available_gas(50000000)]
fn test_lot_crew_grant_without_lease() {
    let f = setup();
    whitelist(f.lot, f.builder.into(), true);
    plan(f, f.builder, 'BUILDER');
    assert_no_tenant(f);
}

#[test]
#[available_gas(50000000)]
fn test_lot_account_grant_without_lease() {
    let f = setup();
    whitelist(f.lot, 'BUILDER', true);
    plan(f, f.builder, 'BUILDER');
    assert_no_tenant(f);
}

#[test]
#[available_gas(50000000)]
fn test_asteroid_public_grant_without_lease() {
    let f = setup();
    public(f.asteroid);
    plan(f, f.builder, 'BUILDER');
    assert_no_tenant(f);
}

#[test]
#[available_gas(50000000)]
fn test_lot_public_grant_without_lease() {
    let f = setup();
    public(f.lot);
    plan(f, f.builder, 'BUILDER');
    assert_no_tenant(f);
}

#[test]
#[available_gas(50000000)]
fn test_asteroid_contract_grant_without_lease() {
    let f = setup();
    contract_grant(f.asteroid, f.builder, true);
    plan(f, f.builder, 'BUILDER');
    assert_no_tenant(f);
}

#[test]
#[available_gas(50000000)]
fn test_lot_contract_grant_without_lease() {
    let f = setup();
    contract_grant(f.lot, f.builder, true);
    plan(f, f.builder, 'BUILDER');
    assert_no_tenant(f);
}

#[test]
#[available_gas(50000000)]
fn test_lot_prepaid_without_tenant() {
    let f = setup();
    components::set::<PrepaidAgreement>(agreement_path(f.lot, permissions::USE_LOT, f.builder.into()),
        PrepaidAgreementTrait::new(1, 100, 20, 1, 300));
    plan(f, f.builder, 'BUILDER');
    assert_no_tenant(f);
}

#[test]
#[available_gas(50000000)]
fn test_asteroid_prepaid_without_tenant() {
    let f = setup();
    components::set::<PrepaidAgreement>(agreement_path(f.asteroid, permissions::USE_LOT, f.builder.into()),
        PrepaidAgreementTrait::new(1, 100, 20, 1, 300));
    plan(f, f.builder, 'BUILDER');
    assert_no_tenant(f);
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('E2005: incorrect controller', ))]
fn test_no_permission_is_squatting() {
    let f = setup();
    plan(f, f.builder, 'BUILDER');
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('E2005: incorrect controller', ))]
fn test_revoked_crew_grant() {
    let f = setup();
    grant_crew(f);
    whitelist(f.asteroid, f.builder.into(), false);
    plan(f, f.builder, 'BUILDER');
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('E2005: incorrect controller', ))]
fn test_revoked_account_grant() {
    let f = setup();
    grant_account(f);
    whitelist(f.asteroid, 'BUILDER', false);
    plan(f, f.builder, 'BUILDER');
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('E2005: incorrect controller', ))]
fn test_grant_to_different_crew() {
    let f = setup();
    grant_crew(f);
    plan(f, f.other, 'OTHER');
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('E2005: incorrect controller', ))]
fn test_grant_to_different_account() {
    let f = setup();
    grant_account(f);
    plan(f, f.other, 'OTHER');
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('E2005: incorrect controller', ))]
fn test_grant_on_other_asteroid() {
    let f = setup();
    whitelist(EntityTrait::new(entities::ASTEROID, f.asteroid.id + 1), f.builder.into(), true);
    plan(f, f.builder, 'BUILDER');
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('E2005: incorrect controller', ))]
fn test_grant_on_other_lot() {
    let f = setup();
    whitelist(EntityTrait::from_position(f.asteroid.id, 1002), f.builder.into(), true);
    plan(f, f.builder, 'BUILDER');
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('E2005: incorrect controller', ))]
fn test_denied_contract_grant() {
    let f = setup();
    contract_grant(f.asteroid, f.builder, false);
    plan(f, f.builder, 'BUILDER');
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('E2005: incorrect controller', ))]
fn test_expired_prepaid_grant() {
    let f = setup();
    components::set::<PrepaidAgreement>(agreement_path(f.asteroid, permissions::USE_LOT, f.builder.into()),
        PrepaidAgreementTrait::new(1, 100, 20, 1, 200));
    plan(f, f.builder, 'BUILDER');
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('E2005: incorrect controller', ))]
fn test_active_tenant_blocks_crew() {
    let f = setup();
    lease(f, 300);
    grant_crew(f);
    plan(f, f.builder, 'BUILDER');
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('E2005: incorrect controller', ))]
fn test_active_tenant_blocks_account() {
    let f = setup();
    lease(f, 300);
    grant_account(f);
    plan(f, f.builder, 'BUILDER');
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('E2005: incorrect controller', ))]
fn test_active_tenant_blocks_public() {
    let f = setup();
    lease(f, 300);
    public(f.asteroid);
    plan(f, f.builder, 'BUILDER');
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('E2005: incorrect controller', ))]
fn test_active_tenant_blocks_lot_grant() {
    let f = setup();
    lease(f, 300);
    whitelist(f.lot, f.builder.into(), true);
    plan(f, f.builder, 'BUILDER');
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('E2005: incorrect controller', ))]
fn test_active_tenant_blocks_contract() {
    let f = setup();
    lease(f, 300);
    contract_grant(f.asteroid, f.builder, true);
    plan(f, f.builder, 'BUILDER');
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('E2005: incorrect controller', ))]
fn test_active_tenant_blocks_owner() {
    let f = setup();
    lease(f, 300);
    plan(f, f.owner, 'OWNER');
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('E2005: incorrect controller', ))]
fn test_lease_end_inclusive_blocks_grantee() {
    let f = setup();
    lease(f, 201);
    grant_crew(f);
    plan(f, f.builder, 'BUILDER');
}

#[test]
#[available_gas(50000000)]
fn test_authorized_tenant_retains_slot() {
    let f = setup();
    lease(f, 201);
    public(f.asteroid);
    plan(f, f.tenant, 'TENANT');
    assert(components::get::<Unique>(use_lot_path(f.lot)).unwrap().unique == f.tenant.into(), 'tenant cleared');
}

#[test]
#[available_gas(50000000)]
fn test_expired_tenant_with_direct_grant_stays_authorized() {
    let f = setup();
    lease(f, 200);
    whitelist(f.lot, f.tenant.into(), true);
    plan(f, f.tenant, 'TENANT');
    assert(components::get::<Unique>(use_lot_path(f.lot)).unwrap().unique == f.tenant.into(), 'tenant cleared');
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('E2005: incorrect controller', ))]
fn test_expired_tenant_without_grant_cannot_squat() {
    let f = setup();
    lease(f, 200);
    plan(f, f.tenant, 'TENANT');
}

#[test]
#[available_gas(50000000)]
fn test_grantee_clears_expired_tenant() {
    let f = setup();
    lease(f, 200);
    grant_crew(f);
    plan(f, f.builder, 'BUILDER');
    assert_no_tenant(f);
    assert(components::get::<PrepaidAgreement>(agreement_path(f.lot, permissions::USE_LOT, f.tenant.into())).is_some(), 'history deleted');
}

#[test]
#[available_gas(50000000)]
fn test_grantee_clears_tenant_without_agreement() {
    let f = setup();
    components::set::<Unique>(use_lot_path(f.lot), Unique { unique: f.tenant.into() });
    grant_account(f);
    plan(f, f.builder, 'BUILDER');
    assert_no_tenant(f);
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('E2005: incorrect controller', ))]
fn test_notice_period_still_blocks_grantee() {
    let f = setup();
    let mut data = PrepaidAgreementTrait::new(1, 100, 20, 1, 170);
    data.notice_time = 150;
    lease(f, 170);
    components::set::<PrepaidAgreement>(agreement_path(f.lot, permissions::USE_LOT, f.tenant.into()), data);
    testing::set_block_timestamp(170);
    grant_crew(f);
    plan(f, f.builder, 'BUILDER');
}

#[test]
#[available_gas(50000000)]
fn test_notice_elapsed_allows_grantee() {
    let f = setup();
    let mut data = PrepaidAgreementTrait::new(1, 100, 20, 1, 170);
    data.notice_time = 150;
    lease(f, 170);
    components::set::<PrepaidAgreement>(agreement_path(f.lot, permissions::USE_LOT, f.tenant.into()), data);
    testing::set_block_timestamp(171);
    grant_crew(f);
    plan(f, f.builder, 'BUILDER');
    assert_no_tenant(f);
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('E6003: lot in use', ))]
fn test_occupied_planned() {
    let f = setup();
    grant_crew(f);
    let building = plan(f, f.builder, 'BUILDER');
    let mut data = components::get::<Building>(building.path()).unwrap();
    data.status = statuses::PLANNED;
    components::set::<Building>(building.path(), data);
    plan(f, f.builder, 'BUILDER');
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('E6003: lot in use', ))]
fn test_occupied_under_construction() {
    let f = setup();
    grant_crew(f);
    let building = plan(f, f.builder, 'BUILDER');
    let mut data = components::get::<Building>(building.path()).unwrap();
    data.status = statuses::UNDER_CONSTRUCTION;
    components::set::<Building>(building.path(), data);
    plan(f, f.builder, 'BUILDER');
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('E6003: lot in use', ))]
fn test_occupied_operational() {
    let f = setup();
    grant_crew(f);
    let building = plan(f, f.builder, 'BUILDER');
    let mut data = components::get::<Building>(building.path()).unwrap();
    data.status = statuses::OPERATIONAL;
    components::set::<Building>(building.path(), data);
    plan(f, f.builder, 'BUILDER');
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('E6003: lot in use', ))]
fn test_surface_ship_blocks_planning() {
    let f = setup();
    grant_crew(f);
    components::set::<Unique>(lot_use_path(f.lot), Unique { unique: EntityTrait::new(entities::SHIP, 42).into() });
    plan(f, f.builder, 'BUILDER');
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('E4001: different asteroids', ))]
fn test_wrong_asteroid() {
    let f = setup();
    grant_crew(f);
    components::set::<Location>(f.builder.path(), LocationTrait::new(EntityTrait::from_position(mocks::adalia_prime().id, 1001)));
    plan(f, f.builder, 'BUILDER');
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('E4003: in orbit', ))]
fn test_in_orbit() {
    let f = setup();
    grant_crew(f);
    components::set::<Location>(f.builder.path(), LocationTrait::new(f.asteroid));
    plan(f, f.builder, 'BUILDER');
}

#[test]
#[available_gas(50000000)]
fn test_abandon_replan_rechecks_grant() {
    let f = setup();
    grant_crew(f);
    let building = plan(f, f.builder, 'BUILDER');
    let mut abandon = ConstructionAbandon::contract_state_for_testing();
    ConstructionAbandon::run(ref abandon, building, f.builder, mocks::context('BUILDER'));
    plan(f, f.builder, 'BUILDER');
    assert_no_tenant(f);
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('E2005: incorrect controller', ))]
fn test_revocation_after_abandon_prevents_squatting() {
    let f = setup();
    grant_crew(f);
    let building = plan(f, f.builder, 'BUILDER');
    let mut abandon = ConstructionAbandon::contract_state_for_testing();
    ConstructionAbandon::run(ref abandon, building, f.builder, mocks::context('BUILDER'));
    whitelist(f.asteroid, f.builder.into(), false);
    plan(f, f.builder, 'BUILDER');
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('in grace period', ))]
fn test_former_tenant_cannot_repossess_grantees_site() {
    let f = setup();
    lease(f, 200);
    grant_crew(f);
    let building = plan(f, f.builder, 'BUILDER');
    let mut state = RepossessBuilding::contract_state_for_testing();
    RepossessBuilding::run(ref state, building, f.tenant, mocks::context('TENANT'));
}

#[test]
#[available_gas(50000000)]
fn test_owner_account_other_crew_can_plan() {
    let f = setup();
    let crew = mocks::delegated_crew(3, 'OWNER');
    components::set::<Location>(crew.path(), LocationTrait::new(f.lot));
    plan(f, crew, 'OWNER');
    assert_no_tenant(f);
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('E2005: incorrect controller', ))]
fn test_tenant_account_other_crew_does_not_bypass_exclusivity() {
    let f = setup();
    lease(f, 300);
    let crew = mocks::delegated_crew(3, 'TENANT');
    components::set::<Location>(crew.path(), LocationTrait::new(f.lot));
    grant_crew(f);
    plan(f, crew, 'TENANT');
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('E2005: incorrect controller', ))]
fn test_active_contract_tenant_blocks_grantee() {
    let f = setup();
    components::set::<Unique>(use_lot_path(f.lot), Unique { unique: f.tenant.into() });
    contract_grant(f.lot, f.tenant, true);
    grant_crew(f);
    plan(f, f.builder, 'BUILDER');
}

#[test]
#[available_gas(50000000)]
fn test_denied_contract_tenant_is_cleared() {
    let f = setup();
    components::set::<Unique>(use_lot_path(f.lot), Unique { unique: f.tenant.into() });
    contract_grant(f.lot, f.tenant, false);
    grant_crew(f);
    plan(f, f.builder, 'BUILDER');
    assert_no_tenant(f);
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('E1021: unique not found', ))]
fn test_former_tenant_cannot_restore_grantees_site() {
    let f = setup();
    lease(f, 200);
    grant_crew(f);
    plan(f, f.builder, 'BUILDER');
    let mut state = ExtendPrepaidAgreement::contract_state_for_testing();
    ExtendPrepaidAgreement::run(
        ref state, f.lot, permissions::USE_LOT, f.tenant, 3600, f.tenant, mocks::context('TENANT')
    );
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('E2004: incorrect delegate', ))]
fn test_permission_does_not_bypass_wallet_authorization() {
    let f = setup();
    grant_crew(f);
    plan(f, f.builder, 'OTHER');
}
