#[starknet::contract]
mod ConfigurePrepaidAgreementAuction {
    use starknet::ContractAddress;

    use influence::components::{PrepaidAgreementAuctionSettings, PrepaidAgreementAuctionSettingsTrait};
    use influence::{components};
    use influence::common::crew::CrewDetailsTrait;
    use influence::config::{entities, errors};
    use influence::types::{Context, Entity, EntityTrait};
    use influence::components::agreements::prepaid_auction::modes;

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct PrepaidAgreementAuctionConfigured {
        asteroid: Entity,
        mode: u64,
        initial_period: u64,
        descending_period: u64,
        max_price: u64,
        min_price: u64,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        PrepaidAgreementAuctionConfigured: PrepaidAgreementAuctionConfigured
    }

    #[external(v0)]
    fn run(
        ref self: ContractState,
        asteroid: Entity,
        mode: u64,
        initial_period: u64,
        descending_period: u64,
        max_price: u64,
        min_price: u64,
        caller_crew: Entity,
        context: Context
    ) {
        assert(asteroid.label == entities::ASTEROID, errors::INCORRECT_ENTITY_TYPE);
        assert(mode == modes::MANUAL || mode == modes::AUTO, errors::INCORRECT_STATUS);
        assert(descending_period > 0, errors::INVALID_AGREEMENT);
        assert(max_price >= min_price, errors::INVALID_AGREEMENT);
        assert(min_price > 0, errors::INVALID_AGREEMENT);

        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_delegated_to(context.caller);
        crew_details.assert_manned();
        caller_crew.assert_controls(asteroid);

        let settings = PrepaidAgreementAuctionSettingsTrait::new(
            mode, initial_period, descending_period, max_price, min_price
        );
        components::set::<PrepaidAgreementAuctionSettings>(asteroid.path(), settings);

        self.emit(PrepaidAgreementAuctionConfigured {
            asteroid: asteroid,
            mode: mode,
            initial_period: initial_period,
            descending_period: descending_period,
            max_price: max_price,
            min_price: min_price,
            caller_crew: caller_crew,
            caller: context.caller
        });
    }
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use option::OptionTrait;

    use influence::components;
    use influence::components::{Control, ControlTrait, PrepaidAgreementAuctionSettings};
    use influence::components::agreements::prepaid_auction::modes;
    use influence::types::EntityTrait;
    use influence::test::{helpers, mocks};

    use super::ConfigurePrepaidAgreementAuction;

    #[test]
    #[available_gas(15000000)]
    fn test_configure_prepaid_auction_settings() {
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        helpers::init();
        let asteroid = mocks::asteroid();
        let controller = mocks::delegated_crew(1, 'CONTROLLER');
        components::set::<Control>(asteroid.path(), ControlTrait::new(controller));

        let mut state = ConfigurePrepaidAgreementAuction::contract_state_for_testing();
        ConfigurePrepaidAgreementAuction::run(
            ref state, asteroid, modes::AUTO, 3600, 604800, 2000000, 1000000, controller, mocks::context('CONTROLLER')
        );

        let settings = components::get::<PrepaidAgreementAuctionSettings>(asteroid.path()).expect('settings missing');
        assert(settings.mode == modes::AUTO, 'wrong mode');
        assert(settings.initial_period == 3600, 'wrong initial');
        assert(settings.descending_period == 604800, 'wrong descending');
        assert(settings.max_price == 2000000, 'wrong max');
        assert(settings.min_price == 1000000, 'wrong min');
    }
}
