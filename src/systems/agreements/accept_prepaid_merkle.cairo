#[starknet::contract]
mod AcceptPrepaidMerkleAgreement {
    use array::{Array, ArrayTrait};
    use option::OptionTrait;
    use starknet::{contract_address_const, ContractAddress};
    use traits::{Into, TryInto};

    use influence::{components, config, contracts};
    use influence::common::{crew::CrewDetailsTrait, math::RoundedDivTrait};
    use influence::components::{Crew, CrewTrait, Control, ControlTrait, PrepaidMerklePolicy, PrepaidMerklePolicyTrait,
        PrepaidAgreement, PrepaidAgreementTrait, Unique};
    use influence::config::{entities, errors, permissions};
    use influence::contracts::sway::{ISwayDispatcher, ISwayDispatcherTrait};
    use influence::systems::agreements::helpers::agreement_path;
    use influence::systems::policies::helpers::policy_path;
    use influence::types::{ArrayHashTrait, Context, Entity, EntityTrait, MerkleTree, MerkleTreeTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct PrepaidMerkleAgreementAccepted {
        target: Entity,
        permission: u64,
        permitted: Entity,
        term: u64,
        rate: u64,
        initial_term: u64,
        notice_period: u64,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        PrepaidMerkleAgreementAccepted: PrepaidMerkleAgreementAccepted
    }

    #[external(v0)]
    fn run(
        ref self: ContractState,
        target: Entity, // the target entity the permitted will get permission to act on
        permission: u64, // the permission being granted
        permitted: Entity, // the entity gaining the permission
        term: u64,
        merkle_proof: Span<felt252>,
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
        let mut policy_path: Span<felt252> = Default::default().span();

        if target.label == entities::LOT {
            assert(permission == permissions::USE_LOT, 'invalid permission');

            // Lot policies are all associated to the asteroid
            policy_path = policy_path(asteroid, permission);
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
                    assert(
                        !unique_data.unique.try_into().unwrap().can(target, permissions::USE_LOT),
                        'lot already leased'
                    );
                },
                Option::None(_) => ()
            };

            // Update unique with new lease permitted crew
            components::set::<Unique>(unique_path.span(), Unique { unique: permitted.into() });
        } else {
            policy_path = policy_path(target, permission);
            controller_crew = components::get::<Control>(target.path()).expect(errors::CONTROL_NOT_FOUND).controller;
        }

        let policy_data = components::get::<PrepaidMerklePolicy>(policy_path)
            .expect(errors::PREPAID_MERKLE_POLICY_NOT_FOUND);

        // Verify Merkle proof
        let mut merkle_tree = MerkleTreeTrait::new();
        let expected_root = merkle_tree.compute_root(target.into(), merkle_proof);
        assert(expected_root == policy_data.merkle_root, errors::INVALID_MERKLE_PROOF);

        // Check that the term matches the policy
        assert(term >= policy_data.initial_term, errors::INVALID_AGREEMENT);
        assert(term <= config::get('MAX_POLICY_DURATION').try_into().unwrap(), errors::AGREEMENT_TOO_LONG);

        // Calculate the required SWAY payment
        let amount = (term * policy_data.rate).div_ceil(3600);

        // Get controller's account address
        let controller_address = components::get::<Crew>(controller_crew.path())
            .expect(errors::CREW_NOT_FOUND).delegated_to;

        // Confirm receipt on SWAY contract for payment to controller
        let mut memo: Array<felt252> = Default::default();
        memo.append(target.into());
        memo.append(permission.into());
        memo.append(permitted.into());
        ISwayDispatcher { contract_address: contracts::get('Sway') }.confirm_receipt(
            context.caller, controller_address, amount.into(), memo.hash()
        );

        // Create agreement
        let mut agreement_data = PrepaidAgreement {
            rate: policy_data.rate,
            initial_term: policy_data.initial_term,
            notice_period: policy_data.notice_period,
            start_time: context.now,
            end_time: context.now + term,
            notice_time: 0
        };

        components::set::<PrepaidAgreement>(agreement_path(target, permission, permitted.into()), agreement_data);

        self.emit(PrepaidMerkleAgreementAccepted {
            target: target,
            permission: permission,
            permitted: permitted,
            term: term,
            rate: agreement_data.rate,
            initial_term: agreement_data.initial_term,
            notice_period: agreement_data.notice_period,
            caller_crew: caller_crew,
            caller: context.caller
        });
    }
}

// Tests --------------------------------------------------------------------------------------------------------------

use influence::types::{Context, Entity};

#[starknet::interface]
trait IAcceptPrepaidMerkleAgreement<TContractState> {
    fn run(
        ref self: TContractState,
        target: Entity,
        permission: u64,
        permitted: Entity,
        term: u64,
        merkle_proof: Span<felt252>,
        caller_crew: Entity,
        context: Context
    );
}

#[cfg(test)]
mod tests {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use traits::{Into, TryInto};
    use starknet::{ClassHash, testing};

    use influence::components;
    use influence::components::{Control, ControlTrait, Crew, CrewTrait, Location, LocationTrait, PrepaidAgreement,
        PrepaidMerklePolicy, PrepaidMerklePolicyTrait};
    use influence::config::{entities, permissions};
    use influence::contracts::sway::{Sway, ISwayDispatcher, ISwayDispatcherTrait};
    use influence::systems::{agreements::helpers::agreement_path, policies::helpers::policy_path};
    use influence::types::{ArrayHashTrait, Entity, EntityTrait};
    use influence::test::{helpers, mocks};

    use super::{AcceptPrepaidMerkleAgreement, IAcceptPrepaidMerkleAgreementLibraryDispatcher,
        IAcceptPrepaidMerkleAgreementDispatcherTrait};

    #[test]
    #[available_gas(15000000)]
    fn test_agreement_with_merkle() {
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        helpers::init();
        mocks::constants();
        let asteroid = mocks::adalia_prime();

        // Deploy SWAY
        let sway_address = helpers::deploy_sway();
        let amount: u256 = (100 * 1000000).into();
        starknet::testing::set_contract_address(starknet::contract_address_const::<'ADMIN'>());
        ISwayDispatcher { contract_address: sway_address }.mint(starknet::contract_address_const::<'PLAYER'>(), amount);
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());

        // Move controller crew to different delegate address
        let controller_crew = influence::test::mocks::delegated_crew(1, 'PLAYER');
        let mut crew_data = components::get::<Crew>(controller_crew.path()).unwrap();
        crew_data.delegated_to = starknet::contract_address_const::<'CONTROLLER'>();
        components::set::<Crew>(controller_crew.path(), crew_data);
        components::set::<Control>(asteroid.path(), ControlTrait::new(controller_crew));

        // Create merkle policy
        components::set::<PrepaidMerklePolicy>(policy_path(asteroid, permissions::USE_LOT), PrepaidMerklePolicy {
            rate: 1000,
            initial_term: 500 * 3600,
            notice_period: 500 * 3600,
            merkle_root: 3564232575591004875088914309508967869247357462435734306724441838705975549200
        });

        // Generate args
        let caller_crew = influence::test::mocks::delegated_crew(2, 'PLAYER');
        components::set::<Location>(caller_crew.path(), LocationTrait::new(asteroid));
        let lot = EntityTrait::from_position(1, 1);
        let mut merkle_proof: Array<felt252> = Default::default();
        merkle_proof.append(562949953486852);
        merkle_proof.append(1946822080369342510206283054380575130640041029732207385159703565378933984719);

        // Send payment
        starknet::testing::set_contract_address(starknet::contract_address_const::<'PLAYER'>());
        let mut memo: Array<felt252> = Default::default();
        memo.append(lot.into());
        memo.append(permissions::USE_LOT.into());
        memo.append(caller_crew.into());
        ISwayDispatcher { contract_address: sway_address }.transfer_with_confirmation(
            starknet::contract_address_const::<'CONTROLLER'>(),
            5000000,
            memo.hash(),
            starknet::contract_address_const::<'DISPATCHER'>()
        );

        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());

        let class_hash: ClassHash = AcceptPrepaidMerkleAgreement::TEST_CLASS_HASH.try_into().unwrap();
        IAcceptPrepaidMerkleAgreementLibraryDispatcher { class_hash: class_hash }.run(
            lot, permissions::USE_LOT, caller_crew, 18000000, merkle_proof.span(), caller_crew, mocks::context('PLAYER')
        );

        // Check agreement
        let agreement_data = components::get::<PrepaidAgreement>(
            agreement_path(lot, permissions::USE_LOT, caller_crew.into())
        ).unwrap();

        assert(agreement_data.rate == 1000, 'invalid rate');
        assert(agreement_data.initial_term == 500 * 3600, 'invalid initial term');
        assert(agreement_data.notice_period == 500 * 3600, 'invalid notice period');
        assert(agreement_data.start_time == 0, 'invalid start time');
        assert(agreement_data.end_time == 18000000, 'invalid end time');
    }
}

