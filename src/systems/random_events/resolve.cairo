#[starknet::contract]
mod ResolveRandomEvent {
    use array::{Array, ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use starknet::ContractAddress;
    use traits::Into;

    use influence::{components, contracts};
    use influence::common::random;
    use influence::common::crew::{CrewDetails, CrewDetailsTrait};
    use influence::components::{Crew, CrewTrait};
    use influence::config::{actions, errors, random_events};
    use influence::systems::random_events::helpers::resolve_event;
    use influence::types::{ArrayHashTrait, Context, Entity, EntityTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct RandomEventResolved {
        random_event: u64,
        choice: u64,
        action_type: u64,
        action_target: Entity,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        RandomEventResolved: RandomEventResolved
    }

    #[external(v0)]
    fn run(ref self: ContractState, choice: u64, caller_crew: Entity, context: Context) {
        // Check that crew is delegated
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_delegated_to(context.caller);
        let mut crew_data = crew_details.component;

        // If no crew action is set just skip
        if crew_data.action_type == 0 { return; }

        // If action is not ready to be resolved just skip
        if crew_data.action_round + 10 >= random::get_current_round(crew_data.action_strategy) { return; }

        // Check for random events that may apply to the action and attempt to resolve them
        let action_config = actions::config(crew_data.action_type);
        let mut iter = 0;

        loop {
            if iter >= (*action_config.random_events).len() { break; }
            let random_event = (*action_config.random_events).at(iter);

            if resolve_event(*random_event, choice, crew_details) {
                self.emit(RandomEventResolved {
                    random_event: *random_event,
                    choice: choice,
                    action_type: crew_data.action_type,
                    action_target: crew_data.action_target,
                    caller_crew: caller_crew,
                    caller: context.caller
                });

                break;
            }

            iter += 1;
        };

        // Clear action
        crew_data.action_type = 0;
        crew_data.action_target = EntityTrait::new(0, 0);
        crew_data.action_strategy = 0;
        crew_data.action_round = 0;
        crew_data.action_weight = 0;
        components::set::<Crew>(caller_crew.path(), crew_data);
    }
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use option::OptionTrait;
    use traits::{Into, TryInto};

    use influence::{components, config};
    use influence::common::random;
    use influence::components::{Crew, CrewTrait, Location, LocationTrait};
    use influence::contracts::sway::{ISwayDispatcher, ISwayDispatcherTrait};
    use influence::test::{helpers, mocks};
    use influence::types::{Entity, EntityTrait};

    use super::ResolveRandomEvent;

    // TODO: figure out how to have both random and time acceleration set properly
    // #[test]
    // #[available_gas(25000000)]
    // fn test_resolve_event() {
    //     starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
    //     helpers::init();
    //     config::set('TIME_ACCELERATION', 24);

    //     // Deploy SWAY
    //     let sway_address = helpers::deploy_sway();
    //     let amount: u256 = (100 * 1000000).into();
    //     starknet::testing::set_contract_address(starknet::contract_address_const::<'ADMIN'>());
    //     ISwayDispatcher { contract_address: sway_address }.mint(starknet::contract_address_const::<'DISPATCHER'>(), amount);
    //     starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());

    //     let asteroid = influence::test::mocks::asteroid();
    //     let crew = influence::test::mocks::delegated_crew(1, 'PLAYER');

    //     // Setup station
    //     let station = influence::test::mocks::public_habitat(crew, 1);
    //     components::set::<Location>(station.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1)));
    //     components::set::<Location>(crew.path(), LocationTrait::new(station));

    //     let mut crew_data = components::get::<Crew>(crew.path()).unwrap();
    //     crew_data.action_type = 1;
    //     crew_data.action_target = EntityTrait::new(7, 1);
    //     crew_data.action_strategy = 1;
    //     crew_data.action_round = 1;
    //     crew_data.action_weight = 1;
    //     components::set::<Crew>(crew.path(), crew_data);

    //     random::entropy::generate(); // make sure we have at least one round of randomness

    //     let mut state = ResolveRandomEvent::contract_state_for_testing();
    //     ResolveRandomEvent::run(ref state, 1, crew, mocks::context('PLAYER'));

    //     // Confirm actions cleared
    //     crew_data = components::get::<Crew>(crew.path()).unwrap();
    //     assert(crew_data.action_type == 0, 'wrong action type');
    //     assert(crew_data.action_target == EntityTrait::new(0, 0), 'wrong action target');
    //     assert(crew_data.action_strategy == 0, 'wrong action strategy');
    //     assert(crew_data.action_round == 0, 'wrong action round');
    //     assert(crew_data.action_weight == 0, 'wrong action weight');
    // }

    #[test]
    #[available_gas(25000000)]
    fn test_resolve_fail_silent() {
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        helpers::init();
        config::set('TIME_ACCELERATION', 24);

        let asteroid = influence::test::mocks::asteroid();
        let crew = influence::test::mocks::delegated_crew(1, 'PLAYER');

        // Setup station
        let station = influence::test::mocks::public_habitat(crew, 1);
        components::set::<Location>(station.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1)));
        components::set::<Location>(crew.path(), LocationTrait::new(station));

        random::entropy::generate(); // make sure we have at least one round of randomness

        let mut state = ResolveRandomEvent::contract_state_for_testing();
        ResolveRandomEvent::run(ref state, 1, crew, mocks::context('PLAYER'));
    }
}
