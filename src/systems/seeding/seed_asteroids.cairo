#[starknet::contract]
mod SeedAsteroids {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use traits::Into;

    use influence::{components, contracts, systems};
    use influence::components::{Name, NameTrait, Unique, UniqueTrait};
    use influence::config::entities;
    use influence::contracts::asteroid::{IAsteroidDispatcher, IAsteroidDispatcherTrait};
    use influence::types::context::{Context, ContextTrait};
    use influence::types::entity::{Entity, EntityTrait};
    use influence::types::string::{String, StringTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, Serde)]
    struct SeededAsteroid {
        asteroid_id: u64,
        name: felt252
    }

    // Seed asteroid ids and name uniqueness
    #[external(v0)]
    fn run(ref self: ContractState, asteroids: Span<SeededAsteroid>, context: Context) {
        // Check the caller is the admin
        assert(context.is_admin(), 'only admin can seed');

        let mut iter = 0;

        // Loop through the asteroids and seed them
        loop {
            if iter >= asteroids.len() { break; }
            let to_seed = *asteroids.at(iter);

            // Mint a new asteroid NFT
            let asteroid_address = contracts::get('Asteroid');
            IAsteroidDispatcher { contract_address: asteroid_address }.mint_with_id(
                asteroid_address, to_seed.asteroid_id.into()
            );

            let asteroid = EntityTrait::new(entities::ASTEROID, to_seed.asteroid_id);

            // If there's a name, save it and set its uniqueness
            if to_seed.name != 0 {
                components::set::<Name>(asteroid.path(), NameTrait::new(StringTrait::new(to_seed.name)));
                components::set::<Unique>(array![asteroid.label.into(), to_seed.name].span(), UniqueTrait::new());
            }

            iter += 1;
        };
    }
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use traits::Into;

    use influence::components;
    use influence::components::{Name, NameTrait, Unique, UniqueTrait};
    use influence::config::entities;
    use influence::contracts::asteroid::{IAsteroidDispatcher, IAsteroidDispatcherTrait};
    use influence::types::{EntityTrait, StringTrait, Context};
    use influence::test::{helpers, mocks};

    use super::SeedAsteroids;

    #[test]
    #[available_gas(3000000)]
    fn test_seed() {
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        helpers::init();
        let asteroid_address = helpers::deploy_asteroid();

        starknet::testing::set_contract_address(starknet::contract_address_const::<'ADMIN'>());
        IAsteroidDispatcher { contract_address: asteroid_address }
            .add_grant(starknet::contract_address_const::<'DISPATCHER'>(), 2);

        let asteroids = array![
            SeedAsteroids::SeededAsteroid { asteroid_id: 1, name: 'Adalia Prime' },
            SeedAsteroids::SeededAsteroid { asteroid_id: 2, name: 'Adalia Subprime' }
        ].span();

        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        let mut state = SeedAsteroids::contract_state_for_testing();
        SeedAsteroids::run(ref state, asteroids, mocks::context('ADMIN'));

        let mut unique_data = components::get::<Unique>(
            array![entities::ASTEROID.into(), 'Adalia Prime'].span()).unwrap();
        assert(unique_data.unique == 1, 'not unique');

        unique_data = components::get::<Unique>(array![entities::ASTEROID.into(), 'Adalia Subprime'].span()).unwrap();
        assert(unique_data.unique == 1, 'not unique');

        let owner = IAsteroidDispatcher { contract_address: asteroid_address }.owner_of(1.into());
        assert(owner == asteroid_address, 'wrong owner');
    }

    #[test]
    #[available_gas(3000000)]
    #[should_panic(expected: ('only admin can seed', ))]
    fn test_not_admin() {
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        helpers::init();
        let asteroid_address = helpers::deploy_asteroid();

        starknet::testing::set_contract_address(starknet::contract_address_const::<'ADMIN'>());
        IAsteroidDispatcher { contract_address: asteroid_address }
            .add_grant(starknet::contract_address_const::<'DISPATCHER'>(), 2);

        let asteroids = array![
            SeedAsteroids::SeededAsteroid { asteroid_id: 1, name: 'Adalia Prime' },
            SeedAsteroids::SeededAsteroid { asteroid_id: 2, name: 'Adalia Subprime' }
        ].span();

        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        let mut state = SeedAsteroids::contract_state_for_testing();
        SeedAsteroids::run(ref state, asteroids, Context {
            caller: starknet::contract_address_const::<1>(),
            now: starknet::get_block_timestamp(),
            payment_to: starknet::contract_address_const::<0>(),
            payment_amount: 0
        });
    }

    #[test]
    #[available_gas(5000000)]
    #[should_panic]
    fn test_already_exists() {
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        helpers::init();
        let asteroid_address = helpers::deploy_asteroid();

        starknet::testing::set_contract_address(starknet::contract_address_const::<'ADMIN'>());
        IAsteroidDispatcher { contract_address: asteroid_address }
            .add_grant(starknet::contract_address_const::<'DISPATCHER'>(), 2);

        let asteroids = array![SeedAsteroids::SeededAsteroid { asteroid_id: 1, name: 'Adalia Prime' }].span();
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        let mut state = SeedAsteroids::contract_state_for_testing();
        SeedAsteroids::run(ref state, asteroids, mocks::context('ADMIN'));
        SeedAsteroids::run(ref state, asteroids, mocks::context('ADMIN'));
  }
}
