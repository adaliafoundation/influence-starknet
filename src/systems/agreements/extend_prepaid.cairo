#[starknet::contract]
mod ExtendPrepaidAgreement {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use starknet::ContractAddress;
    use traits::{Into, TryInto};

    use influence::{components, config, contracts};
    use influence::common::{crew::CrewDetailsTrait, math::RoundedDivTrait};
    use influence::components::{Control, Crew, CrewTrait, PrepaidAgreement, PrepaidAgreementTrait};
    use influence::config::{entities, errors, permissions};
    use influence::contracts::sway::{ISwayDispatcher, ISwayDispatcherTrait};
    use influence::systems::agreements::helpers::agreement_path;
    use influence::types::{ArrayHashTrait, Context, Entity, EntityTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct PrepaidAgreementExtended {
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
        PrepaidAgreementExtended: PrepaidAgreementExtended
    }

    #[external(v0)]
    fn run(
        ref self: ContractState,
        target: Entity,
        permission: u64,
        permitted: Entity,
        added_term: u64, // additional term to add in IRL seconds
        caller_crew: Entity,
        context: Context
    ) {
        // Check that crew is delegated, and ready
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_delegated_to(context.caller);

        // Make sure the calling crew is either the same as, or controls the permitted
        assert(caller_crew == permitted.controller(), 'not controller or permitted');

        // Check for applicable agreement (Prepaid)
        let prepaid_path = agreement_path(target, permission, caller_crew.into());
        let mut agreement_data = components::get::<PrepaidAgreement>(prepaid_path)
            .expect(errors::PREPAID_AGREEMENT_NOT_FOUND);

        // Ensure you can't extend an expired agreement
        assert(agreement_data.end_time > context.now, errors::AGREEMENT_EXPIRED);

        // Check that the agreement is not in notice period and won't be too long
        assert(agreement_data.notice_time == 0, errors::AGREEMENT_CANCELLED);
        let extended_term = agreement_data.end_time - agreement_data.start_time + added_term;
        assert(extended_term <= config::get('MAX_POLICY_DURATION').try_into().unwrap(), errors::AGREEMENT_TOO_LONG);

        // Get the controller and delegate for the target entity
        let mut controller = EntityTrait::new(entities::CREW, 0);

        if target.label == entities::LOT {
            // For lots, get the asteroid controller
            let (asteroid_id, _) = target.to_position();
            let asteroid = EntityTrait::new(entities::ASTEROID, asteroid_id);
            controller = components::get::<Control>(asteroid.path()).expect(errors::CONTROL_NOT_FOUND).controller;
        } else {
            // For all others just get the direct controller
            controller = components::get::<Control>(target.path()).expect(errors::CONTROL_NOT_FOUND).controller;
        }

        let delegate = components::get::<Crew>(controller.path()).expect(errors::CREW_NOT_FOUND).delegated_to;

        // Calculate payment amount
        let amount = (agreement_data.rate * added_term).div_ceil(3600);

        // Confirm receipt on SWAY contract for payment to controller
        let mut memo: Array<felt252> = Default::default();
        memo.append(target.into());
        memo.append(permission.into());
        memo.append(permitted.into());
        ISwayDispatcher { contract_address: contracts::get('Sway') }.confirm_receipt(
            context.caller, delegate, amount.into(), memo.hash()
        );

        // Store the agreement
        agreement_data.end_time += added_term;
        components::set::<PrepaidAgreement>(prepaid_path, agreement_data);

        self.emit(PrepaidAgreementExtended {
            target: target,
            permission: permission,
            permitted: permitted,
            term: agreement_data.end_time - agreement_data.start_time,
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
trait IExtendPrepaidAgreement<TContractState> {
    fn run(
        ref self: TContractState,
        target: Entity,
        permission: u64,
        permitted: Entity,
        added_term: u64,
        caller_crew: Entity,
        context: Context
    );
}

#[cfg(test)]
mod tests {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use traits::{Into, TryInto};
    use starknet::ClassHash;

    use influence::components;
    use influence::components::{Control, ControlTrait, Crew, CrewTrait, Location, LocationTrait,
        PrepaidAgreement, PrepaidAgreementTrait};
    use influence::config::{entities, permissions};
    use influence::contracts::sway::{Sway, ISwayDispatcher, ISwayDispatcherTrait};
    use influence::systems::agreements::helpers::agreement_path;
    use influence::types::{ArrayHashTrait, EntityTrait};
    use influence::test::{helpers, mocks};

    use super::{ExtendPrepaidAgreement, IExtendPrepaidAgreementLibraryDispatcher, IExtendPrepaidAgreementDispatcherTrait};

    #[test]
    #[available_gas(15000000)]
    fn test_extend() {
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

        let controller_crew = influence::test::mocks::delegated_crew(1, 'CONTROLLER');
        components::set::<Control>(asteroid.path(), ControlTrait::new(controller_crew));

        // Create prepaid agreement
        let lot = EntityTrait::from_position(1, 1);
        let caller_crew = influence::test::mocks::delegated_crew(2, 'PLAYER');
        components::set::<Location>(caller_crew.path(), LocationTrait::new(asteroid));

        starknet::testing::set_block_timestamp(10000);
        let now = starknet::get_block_timestamp();
        let prepaid_path = agreement_path(lot, permissions::USE_LOT, caller_crew.into());
        components::set::<PrepaidAgreement>(
            prepaid_path,
            PrepaidAgreementTrait::new(1000, 3600, 3600, now, now + 3600)
        );

        // Send payment
        starknet::testing::set_contract_address(starknet::contract_address_const::<'PLAYER'>());
        let mut memo: Array<felt252> = Default::default();
        memo.append(lot.into());
        memo.append(permissions::USE_LOT.into());
        memo.append(caller_crew.into());
        ISwayDispatcher { contract_address: sway_address }.transfer_with_confirmation(
            starknet::contract_address_const::<'CONTROLLER'>(),
            2000,
            memo.hash(),
            starknet::contract_address_const::<'DISPATCHER'>()
        );

        // Extend the agreement
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        let class_hash: ClassHash = ExtendPrepaidAgreement::TEST_CLASS_HASH.try_into().unwrap();
        IExtendPrepaidAgreementLibraryDispatcher { class_hash: class_hash }.run(
            lot, permissions::USE_LOT, caller_crew, 7200, caller_crew, mocks::context('PLAYER')
        );

        // Check that the agreement was extended
        let agreement_data = components::get::<PrepaidAgreement>(prepaid_path).unwrap();
        assert(agreement_data.end_time == 20800, 'wrong end time');
    }

    #[test]
    #[available_gas(11000000)]
    #[should_panic(expected: ('SWAY: invalid receipt', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
    fn test_insufficient_funds() {
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

        let controller_crew = influence::test::mocks::delegated_crew(1, 'CONTROLLER');
        components::set::<Control>(asteroid.path(), ControlTrait::new(controller_crew));

        // Create prepaid agreement
        let lot = EntityTrait::from_position(1, 1);
        let caller_crew = influence::test::mocks::delegated_crew(2, 'PLAYER');
        components::set::<Location>(caller_crew.path(), LocationTrait::new(asteroid));

        starknet::testing::set_block_timestamp(10000);
        let now = starknet::get_block_timestamp();
        components::set::<PrepaidAgreement>(
            agreement_path(lot, permissions::USE_LOT, caller_crew.into()),
            PrepaidAgreementTrait::new(1000, 3600, 3600, now, now + 3600)
        );

        // Send payment
        starknet::testing::set_contract_address(starknet::contract_address_const::<'PLAYER'>());
        let mut memo: Array<felt252> = Default::default();
        memo.append(lot.into());
        memo.append(permissions::USE_LOT.into());
        memo.append(caller_crew.into());
        ISwayDispatcher { contract_address: sway_address }.transfer_with_confirmation(
            starknet::contract_address_const::<'CONTROLLER'>(),
            1999,
            memo.hash(),
            starknet::contract_address_const::<'DISPATCHER'>()
        );

        // Extend the agreement
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        let class_hash: ClassHash = ExtendPrepaidAgreement::TEST_CLASS_HASH.try_into().unwrap();
        IExtendPrepaidAgreementLibraryDispatcher { class_hash: class_hash }.run(
            lot, permissions::USE_LOT, caller_crew, 7200, caller_crew, mocks::context('PLAYER')
        );
    }

    #[test]
    #[available_gas(11000000)]
    #[should_panic(expected: ('SWAY: invalid receipt', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
    fn test_wrong_recipient() {
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

        let controller_crew = influence::test::mocks::delegated_crew(1, 'CONTROLLER');
        components::set::<Control>(asteroid.path(), ControlTrait::new(controller_crew));

        // Create prepaid agreement
        let lot = EntityTrait::from_position(1, 1);
        let caller_crew = influence::test::mocks::delegated_crew(2, 'PLAYER');
        components::set::<Location>(caller_crew.path(), LocationTrait::new(asteroid));

        starknet::testing::set_block_timestamp(10000);
        let now = starknet::get_block_timestamp();
        components::set::<PrepaidAgreement>(
            agreement_path(lot, permissions::USE_LOT, caller_crew.into()),
            PrepaidAgreementTrait::new(1000, 3600, 3600, now, now + 3600)
        );

        // Send payment
        starknet::testing::set_contract_address(starknet::contract_address_const::<'PLAYER'>());
        let mut memo: Array<felt252> = Default::default();
        memo.append(lot.into());
        memo.append(permissions::USE_LOT.into());
        memo.append(caller_crew.into());
        ISwayDispatcher { contract_address: sway_address }.transfer_with_confirmation(
            starknet::contract_address_const::<'WRONG_CONTROLLER'>(),
            1999,
            memo.hash(),
            starknet::contract_address_const::<'DISPATCHER'>()
        );

        // Extend the agreement
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        let class_hash: ClassHash = ExtendPrepaidAgreement::TEST_CLASS_HASH.try_into().unwrap();
        IExtendPrepaidAgreementLibraryDispatcher { class_hash: class_hash }.run(
            lot, permissions::USE_LOT, caller_crew, 7200, caller_crew, mocks::context('PLAYER')
        );
    }
}
