#[starknet::contract]
mod ConfigureExchange {
    use array::{Array, ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use starknet::ContractAddress;
    use traits::{Into, TryInto};

    use influence::components;
    use influence::common::crew::CrewDetailsTrait;
    use influence::components::{Building, BuildingTrait, Crew, CrewTrait, Exchange, ExchangeTrait,
        exchange_type::{types as exchange_types, ExchangeTypeTrait}};
    use influence::config::{entities, errors};
    use influence::types::{Context, Entity, EntityTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct ExchangeConfigured {
        exchange: Entity,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        ExchangeConfigured: ExchangeConfigured
    }

    #[external(v0)]
    fn run(
        ref self: ContractState,
        exchange: Entity,
        maker_fee: u64, // fee in ten thousandths (i.e. 0.25% == 25)
        taker_fee: u64, // fee in ten thousandths
        allowed_products: Span<u64>,
        caller_crew: Entity,
        context: Context
    ) {
        // Check that crew is delegated, and ready
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_all_ready(context.caller, context.now);

        // Make sure crew controls exchange
        caller_crew.assert_controls(exchange);

        // Make sure exchange is operational
        let building = components::get::<Building>(exchange.path()).expect(errors::BUILDING_NOT_FOUND);
        building.assert_operational();

        // Check that crew is on the same asteroid as exchange
        let (exchange_ast, _) = exchange.to_position();
        assert(exchange_ast == crew_details.asteroid_id(), errors::DIFFERENT_ASTEROIDS);

        // Make sure there aren't too many allowed products
        let mut exchange_data = components::get::<Exchange>(exchange.path()).expect(errors::EXCHANGE_NOT_FOUND);
        let exchange_config = ExchangeTypeTrait::by_type(exchange_data.exchange_type);
        assert(allowed_products.len().into() <= exchange_config.allowed_products, errors::TOO_MANY_ALLOWED_PRODUCTS);

        // Configure the exchange
        exchange_data.maker_fee = maker_fee;
        exchange_data.taker_fee = taker_fee;
        exchange_data.allowed_products = allowed_products;
        components::set::<Exchange>(exchange.path(), exchange_data);

        self.emit(ExchangeConfigured {
            exchange: exchange,
            caller_crew: caller_crew,
            caller: context.caller
        });
    }
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use array::{ArrayTrait, SpanTrait};

    use influence::components;
    use influence::components::{Location, LocationTrait, exchange_type::types as exchange_types};
    use influence::test::{helpers, mocks};
    use influence::types::{Entity, EntityTrait};

    use super::ConfigureExchange;

    #[test]
    #[available_gas(11000000)]
    fn test_configuring_exchange() {
        helpers::init();

        let asteroid = influence::test::mocks::adalia_prime();
        let crew = influence::test::mocks::delegated_crew(1, 'PLAYER');
        mocks::exchange_type(exchange_types::BASIC);

        // Setup station
        let station = influence::test::mocks::public_habitat(crew, 1);
        components::set::<Location>(station.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1758637)));
        components::set::<Location>(crew.path(), LocationTrait::new(station));

        // Setup exchange
        let exchange = mocks::public_marketplace(crew, 2);
        components::set::<Location>(exchange.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1758636)));

        // Configure exchange
        let mut state = ConfigureExchange::contract_state_for_testing();
        let mut allowed_products: Array<u64> = Default::default();
        allowed_products.append(175);
        allowed_products.append(69);
        allowed_products.append(70);

        ConfigureExchange::run(
            ref state,
            exchange: exchange,
            maker_fee: 2500,
            taker_fee: 5000,
            allowed_products: allowed_products.span(),
            caller_crew: crew,
            context: mocks::context('PLAYER')
        );
    }
}
