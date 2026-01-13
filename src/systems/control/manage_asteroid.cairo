// Allows a crew delegated to the actual account owner of an asteroid to regain control of it

#[starknet::contract]
mod ManageAsteroid {
    use array::{Array, ArrayTrait};
    use option::OptionTrait;
    use starknet::{contract_address_const, ContractAddress};
    use traits::Into;

    use influence::common::{config::entities, crew::CrewDetailsTrait, nft};
    use influence::{components, contracts};
    use influence::components::{Crew, CrewTrait, Control, ControlTrait};
    use influence::types::{Context, Entity, EntityTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct AsteroidManaged {
        asteroid: Entity,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        AsteroidManaged: AsteroidManaged
    }

    #[external(v0)]
    fn run(ref self: ContractState, asteroid: Entity, caller_crew: Entity, context: Context) {
        // Check that crew is delegated, and ready
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_delegated_to(context.caller);

        // Ensure that the caller is the owner of the asteroid
        let contract_address = contracts::get('Asteroid');
        nft::assert_owner('Asteroid', asteroid, context.caller);

        components::set::<Control>(asteroid.path(), ControlTrait::new(caller_crew));
        self.emit(AsteroidManaged {
            asteroid: asteroid,
            caller_crew: caller_crew,
            caller: context.caller
        });
    }
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use option::OptionTrait;
    use traits::TryInto;
    use starknet::testing;

    use influence::components;
    use influence::components::Control;
    use influence::contracts::asteroid::{IAsteroidDispatcher, IAsteroidDispatcherTrait};
    use influence::types::entity::EntityTrait;
    use influence::test::{helpers, mocks};

    use super::ManageAsteroid;

    #[test]
    #[available_gas(8000000)]
    fn test_manage_asteroid() {
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        let asteroid_address = helpers::deploy_asteroid();

        starknet::testing::set_contract_address(starknet::contract_address_const::<'ADMIN'>());
        IAsteroidDispatcher { contract_address: asteroid_address }
            .add_grant(starknet::contract_address_const::<'DISPATCHER'>(), 2);

        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        let id = IAsteroidDispatcher { contract_address: asteroid_address }.mint_with_id(
            starknet::contract_address_const::<'PLAYER'>(), 104
        );

        let crew = influence::test::mocks::delegated_crew(27, 'PLAYER');
        let asteroid = influence::test::mocks::asteroid();
        let mut state = ManageAsteroid::contract_state_for_testing();
        ManageAsteroid::run(ref state, asteroid, crew, mocks::context('PLAYER'));

        let control_data = components::get::<Control>(asteroid.path()).expect('control not set');
        assert(control_data.controller == crew, 'control not transferred');
    }

    #[test]
    #[available_gas(8000000)]
    #[should_panic(expected: ('not owner', ))]
    fn test_manage_asteroid_fail() {
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        let asteroid_address = helpers::deploy_asteroid();

        starknet::testing::set_contract_address(starknet::contract_address_const::<'ADMIN'>());
        IAsteroidDispatcher { contract_address: asteroid_address }
            .add_grant(starknet::contract_address_const::<'DISPATCHER'>(), 2);

        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        let id = IAsteroidDispatcher { contract_address: asteroid_address }.mint_with_id(
            starknet::contract_address_const::<'PLAYER'>(), 104
        );

        let crew = influence::test::mocks::delegated_crew(27, 'OTHER_PLAYER');
        let asteroid = influence::test::mocks::asteroid();
        let mut state = ManageAsteroid::contract_state_for_testing();
        ManageAsteroid::run(ref state, asteroid, crew, mocks::context('OTHER_PLAYER'));
    }
}