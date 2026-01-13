#[starknet::contract]
mod CancelPrepaidAgreement {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use starknet::ContractAddress;
    use traits::Into;

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
    struct PrepaidAgreementCancelled {
        target: Entity,
        permission: u64,
        permitted: Entity, // the permitted crew with the active agreement
        eviction_time: u64, // the time after the notice period concludes
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        PrepaidAgreementCancelled: PrepaidAgreementCancelled
    }

    // Allows the controlling crew to start the cancellation process for a prepaid agreement
    // The agreement will be fully terminated after the notice period (which starts when this system is called)
    #[external(v0)]
    fn run(
        ref self: ContractState,
        target: Entity,
        permission: u64,
        permitted: Entity,
        caller_crew: Entity,
        context: Context
    ) {
        // Check that crew is delegated, and ready
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_delegated_to(context.caller);

        // Check that the caller crew is at the same asteroid
        let (asteroid_id, _) = target.to_position();
        assert(crew_details.asteroid_id() == asteroid_id, errors::DIFFERENT_ASTEROIDS);

        // Check for applicable agreement (Prepaid)
        let prepaid_path = agreement_path(target, permission, permitted.into());
        let mut agreement_data = components::get::<PrepaidAgreement>(prepaid_path)
            .expect(errors::PREPAID_AGREEMENT_NOT_FOUND);

        // Check that the agreement is not already in notice period, or notice period would be in initial term
        assert(agreement_data.notice_time == 0, errors::AGREEMENT_CANCELLED);
        assert(
            context.now >= agreement_data.start_time + agreement_data.initial_term - agreement_data.notice_period,
            errors::TOO_EARLY_TO_CANCEL
        );

        // Check that the calling crew controls the target
        let mut controller = EntityTrait::new(entities::CREW, 0);

        if target.label == entities::LOT {
            // If the target is a lot, check the asteroid controller
            let asteroid = EntityTrait::new(entities::ASTEROID, asteroid_id);
            controller = asteroid.controller();
        } else {
            // Otherwise, check the target controller
            controller = target.controller();
        }

        assert(controller == caller_crew, errors::INCORRECT_CONTROLLER);

        // Determine if the controller needs to pay back a portion of prepaid funds
        if agreement_data.end_time > context.now + agreement_data.notice_period {
            let delegate = components::get::<Crew>(permitted.controller().path())
                .expect(errors::CREW_NOT_FOUND).delegated_to;

            let refunded_time = agreement_data.end_time - (context.now + agreement_data.notice_period);
            let refund = (refunded_time * agreement_data.rate).div_ceil(3600);

            // Confirm receipt on SWAY contract for refund payment
            let mut memo: Array<felt252> = Default::default();
            memo.append(target.into());
            memo.append(permission.into());
            memo.append(permitted.into());
            ISwayDispatcher { contract_address: contracts::get('Sway') }.confirm_receipt(
                context.caller, delegate, refund.into(), memo.hash()
            );
        }

        // Store the agreement
        agreement_data.notice_time = context.now;
        agreement_data.end_time = context.now + agreement_data.notice_period;
        components::set::<PrepaidAgreement>(prepaid_path, agreement_data);

        self.emit(PrepaidAgreementCancelled {
            target: target,
            permission: permission,
            permitted: permitted,
            eviction_time: agreement_data.notice_time + agreement_data.notice_period,
            caller_crew: caller_crew,
            caller: context.caller
        });
    }
}

// Tests --------------------------------------------------------------------------------------------------------------

use influence::types::{Context, Entity};

#[starknet::interface]
trait ICancelPrepaidAgreement<TContractState> {
    fn run(
        ref self: TContractState,
        target: Entity,
        permission: u64,
        permitted: Entity,
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

    use super::{CancelPrepaidAgreement, ICancelPrepaidAgreementLibraryDispatcher, ICancelPrepaidAgreementDispatcherTrait};

    #[test]
    #[available_gas(15000000)]
    fn test_cancel() {
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        helpers::init();
        let asteroid = mocks::adalia_prime();

        // Deploy SWAY
        let sway_address = helpers::deploy_sway();
        let amount: u256 = (100 * 1000000).into();
        starknet::testing::set_contract_address(starknet::contract_address_const::<'ADMIN'>());
        ISwayDispatcher { contract_address: sway_address }.mint(
            starknet::contract_address_const::<'CONTROLLER'>(), amount
        );

        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());

        let controller_crew = influence::test::mocks::delegated_crew(1, 'CONTROLLER');
        components::set::<Control>(asteroid.path(), ControlTrait::new(controller_crew));
        components::set::<Location>(controller_crew.path(), LocationTrait::new(asteroid));

        // Create prepaid agreement
        let lot = EntityTrait::from_position(1, 1);
        let tenant = influence::test::mocks::delegated_crew(2, 'PLAYER');

        starknet::testing::set_block_timestamp(10000);
        let now = starknet::get_block_timestamp();
        let prepaid_path = agreement_path(lot, permissions::USE_LOT, tenant.into());
        components::set::<PrepaidAgreement>(
            prepaid_path,
            PrepaidAgreement {
                rate: 1000,
                initial_term: 3600,
                notice_period: 3600,
                start_time: now,
                end_time: now + 10800,
                notice_time: 0
            }
        );

        starknet::testing::set_block_timestamp(13600);

        // Send payments
        starknet::testing::set_contract_address(starknet::contract_address_const::<'CONTROLLER'>());
        let mut memo: Array<felt252> = Default::default();
        memo.append(lot.into());
        memo.append(permissions::USE_LOT.into());
        memo.append(tenant.into());

        ISwayDispatcher { contract_address: sway_address }.transfer_with_confirmation(
            starknet::contract_address_const::<'PLAYER'>(),
            1000,
            memo.hash(),
            starknet::contract_address_const::<'DISPATCHER'>()
        );

        // Cancel the agreement
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        let class_hash: ClassHash = CancelPrepaidAgreement::TEST_CLASS_HASH.try_into().unwrap();
        ICancelPrepaidAgreementLibraryDispatcher { class_hash: class_hash }.run(
            lot, permissions::USE_LOT.into(), tenant, controller_crew, mocks::context('CONTROLLER')
        );

        // Check that the agreement was cancelled
        let agreement_data = components::get::<PrepaidAgreement>(prepaid_path).unwrap();
        assert(agreement_data.notice_time != 0, 'wrong notice time');
    }

    #[test]
    #[available_gas(15000000)]
    #[should_panic(expected: ('SWAY: invalid receipt', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
    fn test_insufficient_refund() {
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        helpers::init();
        let asteroid = mocks::adalia_prime();

        // Deploy SWAY
        let sway_address = helpers::deploy_sway();
        let amount: u256 = (100 * 1000000).into();
        starknet::testing::set_contract_address(starknet::contract_address_const::<'ADMIN'>());
        ISwayDispatcher { contract_address: sway_address }.mint(
            starknet::contract_address_const::<'CONTROLLER'>(), amount
        );

        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());

        let controller_crew = influence::test::mocks::delegated_crew(1, 'CONTROLLER');
        components::set::<Control>(asteroid.path(), ControlTrait::new(controller_crew));
        components::set::<Location>(controller_crew.path(), LocationTrait::new(asteroid));

        // Create prepaid agreement
        let lot = EntityTrait::from_position(1, 1);
        let tenant = influence::test::mocks::delegated_crew(2, 'PLAYER');

        starknet::testing::set_block_timestamp(10000);
        let now = starknet::get_block_timestamp();
        components::set::<PrepaidAgreement>(
            agreement_path(lot, permissions::USE_LOT, tenant.into()),
            PrepaidAgreement {
                rate: 1000,
                initial_term: 3600,
                notice_period: 3600,
                start_time: now,
                end_time: now + 10800,
                notice_time: 0
            }
        );

        starknet::testing::set_block_timestamp(13600);

        // Send payments
        starknet::testing::set_contract_address(starknet::contract_address_const::<'CONTROLLER'>());
        let mut memo: Array<felt252> = Default::default();
        memo.append(lot.into());
        memo.append(permissions::USE_LOT.into());
        memo.append(tenant.into());

        ISwayDispatcher { contract_address: sway_address }.transfer_with_confirmation(
            starknet::contract_address_const::<'PLAYER'>(),
            999,
            memo.hash(),
            starknet::contract_address_const::<'DISPATCHER'>()
        );

        // Cancel the agreement
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        let class_hash: ClassHash = CancelPrepaidAgreement::TEST_CLASS_HASH.try_into().unwrap();
        ICancelPrepaidAgreementLibraryDispatcher { class_hash: class_hash }.run(
            lot, permissions::USE_LOT.into(), tenant, controller_crew, mocks::context('CONTROLLER')
        );
    }

    #[test]
    #[available_gas(11000000)]
    #[should_panic(expected: ('E6034: too early to cancel', 'ENTRYPOINT_FAILED'))]
    fn test_valid_lease() {
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        helpers::init();
        let asteroid = mocks::adalia_prime();

        // Deploy SWAY
        let sway_address = helpers::deploy_sway();
        let amount: u256 = (100 * 1000000).into();
        starknet::testing::set_contract_address(starknet::contract_address_const::<'ADMIN'>());
        ISwayDispatcher { contract_address: sway_address }.mint(
            starknet::contract_address_const::<'CONTROLLER'>(), amount
        );

        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());

        let controller_crew = influence::test::mocks::delegated_crew(1, 'CONTROLLER');
        components::set::<Control>(asteroid.path(), ControlTrait::new(controller_crew));
        components::set::<Location>(controller_crew.path(), LocationTrait::new(asteroid));

        // Create prepaid agreement
        let lot = EntityTrait::from_position(1, 1);
        let tenant = influence::test::mocks::delegated_crew(2, 'PLAYER');

        starknet::testing::set_block_timestamp(10000);
        let now = starknet::get_block_timestamp();
        components::set::<PrepaidAgreement>(
            agreement_path(lot, permissions::USE_LOT, tenant.into()),
            PrepaidAgreement {
                rate: 1000,
                initial_term: 7200,
                notice_period: 3600,
                start_time: now,
                end_time: now + 10800,
                notice_time: 0
            }
        );

        starknet::testing::set_block_timestamp(13599);

        // Send payments
        starknet::testing::set_contract_address(starknet::contract_address_const::<'CONTROLLER'>());
        let mut memo: Array<felt252> = Default::default();
        memo.append(lot.into());
        memo.append(permissions::USE_LOT.into());
        memo.append(tenant.into());

        ISwayDispatcher { contract_address: sway_address }.transfer_with_confirmation(
            starknet::contract_address_const::<'PLAYER'>(),
            1000,
            memo.hash(),
            starknet::contract_address_const::<'DISPATCHER'>()
        );

        // Cancel the agreement
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        let class_hash: ClassHash = CancelPrepaidAgreement::TEST_CLASS_HASH.try_into().unwrap();
        ICancelPrepaidAgreementLibraryDispatcher { class_hash: class_hash }.run(
            lot, permissions::USE_LOT.into(), tenant, controller_crew, mocks::context('CONTROLLER')
        );
    }

    #[test]
    #[available_gas(14000000)]
    #[should_panic(expected: ('E6020: agreement cancelled', 'ENTRYPOINT_FAILED'))]
    fn test_already_cancelled() {
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        helpers::init();
        let asteroid = mocks::adalia_prime();

        // Deploy SWAY
        let sway_address = helpers::deploy_sway();
        let amount: u256 = (100 * 1000000).into();
        starknet::testing::set_contract_address(starknet::contract_address_const::<'ADMIN'>());
        ISwayDispatcher { contract_address: sway_address }.mint(
            starknet::contract_address_const::<'CONTROLLER'>(), amount
        );

        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());

        let controller_crew = influence::test::mocks::delegated_crew(1, 'CONTROLLER');
        components::set::<Control>(asteroid.path(), ControlTrait::new(controller_crew));
        components::set::<Location>(controller_crew.path(), LocationTrait::new(asteroid));

        // Create prepaid agreement
        let lot = EntityTrait::from_position(1, 1);
        let tenant = influence::test::mocks::delegated_crew(2, 'PLAYER');

        starknet::testing::set_block_timestamp(10000);
        let now = starknet::get_block_timestamp();
        components::set::<PrepaidAgreement>(
            agreement_path(lot, permissions::USE_LOT, tenant.into()),
            PrepaidAgreement {
                rate: 1000,
                initial_term: 3600,
                notice_period: 3600,
                start_time: now,
                end_time: now + 10800,
                notice_time: 0
            }
        );

        starknet::testing::set_block_timestamp(13600);

        // Send payments
        starknet::testing::set_contract_address(starknet::contract_address_const::<'CONTROLLER'>());
        let mut memo: Array<felt252> = Default::default();
        memo.append(lot.into());
        memo.append(permissions::USE_LOT.into());
        memo.append(tenant.into());

        ISwayDispatcher { contract_address: sway_address }.transfer_with_confirmation(
            starknet::contract_address_const::<'PLAYER'>(),
            1000,
            memo.hash(),
            starknet::contract_address_const::<'DISPATCHER'>()
        );

        // Cancel the agreement
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        let class_hash: ClassHash = CancelPrepaidAgreement::TEST_CLASS_HASH.try_into().unwrap();
        ICancelPrepaidAgreementLibraryDispatcher { class_hash: class_hash }.run(
            lot, permissions::USE_LOT.into(), tenant, controller_crew, mocks::context('CONTROLLER')
        );

        // Try cancelling again
        starknet::testing::set_block_timestamp(14600);
        ICancelPrepaidAgreementLibraryDispatcher { class_hash: class_hash }.run(
            lot, permissions::USE_LOT.into(), tenant, controller_crew, mocks::context('CONTROLLER')
        );
    }
}
