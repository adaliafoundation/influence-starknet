#[starknet::contract]
mod StartPrepaidAgreementAuction {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use starknet::ContractAddress;
    use traits::{Into, TryInto};

    use influence::components::{
        Building, Control, Crew, CrewTrait, PrepaidAgreement, PrepaidAgreementAuction, PrepaidAgreementAuctionTrait,
        Unique
    };
    use influence::{components};
    use influence::common::crew::CrewDetailsTrait;
    use influence::components::agreements::prepaid_auction::modes;
    use influence::config::{entities, errors, permissions};
    use influence::systems::agreements::helpers::{agreement_path, auction_settings, lot_use_path, use_lot_path};
    use influence::types::{Context, Entity, EntityTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct PrepaidAgreementAuctionStarted {
        lot: Entity,
        start_time: u64,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        PrepaidAgreementAuctionStarted: PrepaidAgreementAuctionStarted
    }

    #[external(v0)]
    fn run(ref self: ContractState, lot: Entity, caller_crew: Entity, context: Context) {
        assert(lot.label == entities::LOT, errors::INCORRECT_ENTITY_TYPE);

        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_delegated_to(context.caller);
        crew_details.assert_manned();

        let (asteroid_id, _) = lot.to_position();
        let asteroid = EntityTrait::new(entities::ASTEROID, asteroid_id);
        caller_crew.assert_controls(asteroid);

        let settings = auction_settings(asteroid);
        assert(settings.mode == modes::MANUAL, errors::INCORRECT_STATUS);

        assert(components::get::<PrepaidAgreementAuction>(lot.path()).is_none(), errors::AUCTION_ACTIVE);

        let lot_use: Entity = components::get::<Unique>(lot_use_path(lot)).expect(errors::UNIQUE_NOT_FOUND).unique
            .try_into().unwrap();
        assert(lot_use.label == entities::BUILDING, errors::INCORRECT_ENTITY_TYPE);
        components::get::<Building>(lot_use.path()).expect(errors::BUILDING_NOT_FOUND);

        let tenant: Entity = components::get::<Unique>(use_lot_path(lot)).expect(errors::UNIQUE_NOT_FOUND).unique
            .try_into().unwrap();
        components::get::<PrepaidAgreement>(agreement_path(lot, permissions::USE_LOT, tenant.into()))
            .expect(errors::PREPAID_AGREEMENT_NOT_FOUND);
        assert(!tenant.can(lot, permissions::USE_LOT), errors::ACCESS_DENIED);

        components::set::<PrepaidAgreementAuction>(lot.path(), PrepaidAgreementAuctionTrait::new(context.now));
        self.emit(PrepaidAgreementAuctionStarted {
            lot: lot,
            start_time: context.now,
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
    use traits::Into;

    use influence::components;
    use influence::components::{
        Control, ControlTrait, Location, LocationTrait, PrepaidAgreement, PrepaidAgreementAuction,
        PrepaidAgreementTrait, Unique
    };
    use influence::config::{permissions};
    use influence::systems::agreements::helpers::{agreement_path, lot_use_path, use_lot_path};
    use influence::types::{EntityTrait};
    use influence::test::{helpers, mocks};

    use super::StartPrepaidAgreementAuction;
    use influence::systems::agreements::cancel_prepaid_auction::CancelPrepaidAgreementAuction;

    #[test]
    #[available_gas(30000000)]
    fn test_start_and_cancel_manual_auction() {
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        helpers::init();
        let asteroid = mocks::adalia_prime();
        let lot = EntityTrait::from_position(asteroid.id, 1);

        let asteroid_controller = mocks::delegated_crew(1, 'CONTROLLER');
        components::set::<Control>(asteroid.path(), ControlTrait::new(asteroid_controller));

        let tenant = mocks::delegated_crew(2, 'PLAYER');
        components::set::<Location>(tenant.path(), LocationTrait::new(asteroid));
        let warehouse = mocks::public_warehouse(tenant, 3);
        components::set::<Location>(warehouse.path(), LocationTrait::new(lot));
        components::set::<Unique>(lot_use_path(lot), Unique { unique: warehouse.into() });
        components::set::<Unique>(use_lot_path(lot), Unique { unique: tenant.into() });
        components::set::<PrepaidAgreement>(
            agreement_path(lot, permissions::USE_LOT, tenant.into()),
            PrepaidAgreementTrait::new(1000, 3600, 3600, 0, 3600)
        );

        starknet::testing::set_block_timestamp(7200);

        let mut start_state = StartPrepaidAgreementAuction::contract_state_for_testing();
        StartPrepaidAgreementAuction::run(
            ref start_state, lot, asteroid_controller, mocks::context('CONTROLLER')
        );

        let auction = components::get::<PrepaidAgreementAuction>(lot.path()).expect('auction missing');
        assert(auction.start_time == 7200, 'wrong start time');

        let mut cancel_state = CancelPrepaidAgreementAuction::contract_state_for_testing();
        CancelPrepaidAgreementAuction::run(
            ref cancel_state, lot, asteroid_controller, mocks::context('CONTROLLER')
        );

        assert(components::get::<PrepaidAgreementAuction>(lot.path()).is_none(), 'auction still active');
    }
}
