use array::{Array, ArrayTrait, SpanTrait};
use cmp::max;
use clone::Clone;
use option::OptionTrait;
use starknet::ContractAddress;
use traits::{Into, TryInto};

use influence::components;
use influence::components::{ContractAgreement, ContractAgreementTrait, PrepaidAgreement, PrepaidAgreementTrait,
    WhitelistAgreement, WhitelistAgreementTrait, Control, ControlTrait, Crew, CrewTrait,
    Location, LocationTrait, PrepaidPolicy, PrepaidPolicyTrait, PublicPolicy, PublicPolicyTrait};
use influence::config::{entities, errors};
use influence::interfaces::contract_policy::{IContractPolicyDispatcher, IContractPolicyDispatcherTrait};
use influence::systems::{agreements::helpers::agreement_path, policies::helpers::policy_path};
use influence::types::entity::{Entity, EntityTrait};

// Resolves the controller of an entity
fn controller_of(entity: Entity) -> Option<Entity> {
    // A crew controls itself
    if entity.label == entities::CREW {
        return Option::Some(entity);
    }

    let controller = components::get::<Control>(entity.path());
    if controller.is_some() {
        return Option::Some(controller.unwrap().controller);
    }

    return Option::None(());
}

// Assert that the permitted entity (usually a crew) controls the target
fn assert_controls(permitted: Entity, target: Entity) {
    assert(controls(permitted, target), errors::UNCONTROLLED);
}

// Check if the permitted entity (usually a crew) controls the target
fn controls(permitted: Entity, target: Entity) -> bool {
    // A crew controls itself
    if permitted == target { return true; }

    // Get information about permitted entity
    let permitted_controller = controller_of(permitted).unwrap();
    let permitted_delegate = components::get::<Crew>(permitted_controller.path())
        .expect(errors::CREW_NOT_FOUND).delegated_to;

    let maybe_target_controller = controller_of(target);
    if maybe_target_controller.is_some() {
        let target_controller = maybe_target_controller.unwrap();
        if permitted_controller == target_controller { return true; }

        let target_delegate = components::get::<Crew>(target_controller.path())
            .expect(errors::CREW_NOT_FOUND).delegated_to;

        // Check if the target controller and permitted entity have the same delegate
        if permitted_delegate == target_delegate { return true; }
    }

    return false;
}

fn assert_can(permitted: Entity, entity: Entity, permission: u64) {
    assert(can(permitted, entity, permission), errors::ACCESS_DENIED);
}

fn can(permitted: Entity, target: Entity, permission: u64) -> bool {
    // Easiest to check public policy first
    if components::get::<PublicPolicy>(policy_path(target, permission)).is_some() { return true; }

    // Always allow if controller
    if controls(permitted, target) { return true; }

    // If a whitelist agreement is present return true
    let agreement_path = agreement_path(target, permission, permitted.into());
    if components::get::<WhitelistAgreement>(agreement_path).is_some() { return true; }

    // Check if the account is whitelisted instead
    let permitted_controller = controller_of(permitted).unwrap();
    let permitted_delegate = components::get::<Crew>(permitted_controller.path())
        .expect(errors::CREW_NOT_FOUND).delegated_to;
    let account_agreement_path = agreement_path(target, permission, permitted_delegate.into());
    if components::get::<WhitelistAgreement>(account_agreement_path).is_some() { return true; }

    // If a prepaid agreement is set and un-expired return true
    match components::get::<PrepaidAgreement>(agreement_path) {
        Option::Some(prepaid_data) => {
            let now = starknet::info::get_block_timestamp();
            let invalid_time = max(prepaid_data.end_time, prepaid_data.notice_time + prepaid_data.notice_period);
            if now <= invalid_time { return true; }
        },
        Option::None(_) => ()
    };

    // If a contract agreement is in place, call out to check the contract
    let _contract_agreement = components::get::<ContractAgreement>(agreement_path);
    if _contract_agreement.is_some() {
        let contract_agreement = _contract_agreement.unwrap();
        let policy = IContractPolicyDispatcher { contract_address: contract_agreement.address };
        return policy.can(target, permission, permitted);
    }

    return false;
}

fn assert_can_until(permitted: Entity, target: Entity, permission: u64, until: u64) {
    assert(can_until(permitted, target, permission, until), errors::ACCESS_DENIED);
}

fn can_until(permitted: Entity, target: Entity, permission: u64, until: u64) -> bool {
    // Easiest to check public policy first
    if components::get::<PublicPolicy>(policy_path(target, permission)).is_some() { return true; }

    // Always allow if controller
    if controls(permitted, target) { return true; }

    // If a whitelist agreement is present return true
    let agreement_path = agreement_path(target, permission, permitted.into());
    if components::get::<WhitelistAgreement>(agreement_path).is_some() { return true; }

    // Check if the account is whitelisted instead
    let permitted_controller = controller_of(permitted).unwrap();
    let permitted_delegate = components::get::<Crew>(permitted_controller.path())
        .expect(errors::CREW_NOT_FOUND).delegated_to;
    let account_agreement_path = agreement_path(target, permission, permitted_delegate.into());
    if components::get::<WhitelistAgreement>(account_agreement_path).is_some() { return true; }

    // If a contract agreement is in place, call out to check the contract
    let _contract_agreement = components::get::<ContractAgreement>(agreement_path);
    if _contract_agreement.is_some() {
        let contract_agreement = _contract_agreement.unwrap();
        let policy = IContractPolicyDispatcher { contract_address: contract_agreement.address };
        return policy.can(target, permission, permitted);
    }

    // If a prepaid agreement is set and un-expired return true
    match components::get::<PrepaidAgreement>(agreement_path) {
        Option::Some(prepaid_data) => {
            let now = starknet::info::get_block_timestamp();
            let invalid_time = max(prepaid_data.end_time, prepaid_data.notice_time + prepaid_data.notice_period);
            if until <= invalid_time { return true; }
        },
        Option::None(_) => ()
    };

    return false;
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use array::{Array, ArrayTrait, SpanTrait};
    use clone::Clone;
    use option::OptionTrait;
    use result::ResultTrait;
    use starknet::{ClassHash, ContractAddress, deploy_syscall};
    use traits::{Into, TryInto};

    use influence::{config, config::{entities, errors, permissions}};
    use influence::components;
    use influence::components::{ContractAgreement, ContractAgreementTrait, PrepaidAgreement, PrepaidAgreementTrait,
        WhitelistAgreement, WhitelistAgreementTrait, Control, ControlTrait, Crew, CrewTrait,
        Location, LocationTrait, PrepaidPolicy, PrepaidPolicyTrait, PublicPolicy, PublicPolicyTrait};
    use influence::contracts::contract_policy::ContractPolicy;
    use influence::systems::agreements::helpers::agreement_path;
    use influence::types::entity::{Entity, EntityTrait};
    use influence::test::{helpers, mocks};

    #[test]
    #[available_gas(1000000)]
    fn test_controller_of() {
        let building = EntityTrait::new(entities::BUILDING, 1);
        let crew = EntityTrait::new(entities::CREW, 3);

        components::set::<Control>(building.path(), ControlTrait::new(crew));

        assert(super::controller_of(building).unwrap() == crew, 'wrong controller');
        assert(super::controller_of(crew).unwrap() == crew, 'wrong controller');
    }

    #[test]
    #[available_gas(10000000)]
    fn test_whitelist_account() {
        let building = EntityTrait::new(entities::BUILDING, 1);
        let other_crew = mocks::delegated_crew(2, 'OTHER');
        components::set::<Control>(building.path(), ControlTrait::new(other_crew));

        let crew = mocks::delegated_crew(3, 'PLAYER');
        assert(!super::can(crew, building, permissions::DOCK_SHIP), 'should not be allowed');

        components::set::<WhitelistAgreement>(
            agreement_path(building, permissions::DOCK_SHIP, 'PLAYER'), WhitelistAgreementTrait::new(true)
        );

        assert(super::can(crew, building, permissions::DOCK_SHIP), 'should be allowed');
    }

    #[test]
    #[available_gas(20000000)]
    fn test_can_control() {
        let ship = EntityTrait::new(entities::SHIP, 1);
        let asteroid = influence::test::mocks::asteroid();
        let lot = EntityTrait::from_position(asteroid.id, 69);
        let spaceport = EntityTrait::new(entities::BUILDING, 2);
        let crew = mocks::delegated_crew(3, 'PLAYER');
        let tenant = mocks::delegated_crew(4, 'TENANT');

        components::set::<Control>(asteroid.path(), ControlTrait::new(crew));
        components::set::<Control>(ship.path(), ControlTrait::new(crew));
        components::set::<Control>(lot.path(), ControlTrait::new(tenant));

        components::set::<Location>(spaceport.path(), LocationTrait::new(lot));
        components::set::<Location>(ship.path(), LocationTrait::new(spaceport));

        assert(super::can(crew, ship, 5), 'access to ship');
        assert(!super::can(crew, lot, 1), 'no access to lot');
        assert(super::can(crew, asteroid, 1), 'access to asteroid');
    }

    #[test]
    #[available_gas(11000000)]
    fn test_contract_agreement() {
        helpers::init();

        // Deploy contract policies
        let class_hash: ClassHash = ContractPolicy::TEST_CLASS_HASH.try_into().unwrap();
        let mut calldata = array![1];
        let (addressTrue, _) = deploy_syscall(class_hash, 0, calldata.span(), false).unwrap();
        calldata = array![0];
        let (addressFalse, _) = deploy_syscall(class_hash, 0, calldata.span(), false).unwrap();

        // Setup entities
        let owner_crew = mocks::delegated_crew(1, 'PLAYER');
        let permitted_crew = mocks::delegated_crew(2, 'PERMITTED');
        let spaceport = EntityTrait::new(entities::BUILDING, 1);
        components::set::<Control>(spaceport.path(), ControlTrait::new(owner_crew));

        let agreement_path = agreement_path(spaceport, permissions::DOCK_SHIP, permitted_crew.into());

        // Test allowed
        components::set::<ContractAgreement>(agreement_path, ContractAgreementTrait::new(addressTrue));
        assert(super::can(permitted_crew, spaceport, permissions::DOCK_SHIP), 'not allowed');

        // Test not allowed
        components::set::<ContractAgreement>(agreement_path, ContractAgreementTrait::new(addressFalse));
        assert(!super::can(permitted_crew, spaceport, permissions::DOCK_SHIP), 'allowed');
    }

    #[test]
    #[available_gas(15000000)]
    fn test_prepaid_agreement() {
        let building = EntityTrait::new(entities::BUILDING, 1);
        let other_crew = mocks::delegated_crew(2, 'OTHER');
        components::set::<Control>(building.path(), ControlTrait::new(other_crew));

        let crew = mocks::delegated_crew(3, 'PLAYER');
        assert(!super::can(crew, building, permissions::RUN_PROCESS), 'should not be allowed');

        starknet::testing::set_block_timestamp(10000);
        let now = starknet::get_block_timestamp();
        components::set::<PrepaidAgreement>(
            agreement_path(building, permissions::RUN_PROCESS, crew.into()),
            PrepaidAgreementTrait::new(1000, 3600, 3600, now, now + 3600)
        );

        assert(super::can_until(crew, building, permissions::RUN_PROCESS, 13599), 'should be allowed');
        assert(!super::can_until(crew, building, permissions::RUN_PROCESS, 13601), 'should not be allowed');
    }
}
