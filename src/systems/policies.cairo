mod assign_contract;
mod assign_prepaid;
mod assign_prepaid_merkle;
mod assign_public;
mod remove_contract;
mod remove_prepaid;
mod remove_prepaid_merkle;
mod remove_public;

use assign_contract::AssignContractPolicy;
use assign_prepaid::AssignPrepaidPolicy;
use assign_prepaid_merkle::AssignPrepaidMerklePolicy;
use assign_public::AssignPublicPolicy;
use remove_contract::RemoveContractPolicy;
use remove_prepaid::RemovePrepaidPolicy;
use remove_prepaid_merkle::RemovePrepaidMerklePolicy;
use remove_public::RemovePublicPolicy;

mod helpers {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use traits::Into;

    use influence::components;
    use influence::config::{entities, errors, permissions};
    use influence::components::{ContractPolicy, PrepaidPolicy, PrepaidMerklePolicy, PublicPolicy};
    use influence::types::{Entity, EntityTrait, SpanHashTrait};

    fn policy_path(target: Entity, permission: u64) -> Span<felt252> {
        if target.label == entities::ASTEROID {
            assert(permission == permissions::USE_LOT, 'invalid permission');
        } else if target.label == entities::LOT {
            assert(permission == permissions::USE_LOT, 'invalid permission');
        } else if target.label == entities::BUILDING {
            assert(
                permission == permissions::RUN_PROCESS ||
                permission == permissions::ADD_PRODUCTS ||
                permission == permissions::REMOVE_PRODUCTS ||
                permission == permissions::STATION_CREW ||
                permission == permissions::RECRUIT_CREWMATE ||
                permission == permissions::DOCK_SHIP ||
                permission == permissions::BUY ||
                permission == permissions::SELL ||
                permission == permissions::LIMIT_BUY ||
                permission == permissions::LIMIT_SELL ||
                permission == permissions::EXTRACT_RESOURCES ||
                permission == permissions::ASSEMBLE_SHIP,
                'invalid permission'
            );
        } else if target.label == entities::SHIP {
            assert(
                permission == permissions::ADD_PRODUCTS ||
                permission == permissions::REMOVE_PRODUCTS ||
                permission == permissions::STATION_CREW,
                'invalid permission'
            );
        } else if target.label == entities::DEPOSIT {
            assert(permission == permissions::USE_DEPOSIT, 'invalid permission');
        } else {
            assert(false, 'invalid permission');
        }

        let mut path: Array<felt252> = Default::default();
        path.append(target.into());
        path.append(permission.into());
        return path.span();
    }

    fn assert_no_current_policy(target: Entity, keys: Span<felt252>) {
        // Lot / USE_LOT policies must be set on the asteroid
        assert(target.label != entities::LOT, errors::INCORRECT_ENTITY_TYPE);

        assert(components::get::<PublicPolicy>(keys).is_none(), 'public policy set');
        assert(components::get::<PrepaidPolicy>(keys).is_none(), 'prepaid policy set');
        assert(components::get::<PrepaidMerklePolicy>(keys).is_none(), 'prepaid merkle policy set');
        assert(components::get::<ContractPolicy>(keys).is_none(), 'contract policy set');
    }
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use traits::Into;

    use influence::config::{entities, permissions};
    use influence::types::array::SpanHashTrait;
    use influence::types::entity::{Entity, EntityTrait};
    use influence::types::context::Context;
    use influence::test::{helpers, mocks};

    use influence::components;
    use influence::components::crew::{Crew, CrewTrait};
    use influence::components::{Control, ControlTrait, ContractPolicy, ContractPolicyTrait, Location, LocationTrait,
        PrepaidPolicy, PrepaidPolicyTrait, PrepaidMerklePolicy, PrepaidMerklePolicyTrait, PublicPolicy,
        PublicPolicyTrait};

    use super::{
        AssignContractPolicy,
        AssignPrepaidPolicy,
        AssignPrepaidMerklePolicy,
        AssignPublicPolicy,
        RemovePublicPolicy,
        RemovePrepaidPolicy,
        RemovePrepaidMerklePolicy,
        RemoveContractPolicy
    };

    #[test]
    #[available_gas(8000000)]
    fn test_public_policy() {
        let asteroid = mocks::asteroid();
        let entity = EntityTrait::new(entities::BUILDING, 1);
        let permission = permissions::ADD_PRODUCTS;
        let caller_crew = mocks::delegated_crew(3, 'PLAYER');

        // Delegate and set caller to owner
        components::set::<Control>(entity.path(), Control { controller: caller_crew });
        components::set::<Location>(entity.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1)));
        components::set::<Location>(caller_crew.path(), LocationTrait::new(asteroid));

        let mut state = AssignPublicPolicy::contract_state_for_testing();
        AssignPublicPolicy::run(
            ref state,
            entity,
            permission,
            caller_crew,
            mocks::context('PLAYER')
        );

        let keys = super::helpers::policy_path(entity, permission);
        assert(components::get::<PublicPolicy>(keys).is_some(), 'assignment not set');

        let mut state = RemovePublicPolicy::contract_state_for_testing();
        RemovePublicPolicy::run(ref state, entity, permission, caller_crew, mocks::context('PLAYER'));
        assert(components::get::<PublicPolicy>(keys).is_none(), 'assignment not removed');
    }

    #[test]
    #[should_panic(expected: ('public policy set', ))]
    #[available_gas(7000000)]
    fn test_already_set() {
        let asteroid = mocks::asteroid();
        let entity = EntityTrait::new(entities::BUILDING, 1);
        let permission = permissions::ADD_PRODUCTS;
        let caller_crew = mocks::delegated_crew(3, 'PLAYER');

        // Delegate and set caller to owner
        components::set::<Control>(entity.path(), Control { controller: caller_crew });
        components::set::<Location>(entity.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1)));
        components::set::<Location>(caller_crew.path(), LocationTrait::new(asteroid));

        let mut state = AssignPublicPolicy::contract_state_for_testing();
        AssignPublicPolicy::run(ref state, entity, permission, caller_crew, mocks::context('PLAYER'));

        let mut state = AssignContractPolicy::contract_state_for_testing();
        AssignContractPolicy::run(
            ref state, entity, permission, starknet::contract_address_const::<5678>(), caller_crew, mocks::context('PLAYER')
        );
    }

    #[test]
    #[available_gas(8000000)]
    fn test_prepaid_policy() {
        mocks::constants();
        let asteroid = mocks::asteroid();
        let entity = EntityTrait::new(entities::BUILDING, 1);
        let permission = permissions::ADD_PRODUCTS;
        let caller_crew = mocks::delegated_crew(3, 'PLAYER');

        // Delegate and set caller to owner
        components::set::<Control>(entity.path(), Control { controller: caller_crew });
        components::set::<Location>(entity.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1)));
        components::set::<Location>(caller_crew.path(), LocationTrait::new(asteroid));

        let mut state = AssignPrepaidPolicy::contract_state_for_testing();
        AssignPrepaidPolicy::run(
            ref state, entity, permission, 100000, 20000, 30000, caller_crew, mocks::context('PLAYER')
        );

        let keys = super::helpers::policy_path(entity, permission);
        assert(components::get::<PrepaidPolicy>(keys).is_some(), 'assignment not set');

        let mut state = RemovePrepaidPolicy::contract_state_for_testing();
        RemovePrepaidPolicy::run(ref state, entity, permission, caller_crew, mocks::context('PLAYER'));
        assert(components::get::<PrepaidPolicy>(keys).is_none(), 'assignment not removed');
    }

    #[test]
    #[should_panic(expected: ('policy too long', ))]
    #[available_gas(6000000)]
    fn test_prepaid_policy_too_long() {
        let asteroid = mocks::asteroid();
        let entity = EntityTrait::new(entities::BUILDING, 1);
        let permission = permissions::ADD_PRODUCTS;
        let caller_crew = mocks::delegated_crew(3, 'PLAYER');

        // Delegate and set caller to owner
        components::set::<Control>(entity.path(), ControlTrait::new(caller_crew));
        components::set::<Location>(entity.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1)));
        components::set::<Location>(caller_crew.path(), LocationTrait::new(asteroid));

        let mut state = AssignPrepaidPolicy::contract_state_for_testing();
        AssignPrepaidPolicy::run(
            ref state, entity, permission, 100000, 200 * 86400, 200 * 86400, caller_crew, mocks::context('PLAYER')
        );
    }

    #[test]
    #[available_gas(8000000)]
    fn test_prepaid_merkle_policy() {
        mocks::constants();
        let asteroid = mocks::asteroid();
        let entity = EntityTrait::new(entities::BUILDING, 1);
        let permission = permissions::ADD_PRODUCTS;
        let caller_crew = mocks::delegated_crew(3, 'PLAYER');

        // Delegate and set caller to owner
        components::set::<Control>(entity.path(), Control { controller: caller_crew });
        components::set::<Location>(entity.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1)));
        components::set::<Location>(caller_crew.path(), LocationTrait::new(asteroid));

        let mut state = AssignPrepaidMerklePolicy::contract_state_for_testing();
        let merkle_root = 0x123456789abcdef;
        AssignPrepaidMerklePolicy::run(
            ref state, entity, permission, 100000, 20000, 30000, merkle_root, caller_crew, mocks::context('PLAYER')
        );

        let prepaid_path = super::helpers::policy_path(entity, permission);
        assert(components::get::<PrepaidMerklePolicy>(prepaid_path).is_some(), 'assignment not set');

        let mut state = RemovePrepaidMerklePolicy::contract_state_for_testing();
        RemovePrepaidMerklePolicy::run(ref state, entity, permission, caller_crew, mocks::context('PLAYER'));
        assert(components::get::<PrepaidMerklePolicy>(prepaid_path).is_none(), 'assignment not removed');
    }

    #[test]
    #[available_gas(8000000)]
    fn test_contract_policy() {
        let asteroid = mocks::asteroid();
        let entity = EntityTrait::new(entities::BUILDING, 1);
        let permission = permissions::ADD_PRODUCTS;
        let caller_crew = mocks::delegated_crew(3, 'PLAYER');

        // Delegate and set caller to owner
        components::set::<Control>(entity.path(), Control { controller: caller_crew });
        components::set::<Location>(entity.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1)));
        components::set::<Location>(caller_crew.path(), LocationTrait::new(asteroid));

        let mut state = AssignContractPolicy::contract_state_for_testing();
        let contract_address = starknet::contract_address_const::<5678>();
        AssignContractPolicy::run(
            ref state, entity, permission, contract_address, caller_crew, mocks::context('PLAYER')
        );

        let keys = super::helpers::policy_path(entity, permission);
        assert(components::get::<ContractPolicy>(keys).is_some(), 'assignment not set');

        let mut state = RemoveContractPolicy::contract_state_for_testing();
        RemoveContractPolicy::run(ref state, entity, permission, caller_crew, mocks::context('PLAYER'));
        assert(components::get::<ContractPolicy>(keys).is_none(), 'assignment not removed');
    }
}
