#[starknet::contract]
mod CheckForRandomEvent {
    use array::{ArrayTrait, SpanTrait};

    use influence::common::random;
    use influence::common::crew::{CrewDetails, CrewDetailsTrait};
    use influence::config::{actions, random_events};
    use influence::types::{ArrayHashTrait, Context, Entity, EntityTrait};

    use influence::systems::random_events::helpers::resolve_event;

    #[storage]
    struct Storage {}

    #[external(v0)]
    fn run(self: @ContractState, caller_crew: Entity, context: Context) -> u64 {
        // Check that crew is delegated
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        let mut crew_data = crew_details.component;

        // Check there is an action to process
        if crew_data.action_type == 0 { return 0; }
        if crew_data.action_round + 10 >= random::get_current_round(crew_data.action_strategy) { return 0; }

        // Check for random events that may apply to the action and attempt to resolve them
        let mut pending_event = 0;
        let action_config = actions::config(crew_data.action_type);
        let mut iter = 0;

        loop {
            if iter >= (*action_config.random_events).len() { break; }
            let random_event = (*action_config.random_events).at(iter);

            if resolve_event(*random_event, 0, crew_details) {
                pending_event = *random_event;
                break;
            }

            iter += 1;
        };

        return pending_event;
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

    use super::CheckForRandomEvent;

    // TODO: figure out how to have both random and time acceleration set properly
    // #[test]
    // #[available_gas(25000000)]
    // fn test_resolve_event() {
    //     helpers::init();
    //     starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
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

    //     let mut state = CheckForRandomEvent::contract_state_for_testing();
    //     let res = CheckForRandomEvent::run(@state, crew, mocks::context('PLAYER'));
    // }
}
