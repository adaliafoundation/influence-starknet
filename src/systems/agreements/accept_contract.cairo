#[starknet::contract]
mod AcceptContractAgreement {
    use array::{Array, ArrayTrait};
    use option::OptionTrait;
    use starknet::{contract_address_const, ContractAddress};
    use traits::{Into, TryInto};

    use influence::{components, contracts};
    use influence::common::crew::CrewDetailsTrait;
    use influence::components::{Control, ControlTrait, ContractPolicy, ContractPolicyTrait,
        ContractAgreement, ContractAgreementTrait, Unique};
    use influence::config::{entities, errors, permissions};
    use influence::contracts::sway::{ISwayDispatcher, ISwayDispatcherTrait};
    use influence::interfaces::contract_policy::{IContractPolicyDispatcher, IContractPolicyDispatcherTrait};
    use influence::systems::{agreements::helpers::agreement_path, policies::helpers::policy_path};
    use influence::types::{ArrayHashTrait, Context, Entity, EntityTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct ContractAgreementAccepted {
        target: Entity,
        permission: u64,
        permitted: Entity,
        contract: ContractAddress,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        ContractAgreementAccepted: ContractAgreementAccepted
    }

    #[external(v0)]
    fn run(
        ref self: ContractState,
        target: Entity, // the target entity the permitted will get permission to act on
        permission: u64, // the permission being granted
        permitted: Entity, // the entity gaining the permission
        caller_crew: Entity,
        context: Context
    ) {
        // Check that crew is delegated, and ready
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_delegated_to(context.caller);

        // Check for current policy
        let mut controller_crew = EntityTrait::new(entities::CREW, 0);
        let (target_ast, _) = target.to_position();
        let mut asteroid = EntityTrait::new(entities::ASTEROID, target_ast);
        let mut contract_path: Span<felt252> = Default::default().span();

        if target.label == entities::LOT {
            assert(permission == permissions::USE_LOT, 'invalid permission');

            // Lot policies are all associated to the asteroid
            contract_path = policy_path(asteroid, permission);
            controller_crew = components::get::<Control>(asteroid.path()).expect(errors::CONTROL_NOT_FOUND).controller;

            // Check that the lot is not already used by the asteroid controller
            let mut lot_use_path: Array<felt252> = Default::default();
            lot_use_path.append('LotUse');
            lot_use_path.append(target.into());

            match components::get::<Unique>(lot_use_path.span()) {
                Option::Some(unique_data) => {
                    let lot_use = unique_data.unique.try_into().unwrap();
                    assert(!controller_crew.controls(lot_use), 'lot controlled by asteroid');
                },
                Option::None(_) => ()
            };

            // Ensure use lot agreements are unique / you can't lease over the top of someone else's lease
            let mut unique_path: Array<felt252> = Default::default();
            unique_path.append('UseLot');
            unique_path.append(target.into());

            match components::get::<Unique>(unique_path.span()) {
                Option::Some(unique_data) => {
                    let using_crew: Entity = unique_data.unique.try_into().unwrap();
                    assert(!using_crew.can(target, permissions::USE_LOT), 'lot already leased');
                },
                Option::None(_) => ()
            };

            // Update unique with new lease permitted crew
            components::set::<Unique>(unique_path.span(), Unique { unique: permitted.into() });
        } else {
            contract_path = policy_path(target, permission);
            controller_crew = components::get::<Control>(target.path()).expect(errors::CONTROL_NOT_FOUND).controller;
        }

        let policy_data = components::get::<ContractPolicy>(contract_path).expect(errors::CONTRACT_POLICY_NOT_FOUND);

        // Call out to contract
        let accepted = IContractPolicyDispatcher { contract_address: policy_data.address }
            .accept(target, permission, permitted);

        assert(accepted, 'contract policy rejected');

        // Create agreement
        let path = agreement_path(target, permission, permitted.into());
        components::set::<ContractAgreement>(path, ContractAgreement { address: policy_data.address });

        self.emit(ContractAgreementAccepted {
            target: target,
            permission: permission,
            permitted: permitted,
            contract: policy_data.address,
            caller_crew: caller_crew,
            caller: context.caller
        });
    }
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use result::ResultTrait;
    use traits::{Into, TryInto};
    use starknet::{ClassHash, deploy_syscall, testing};

    use influence::components;
    use influence::components::{Control, ControlTrait, Crew, CrewTrait, Location, LocationTrait, ContractAgreement,
        ContractAgreementTrait, ContractPolicy};
    use influence::config::{entities, permissions};
    use influence::contracts::contract_policy::ContractPolicy as ContractPolicyContract;
    use influence::interfaces::contract_policy::{IContractPolicyDispatcher, IContractPolicyDispatcherTrait};
    use influence::systems::{agreements::helpers::agreement_path, policies::helpers::policy_path};
    use influence::types::{ArrayHashTrait, EntityTrait};
    use influence::test::{helpers, mocks};

    use super::AcceptContractAgreement;

    #[test]
    #[available_gas(11000000)]
    fn test_accept_contract() {
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        helpers::init();
        let asteroid = mocks::adalia_prime();
        let lot = EntityTrait::from_position(1, 1);

        // Deploy contract policies
        let class_hash: ClassHash = ContractPolicyContract::TEST_CLASS_HASH.try_into().unwrap();
        let mut calldata: Array<felt252> = Default::default();
        calldata.append(1);
        let (addressTrue, _) = deploy_syscall(class_hash, 0, calldata.span(), false).unwrap();

        // Setup entities
        let owner_crew = mocks::delegated_crew(1, 'OWNER');
        let permitted_crew = mocks::delegated_crew(2, 'PLAYER');
        let spaceport = EntityTrait::new(entities::BUILDING, 1);
        components::set::<Location>(spaceport.path(), LocationTrait::new(asteroid));
        components::set::<Location>(owner_crew.path(), LocationTrait::new(asteroid));
        components::set::<Location>(permitted_crew.path(), LocationTrait::new(asteroid));
        components::set::<Crew>(owner_crew.path(), CrewTrait::new(starknet::contract_address_const::<'PLAYER'>()));
        components::set::<Control>(spaceport.path(), ControlTrait::new(owner_crew));
        components::set::<ContractPolicy>(
            policy_path(spaceport, permissions::DOCK_SHIP), ContractPolicy { address: addressTrue }
        );

        let mut state = AcceptContractAgreement::contract_state_for_testing();
        AcceptContractAgreement::run(
            ref state,
            spaceport,
            permissions::DOCK_SHIP,
            permitted_crew,
            permitted_crew,
            mocks::context('PLAYER')
        );

        // Check agreement
        let agreement_data = components::get::<ContractAgreement>(
            agreement_path(spaceport, permissions::DOCK_SHIP, permitted_crew.into())
        ).unwrap();

        assert(agreement_data.address == addressTrue, 'wrong address');
    }
}
