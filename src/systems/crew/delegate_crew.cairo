// Delegates control of a crew to an account address

#[starknet::contract]
mod DelegateCrew {
    use array::{Array, ArrayTrait};
    use option::OptionTrait;
    use starknet::{contract_address_const, ContractAddress};
    use traits::Into;

    use influence::{components, contracts};
    use influence::common::nft;
    use influence::components::crew::{Crew, CrewTrait};
    use influence::config::{entities, errors};
    use influence::types::{Context, Entity, EntityTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct CrewDelegated {
        delegated_to: ContractAddress,
        crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        CrewDelegated: CrewDelegated
    }

    #[external(v0)]
    fn run(ref self: ContractState, delegated_to: ContractAddress, caller_crew: Entity, context: Context) {
        let mut crew_data = components::get::<Crew>(caller_crew.path()).expect(errors::CREW_NOT_FOUND);

        // Ensure caller owns the crew
        let contract_address = contracts::get('Crew');
        nft::assert_owner('Crew', caller_crew, context.caller);

        // Delegate to the new address and update
        crew_data.delegated_to = delegated_to.into();
        components::set::<Crew>(caller_crew.path(), crew_data);

        self.emit(CrewDelegated {
            delegated_to: delegated_to,
            crew: caller_crew,
            caller: context.caller
        });
    }
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use option::OptionTrait;
    use traits::TryInto;

    use influence::components;
    use influence::components::crew::{Crew, CrewTrait};
    use influence::config::entities;
    use influence::contracts::crew::{ICrewDispatcher, ICrewDispatcherTrait};
    use influence::types::entity::EntityTrait;
    use influence::test::{helpers, mocks};

    use super::DelegateCrew;

    #[test]
    #[available_gas(5000000)]
    fn test_delegate() {
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        helpers::init();
        let crew_address = helpers::deploy_crew();

        starknet::testing::set_contract_address(starknet::contract_address_const::<'ADMIN'>());
        ICrewDispatcher { contract_address: crew_address }
            .add_grant(starknet::contract_address_const::<'DISPATCHER'>(), 2);

        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        let id = ICrewDispatcher { contract_address: crew_address }.mint_with_auto_id(
            starknet::contract_address_const::<'PLAYER'>()
        );

        let crew = EntityTrait::new(entities::CREW, id.try_into().unwrap());
        components::set::<Crew>(crew.path(), CrewTrait::new(starknet::contract_address_const::<'PLAYER'>()));

        let mut state = DelegateCrew::contract_state_for_testing();
        DelegateCrew::run(
            ref state,
            starknet::contract_address_const::<'OTHER_PLAYER'>(),
            crew,
            mocks::context('PLAYER')
        );

        let crew_data = components::get::<Crew>(crew.path()).unwrap();
        assert(crew_data.delegated_to == starknet::contract_address_const::<'OTHER_PLAYER'>(), 'delegate incorrect');
    }

    #[test]
    #[available_gas(5000000)]
    #[should_panic(expected: ('not owner', ))]
    fn test_wrong_owner() {
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        helpers::init();
        let crew_address = helpers::deploy_crew();

        starknet::testing::set_contract_address(starknet::contract_address_const::<'ADMIN'>());
        ICrewDispatcher { contract_address: crew_address }
            .add_grant(starknet::contract_address_const::<'DISPATCHER'>(), 2);


        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        let id = ICrewDispatcher { contract_address: crew_address }.mint_with_auto_id(
            starknet::contract_address_const::<'OTHER_PLAYER'>()
        );

        let crew = EntityTrait::new(entities::CREW, id.try_into().unwrap());
        components::set::<Crew>(crew.path(), CrewTrait::new(starknet::contract_address_const::<'OTHER_PLAYER'>()));

        let mut state = DelegateCrew::contract_state_for_testing();
        DelegateCrew::run(
            ref state,
            starknet::contract_address_const::<'PLAYER'>(),
            crew,
            mocks::context('PLAYER')
        );
    }
}