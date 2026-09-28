use array::ArrayTrait;
use option::OptionTrait;
use traits::{Into, TryInto};
use starknet::{testing, ClassHash, syscalls::deploy_syscall};
use influence::components;
use influence::components::{Control, ControlTrait, Location, LocationTrait, Ship, ShipTrait,
    ShipTypeTrait, Inventory, InventoryTrait, Unique, PrepaidAgreement, PrepaidAgreementTrait,
    WhitelistAgreement, WhitelistAgreementTrait, PublicPolicy, PublicPolicyTrait,
    ContractAgreement, ContractAgreementTrait, Dock, DockTrait, Crew,
    ship_type::types as ship_types, modifier_type::types as modifier_types, station_type::types as station_types};
use influence::config::{entities, permissions};
use influence::contracts::contract_policy::ContractPolicy;
use influence::systems::agreements::helpers::{agreement_path, use_lot_path, lot_use_path};
use influence::systems::policies::helpers::policy_path;
use influence::systems::ship::undock_ship::UndockShip;
use influence::test::{helpers, mocks};
use influence::types::{Entity, EntityTrait};

#[derive(Copy, Drop)]
struct Fixture { asteroid: Entity, lot: Entity, ship: Entity, pilot: Entity, tenant: Entity, bystander: Entity }

fn setup() -> Fixture {
    testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
    helpers::init();
    mocks::constants();
    mocks::station_type(station_types::STANDARD_QUARTERS);
    mocks::modifier_type(modifier_types::HOPPER_TRANSPORT_TIME);
    mocks::modifier_type(modifier_types::FREE_TRANSPORT_DISTANCE);
    testing::set_block_timestamp(201);
    let asteroid = mocks::asteroid();
    let lot = EntityTrait::from_position(asteroid.id, 1001);
    let owner = mocks::delegated_crew(1, 'OWNER');
    let pilot = mocks::delegated_crew(2, 'PILOT');
    let tenant = mocks::delegated_crew(3, 'TENANT');
    let bystander = mocks::delegated_crew(4, 'BYSTANDER');
    components::set::<Control>(asteroid.path(), ControlTrait::new(owner));
    components::set::<Location>(pilot.path(), LocationTrait::new(lot));
    components::set::<Location>(bystander.path(), LocationTrait::new(lot));
    let ship = EntityTrait::new(entities::SHIP, 42);
    mocks::ship_type(ship_types::LIGHT_TRANSPORT);
    let config = ShipTypeTrait::by_type(ship_types::LIGHT_TRANSPORT);
    let mut data = ShipTrait::new(ship_types::LIGHT_TRANSPORT, 1);
    data.status = 1;
    components::set::<Ship>(ship.path(), data);
    components::set::<Control>(ship.path(), ControlTrait::new(pilot));
    components::set::<Location>(ship.path(), LocationTrait::new(lot));
    components::set::<Unique>(lot_use_path(lot), Unique { unique: ship.into() });
    components::set::<Inventory>(array![ship.into(), config.propellant_slot.into()].span(), InventoryTrait::new(config.propellant_inventory_type));
    components::set::<Inventory>(array![ship.into(), config.cargo_slot.into()].span(), InventoryTrait::new(config.cargo_inventory_type));
    Fixture { asteroid, lot, ship, pilot, tenant, bystander }
}

fn grant(target: Entity, permitted: felt252, permission: u64, enabled: bool) {
    components::set::<WhitelistAgreement>(agreement_path(target, permission, permitted), WhitelistAgreementTrait::new(enabled));
}
fn lease(f: Fixture, tenant: Entity, end: u64) {
    components::set::<Unique>(use_lot_path(f.lot), Unique { unique: tenant.into() });
    components::set::<PrepaidAgreement>(agreement_path(f.lot, permissions::USE_LOT, tenant.into()), PrepaidAgreementTrait::new(1, 100, 20, 1, end));
}
fn policy(target: Entity, crew: Entity, approved: bool) {
    let hash: ClassHash = ContractPolicy::TEST_CLASS_HASH.try_into().unwrap();
    let (address, _) = deploy_syscall(hash, 0, array![if approved { 1 } else { 0 }].span(), false).unwrap();
    components::set::<ContractAgreement>(agreement_path(target, permissions::USE_LOT, crew.into()), ContractAgreementTrait::new(address));
}
fn evict(f: Fixture) {
    let tenant_before = components::get::<Unique>(use_lot_path(f.lot));
    let mut state = UndockShip::contract_state_for_testing();
    UndockShip::run(ref state, f.ship, false, f.bystander, mocks::context('BYSTANDER'));
    assert(components::get::<Location>(f.ship.path()).unwrap().location == f.asteroid, 'not moved to orbit');
    assert(components::get::<Control>(f.ship.path()).unwrap().controller == f.pilot, 'ownership changed');
    assert(components::get::<Unique>(lot_use_path(f.lot)).is_none(), 'occupancy retained');
    if let Option::Some(tenant) = tenant_before {
        assert(components::get::<Unique>(use_lot_path(f.lot)).unwrap().unique == tenant.unique, 'tenancy changed');
    }
}
fn dock(f: Fixture) -> Entity {
    let building = EntityTrait::new(entities::BUILDING, 42);
    components::set::<Location>(building.path(), LocationTrait::new(f.lot));
    components::set::<Location>(f.ship.path(), LocationTrait::new(building));
    components::set::<Unique>(lot_use_path(f.lot), Unique { unique: 0 });
    mocks::dock_type(1);
    let mut data = DockTrait::new(1);
    data.docked_ships = 1;
    components::set::<Dock>(building.path(), data);
    building
}

#[test]
#[available_gas(50000000)]
fn test_bystander_clears_unprotected_ship() {
    let f = setup();
    
    evict(f);
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('E2002: access denied', ))]
fn test_asteroid_crew_protected() {
    let f = setup();
    grant(f.asteroid, f.pilot.into(), permissions::USE_LOT, true);
    evict(f);
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('E2002: access denied', ))]
fn test_asteroid_account_protected() {
    let f = setup();
    grant(f.asteroid, 'PILOT', permissions::USE_LOT, true);
    evict(f);
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('E2002: access denied', ))]
fn test_lot_grant_protected() {
    let f = setup();
    grant(f.lot, f.pilot.into(), permissions::USE_LOT, true);
    evict(f);
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('E2002: access denied', ))]
fn test_public_asteroid_protected() {
    let f = setup();
    components::set::<PublicPolicy>(policy_path(f.asteroid, permissions::USE_LOT), PublicPolicyTrait::new(true));
    evict(f);
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('E2002: access denied', ))]
fn test_asteroid_owner_protected() {
    let f = setup();
    components::set::<Control>(f.asteroid.path(), ControlTrait::new(f.pilot));
    evict(f);
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('E2002: access denied', ))]
fn test_active_tenant_protected() {
    let f = setup();
    lease(f, f.pilot, 300);
    evict(f);
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('E2002: access denied', ))]
fn test_lease_boundary_protected() {
    let f = setup();
    lease(f, f.pilot, 201);
    evict(f);
}

#[test]
#[available_gas(50000000)]
fn test_expired_tenant_evictable() {
    let f = setup();
    lease(f, f.pilot, 200);
    evict(f);
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('E2002: access denied', ))]
fn test_expired_tenant_broad_grant_protected() {
    let f = setup();
    lease(f, f.pilot, 200);
    grant(f.asteroid, f.pilot.into(), permissions::USE_LOT, true);
    evict(f);
}

#[test]
#[available_gas(50000000)]
fn test_active_tenant_overrides_broad_grant() {
    let f = setup();
    lease(f, f.tenant, 300);
    grant(f.asteroid, f.pilot.into(), permissions::USE_LOT, true);
    evict(f);
}

#[test]
#[available_gas(50000000)]
fn test_active_tenant_overrides_lot_grant() {
    let f = setup();
    lease(f, f.tenant, 300);
    grant(f.lot, f.pilot.into(), permissions::USE_LOT, true);
    evict(f);
}

#[test]
#[available_gas(50000000)]
fn test_active_tenant_overrides_owner() {
    let f = setup();
    lease(f, f.tenant, 300);
    components::set::<Control>(f.asteroid.path(), ControlTrait::new(f.pilot));
    evict(f);
}

#[test]
#[available_gas(50000000)]
fn test_active_tenant_overrides_public() {
    let f = setup();
    lease(f, f.tenant, 300);
    components::set::<PublicPolicy>(policy_path(f.asteroid, permissions::USE_LOT), PublicPolicyTrait::new(true));
    evict(f);
}

#[test]
#[available_gas(50000000)]
fn test_revoked_grant_evictable() {
    let f = setup();
    grant(f.asteroid, f.pilot.into(), permissions::USE_LOT, true);
    grant(f.asteroid, f.pilot.into(), permissions::USE_LOT, false);
    evict(f);
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('E2002: access denied', ))]
fn test_approved_contract_protected() {
    let f = setup();
    policy(f.asteroid, f.pilot, true);
    evict(f);
}

#[test]
#[available_gas(50000000)]
fn test_denied_contract_evictable() {
    let f = setup();
    policy(f.asteroid, f.pilot, false);
    evict(f);
}

#[test]
#[available_gas(50000000)]
fn test_active_contract_tenant_overrides_grant() {
    let f = setup();
    lease(f, f.tenant, 200);
    policy(f.lot, f.tenant, true);
    grant(f.asteroid, f.pilot.into(), permissions::USE_LOT, true);
    evict(f);
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('E2002: access denied', ))]
fn test_notice_boundary_protected() {
    let f = setup();
    lease(f, f.pilot, 170);
    let path = agreement_path(f.lot, permissions::USE_LOT, f.pilot.into());
    let mut data = components::get::<PrepaidAgreement>(path).unwrap();
    data.notice_time = 181;
    components::set::<PrepaidAgreement>(path, data);
    evict(f);
}

#[test]
#[available_gas(50000000)]
fn test_absent_busy_pilot_does_not_block_cleanup() {
    let f = setup();
    let mut data = components::get::<Crew>(f.pilot.path()).unwrap();
    data.ready_at = 999999;
    components::set::<Crew>(f.pilot.path(), data);
    let mut ship = components::get::<Ship>(f.ship.path()).unwrap();
    ship.ready_at = 999999;
    components::set::<Ship>(f.ship.path(), ship);
    evict(f);
}

#[test]
#[available_gas(50000000)]
fn test_dock_bystander_cleanup() {
    let f = setup();
    let building = dock(f);
    evict(f);
    assert(components::get::<Dock>(building.path()).unwrap().docked_ships == 0, 'berth not released');
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('E2002: access denied', ))]
fn test_dock_crew_protected() {
    let f = setup();
    let building = dock(f);
    grant(building, f.pilot.into(), permissions::DOCK_SHIP, true);
    evict(f);
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('E2002: access denied', ))]
fn test_dock_ship_protected() {
    let f = setup();
    let building = dock(f);
    grant(building, f.ship.into(), permissions::DOCK_SHIP, true);
    evict(f);
}

#[test]
#[available_gas(50000000)]
fn test_broad_lot_grant_does_not_protect_docked_ship() {
    let f = setup();
    dock(f);
    grant(f.asteroid, f.pilot.into(), permissions::USE_LOT, true);
    evict(f);
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('E2004: incorrect delegate', ))]
fn test_wrong_wallet() {
    let f = setup();
    
    let mut state = UndockShip::contract_state_for_testing();
    UndockShip::run(ref state, f.ship, false, f.bystander, mocks::context('PILOT'));
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('eviction must be unpowered', ))]
fn test_powered_eviction() {
    let f = setup();
    
    let mut state = UndockShip::contract_state_for_testing();
    UndockShip::run(ref state, f.ship, true, f.bystander, mocks::context('BYSTANDER'));
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('E4001: different asteroids', ))]
fn test_wrong_asteroid() {
    let f = setup();
    components::set::<Location>(f.bystander.path(), LocationTrait::new(EntityTrait::from_position(mocks::adalia_prime().id, 1001)));
    let mut state = UndockShip::contract_state_for_testing();
    UndockShip::run(ref state, f.ship, false, f.bystander, mocks::context('BYSTANDER'));
}

#[test]
#[available_gas(50000000)]
fn test_self_launch_does_not_require_lot_permission() {
    let f = setup();
    lease(f, f.tenant, 300);
    let mut state = UndockShip::contract_state_for_testing();
    UndockShip::run(ref state, f.ship, false, f.pilot, mocks::context('PILOT'));
    assert(components::get::<Location>(f.ship.path()).unwrap().location == f.asteroid, 'self launch failed');
}

#[test]
#[available_gas(50000000)]
fn test_other_crew_on_tenant_wallet_is_not_protected() {
    let f = setup();
    lease(f, f.tenant, 300);
    let mut pilot = components::get::<Crew>(f.pilot.path()).unwrap();
    pilot.delegated_to = starknet::contract_address_const::<'TENANT'>();
    components::set::<Crew>(f.pilot.path(), pilot);
    grant(f.asteroid, 'TENANT', permissions::USE_LOT, true);
    evict(f);
}
