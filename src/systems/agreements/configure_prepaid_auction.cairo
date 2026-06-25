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
        grace_period: u64,
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
        grace_period: u64,
        caller_crew: Entity,
        context: Context
    ) {
        assert(asteroid.label == entities::ASTEROID, errors::INCORRECT_ENTITY_TYPE);
        assert(mode == modes::MANUAL || mode == modes::AUTO, errors::INCORRECT_STATUS);

        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_delegated_to(context.caller);
        crew_details.assert_manned();
        caller_crew.assert_controls(asteroid);

        let settings = PrepaidAgreementAuctionSettingsTrait::new(mode, grace_period);
        components::set::<PrepaidAgreementAuctionSettings>(asteroid.path(), settings);

        self.emit(PrepaidAgreementAuctionConfigured {
            asteroid: asteroid,
            mode: mode,
            grace_period: grace_period,
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
            ref state, asteroid, modes::AUTO, 3600, controller, mocks::context('CONTROLLER')
        );

        let settings = components::get::<PrepaidAgreementAuctionSettings>(asteroid.path()).expect('settings missing');
        assert(settings.mode == modes::AUTO, 'wrong mode');
        assert(settings.grace_period == 3600, 'wrong grace');
    }
}
