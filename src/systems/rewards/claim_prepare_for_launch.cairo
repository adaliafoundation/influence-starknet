#[starknet::contract]
mod ClaimPrepareForLaunchReward {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use starknet::contract_address::ContractAddress;
    use traits::{Into, TryInto};

    use influence::{components, contracts};
    use influence::common::crew::CrewDetailsTrait;
    use influence::components::{Crew, CrewTrait, Unique, UniqueTrait,
        celestial::{statuses as scan_statuses, Celestial, CelestialTrait},
        crewmate::{collections, titles, Crewmate, CrewmateTrait}};
    use influence::config::{entities, errors};
    use influence::contracts::asteroid::{IAsteroidDispatcher, IAsteroidDispatcherTrait};
    use influence::contracts::crewmate::{ICrewmateDispatcher, ICrewmateDispatcherTrait};
    use influence::types::{Context, Entity, EntityTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct PrepareForLaunchRewardClaimed {
        asteroid: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        PrepareForLaunchRewardClaimed: PrepareForLaunchRewardClaimed
    }

    #[external(v0)]
    fn run(ref self: ContractState, asteroid: Entity, context: Context) {
        // Only the account owner of asteroid can claim
        let owner = IAsteroidDispatcher { contract_address: contracts::get('Asteroid') }.owner_of(asteroid.id.into());
        assert(owner == context.caller, errors::INCORRECT_OWNER);

        // Check the asteroid is in the correct purchase order range
        let celestial_data = components::get::<Celestial>(asteroid.path()).expect(errors::CELESTIAL_NOT_FOUND);
        assert(
            celestial_data.purchase_order > 11100 && celestial_data.purchase_order <= 11468,
            errors::REWARD_NOT_FOUND
        );

        // Check that the asteroid hasn't already been used to claim
        let mut path: Array<felt252> = Default::default();
        path.append(asteroid.into());
        path.append('PrepareForLaunchRewardClaimed');
        assert(components::get::<Unique>(path.span()).is_none(), errors::REWARD_ALREADY_CLAIMED);
        components::set::<Unique>(path.span(), Unique { unique: 1 }); // set it to used

        // Grant an Adalian crewmate credit
        let id = ICrewmateDispatcher { contract_address: contracts::get('Crewmate') }.mint_with_auto_id(context.caller);

        // Add the unique "First Generation" title to the crewmate
        let crewmate = EntityTrait::new(entities::CREWMATE, id.try_into().unwrap());
        let mut crewmate_data = CrewmateTrait::new(collections::ADALIAN);
        crewmate_data.title = titles::FIRST_GENERATION;
        components::set::<Crewmate>(crewmate.path(), crewmate_data);

        self.emit(PrepareForLaunchRewardClaimed {
            asteroid: asteroid,
            caller: context.caller
        });
    }
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;

    use influence::{components, config};
    use influence::components::{Celestial, CelestialTrait, crewmate::{titles, Crewmate}};
    use influence::config::entities;
    use influence::contracts::asteroid::{IAsteroidDispatcher, IAsteroidDispatcherTrait};
    use influence::contracts::crewmate::{ICrewmateDispatcher, ICrewmateDispatcherTrait};
    use influence::test::{helpers, mocks};
    use influence::types::{Context, Entity, EntityTrait};

    use super::ClaimPrepareForLaunchReward;

    #[test]
    #[available_gas(15000000)]
    fn test_claim() {
        helpers::init();
        config::set('TIME_ACCELERATION', 24);

        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        let asteroid_address = helpers::deploy_asteroid();
        let crewmate_address = helpers::deploy_crewmate();

        starknet::testing::set_contract_address(starknet::contract_address_const::<'ADMIN'>());
        IAsteroidDispatcher { contract_address: asteroid_address }
            .add_grant(starknet::contract_address_const::<'DISPATCHER'>(), 2);
        ICrewmateDispatcher { contract_address: crewmate_address }
            .add_grant(starknet::contract_address_const::<'DISPATCHER'>(), 2);

        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        let id = IAsteroidDispatcher { contract_address: asteroid_address }.mint_with_id(
            starknet::contract_address_const::<'PLAYER'>(), 104
        );

        let asteroid = influence::test::mocks::asteroid();

        let mut celestial_data = components::get::<Celestial>(asteroid.path()).unwrap();
        celestial_data.purchase_order = 11101;
        components::set::<Celestial>(asteroid.path(), celestial_data);

        let mut state = ClaimPrepareForLaunchReward::contract_state_for_testing();
        ClaimPrepareForLaunchReward::run(ref state, asteroid, mocks::context('PLAYER'));

        // Check the crewmate was minted
        let crewmate = EntityTrait::new(entities::CREWMATE, 20000);
        let crewmate_data = components::get::<Crewmate>(crewmate.path()).unwrap();
        assert(crewmate_data.title == titles::FIRST_GENERATION, 'incorrect title');
    }
}
