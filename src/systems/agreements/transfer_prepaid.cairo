#[starknet::contract]
mod TransferPrepaidAgreement {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use starknet::ContractAddress;
    use traits::{Into, TryInto};

    use influence::{components, config, contracts};
    use influence::common::{crew::CrewDetailsTrait, math::RoundedDivTrait};
    use influence::components::{Control, Crew, CrewTrait, PrepaidAgreement, PrepaidAgreementTrait, Unique};
    use influence::config::{entities, errors, permissions};
    use influence::contracts::sway::{ISwayDispatcher, ISwayDispatcherTrait};
    use influence::systems::agreements::helpers::agreement_path;
    use influence::types::{ArrayHashTrait, Context, Entity, EntityTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct PrepaidAgreementTransferred {
        target: Entity,
        permission: u64,
        permitted: Entity,
        old_permitted: Entity,
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
        PrepaidAgreementTransferred: PrepaidAgreementTransferred
    }

    #[external(v0)]
    fn run(
        ref self: ContractState,
        target: Entity,
        permission: u64,
        permitted: Entity,
        new_permitted: Entity,
        caller_crew: Entity,
        context: Context
    ) {
        // Check that crew is delegated, and ready
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_delegated_to(context.caller);

        // Make sure the calling crew is either the same as, or controls the permitted
        assert(caller_crew == permitted.controller(), 'not controller or permitted');

        // Check for applicable agreement (Prepaid)
        let prepaid_path = agreement_path(target, permission, permitted.into());
        let mut agreement_data = components::get::<PrepaidAgreement>(prepaid_path)
            .expect(errors::PREPAID_AGREEMENT_NOT_FOUND);

        // Ensure you can't transfer an expired agreement
        assert(agreement_data.end_time > context.now, errors::AGREEMENT_EXPIRED);

        // Store the agreement
        let new_path = agreement_path(target, permission, new_permitted.into());

        // Check that there is no existing agreement
        assert(!new_permitted.can(target, permission), 'already has agreement');

        let original_start = agreement_data.start_time;
        agreement_data.start_time = context.now;
        components::set::<PrepaidAgreement>(new_path, agreement_data);

        // Remove the old agreement
        agreement_data.start_time = original_start;
        agreement_data.end_time = context.now;
        components::set::<PrepaidAgreement>(prepaid_path, agreement_data);

        // Update the unique UseLot pointer
        let mut unique_path: Array<felt252> = Default::default();
        unique_path.append('UseLot');
        unique_path.append(target.into());
        components::set::<Unique>(unique_path.span(), Unique { unique: new_permitted.into() });

        self.emit(PrepaidAgreementTransferred {
            target: target,
            permission: permission,
            permitted: new_permitted,
            old_permitted: permitted,
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

    use super::TransferPrepaidAgreement;

    #[test]
    #[available_gas(15000000)]
    fn test_transfer_prepaid() {
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

        // Transfer to new crew
        starknet::testing::set_block_timestamp(11000);
        let new_crew = influence::test::mocks::delegated_crew(3, 'PLAYER2');
        let mut state = TransferPrepaidAgreement::contract_state_for_testing();
        TransferPrepaidAgreement::run(
            ref state,
            lot,
            permissions::USE_LOT,
            caller_crew,
            new_crew,
            caller_crew,
            mocks::context('PLAYER')
        );

        // Check that the agreement was extended
        let old_agreement_data = components::get::<PrepaidAgreement>(prepaid_path).unwrap();
        let new_agreement_path = agreement_path(lot, permissions::USE_LOT, new_crew.into());
        let new_agreement_data = components::get::<PrepaidAgreement>(new_agreement_path).unwrap();

        assert(old_agreement_data.start_time == 10000, 'old agreement start time');
        assert(old_agreement_data.end_time == 11000, 'old agreement end time');
        assert(new_agreement_data.start_time == 11000, 'new agreement start time');
        assert(new_agreement_data.end_time == 13600, 'new agreement end time');
    }
}
