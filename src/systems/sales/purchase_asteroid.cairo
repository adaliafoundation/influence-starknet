#[starknet::contract]
mod PurchaseAsteroid {
    use array::{ArrayTrait, SpanTrait};
    use hash::LegacyHash;
    use option::OptionTrait;
    use starknet::ContractAddress;
    use traits::{Into, TryInto};

    use cubit::{f64, f128};

    use influence::{config, contracts, components};
    use influence::common::{position, nft};
    use influence::components::{AsteroidSale, Celestial, CelestialTrait, Control, ControlTrait, Crew, CrewTrait,
        crewmate::{collections, Crewmate, CrewmateTrait}};
    use influence::config::{entities, errors};
    use influence::contracts::asteroid::{IAsteroidDispatcher, IAsteroidDispatcherTrait};
    use influence::contracts::crewmate::{ICrewmateDispatcher, ICrewmateDispatcherTrait};
    use influence::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use influence::types::{Context, Entity, EntityTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct AsteroidPurchased {
        asteroid: Entity,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[derive(Copy, Drop, starknet::Event)]
    struct CrewmatePurchased {
        crewmate: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        AsteroidPurchased: AsteroidPurchased,
        CrewmatePurchased: CrewmatePurchased
    }

    #[external(v0)]
    fn run(ref self: ContractState, asteroid: Entity, caller_crew: Entity, context: Context) {
        // Calculate price (if features aren't set, this will fail)
        let celestial_data = components::get::<Celestial>(asteroid.path()).expect(errors::CELESTIAL_NOT_FOUND);
        let price = price(celestial_data.radius);

        // Transfer ETH to Influence receivables account
        let token = IERC20Dispatcher { contract_address: config::get('ASTEROID_PURCHASE_TOKEN').try_into().unwrap() };
        token.transferFrom(context.caller, contracts::get('ReceivablesAccount'), price.into());

        // Mint NFT
        IAsteroidDispatcher { contract_address: contracts::get('Asteroid') }.mint_with_id(
            context.caller, asteroid.id.into()
        );

        // If a crew was provided, assign control of the asteroid to the crew
        if caller_crew.id != 0 {
            let mut crew_data = components::get::<Crew>(caller_crew.path()).expect(errors::CREW_NOT_FOUND);
            crew_data.assert_delegated_to(context.caller);

            // Assign control of the asteroid to the purchasing crew
            components::set::<Control>(asteroid.path(), ControlTrait::new(caller_crew));
        }

        // Check if sale limit has been reached
        let limit: u64 = config::get('ASTEROID_SALE_LIMIT').try_into().unwrap();
        let current_period = context.now / 1000000;

        let mut sale_keys: Array<felt252> = Default::default();
        sale_keys.append(current_period.into());

        match components::get::<AsteroidSale>(sale_keys.span()) {
            Option::Some(mut sale_data) => {
                assert(sale_data.volume < limit, errors::SALE_LIMIT_REACHED);
                sale_data.volume += 1;
                components::set::<AsteroidSale>(sale_keys.span(), sale_data);
            },
            Option::None(_) => {
                assert(limit > 0, errors::SALE_NOT_ACTIVE);
                components::set::<AsteroidSale>(sale_keys.span(), AsteroidSale { volume: 1 });
            }
        };

        // Mint included Adalian crewmate
        let crewmate_id = ICrewmateDispatcher { contract_address: contracts::get('Crewmate') }
            .mint_with_auto_id(context.caller);
        let crewmate = EntityTrait::new(entities::CREWMATE, crewmate_id.try_into().unwrap());
        components::set::<Crewmate>(crewmate.path(), CrewmateTrait::new(collections::ADALIAN));

        self.emit(AsteroidPurchased { asteroid, caller_crew: caller_crew, caller: context.caller });
        self.emit(CrewmatePurchased { crewmate, caller: context.caller });
    }

    fn price(radius: f64::Fixed) -> u128 {
        let base_price: u128 = config::get('ASTEROID_PURCHASE_BASE_PRICE').try_into().unwrap();
        assert(base_price > 0, errors::SALE_NOT_ACTIVE);

        let price_per_lot: u128 = config::get('ASTEROID_PURCHASE_LOT_PRICE').try_into().unwrap();
        assert(price_per_lot > 0, errors::SALE_NOT_ACTIVE);

        let surface_area = position::surface_area(radius);
        let lots = surface_area.mag / f64::ONE;
        return base_price + price_per_lot * lots.into();
    }
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use cubit::f64;

    use influence::config;

    #[test]
    #[available_gas(5000000)]
    fn test_price() {
        config::set('ASTEROID_PURCHASE_BASE_PRICE', 30000000000000000);
        config::set('ASTEROID_PURCHASE_LOT_PRICE', 1250000000000000);

        let price = super::PurchaseAsteroid::price(f64::FixedTrait::new(4402341478, false)); // radius for #249322
        assert(price == 46250000000000000, 'wrong price');
    }
}

// Additionally tested via integration tests