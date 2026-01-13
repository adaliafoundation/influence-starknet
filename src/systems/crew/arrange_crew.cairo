#[starknet::contract]
mod ArrangeCrew {
    use array::{ArrayTrait, Span, SpanTrait};
    use option::OptionTrait;
    use starknet::ContractAddress;
    use traits::{Into, TryInto};

    use influence::{components, contracts};
    use influence::common::crew::CrewDetailsTrait;
    use influence::components::{Crew, CrewTrait};
    use influence::config::{errors, entities};
    use influence::types::{SpanTraitExt, Context, Entity, EntityTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct CrewmatesArranged {
        composition: Span<u64>,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[derive(Copy, Drop, starknet::Event)]
    struct CrewmatesArrangedV1 {
        composition_old: Span<u64>,
        composition_new: Span<u64>,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        CrewmatesArranged: CrewmatesArranged,
        CrewmatesArrangedV1: CrewmatesArrangedV1
    }

    #[external(v0)]
    fn run(ref self: ContractState, composition: Span<u64>, caller_crew: Entity, context: Context) {
        // Check that crew is delegated, ready (allowed pre-launch)
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_delegated_to(context.caller);
        crew_details.assert_manned();
        crew_details.assert_ready(context.now);
        crew_details.assert_not_in_emergency();
        crew_details.assert_building_operational();
        let mut crew_data = crew_details.component;

        // Check that old and new crew is the same size
        assert(crew_data.roster.len() == composition.len(), errors::INCORRECT_CREW_SIZE);

        // Checks that each crewmate is present in the new roster and not duplicated
        let mut length = crew_data.roster.len();
        let mut iter = 0;

        loop {
            if (iter >= length) { break; }
            let to_check = crew_data.roster.at(iter);

            let in1 = crew_data.roster.occurrences_of(*to_check);
            let in2 = composition.occurrences_of(*to_check);

            assert(in1 + in2 == 2, errors::CREW_ROSTER_MISMATCH);
            iter += 1;
        };

        // Update the crews
        let composition_old = crew_data.roster;
        crew_data.roster = composition;
        components::set::<Crew>(caller_crew.path(), crew_data);

        self.emit(CrewmatesArrangedV1 {
            composition_old: composition_old,
            composition_new: crew_data.roster,
            caller_crew: caller_crew,
            caller: context.caller
        });
    }
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use traits::Into;

    use influence::components;
    use influence::components::{Crew, CrewTrait, Crewmate, CrewmateTrait, Location, LocationTrait};
    use influence::config;
    use influence::test::{helpers, mocks};
    use influence::types::{Entity, EntityTrait};

    use super::ArrangeCrew;

    #[test]
    #[available_gas(10000000)]
    fn test_arrange_crew() {
        helpers::init();
        config::set('TIME_ACCELERATION', 24);
        starknet::testing::set_block_timestamp(100);

        let asteroid = influence::test::mocks::asteroid();
        let crew = influence::test::mocks::delegated_crew(1, 'PLAYER');
        let station = influence::test::mocks::public_habitat(crew, 37);
        components::set::<Location>(crew.path(), LocationTrait::new(station));

        // Add a couple crewmates to crew
        let mut crew_data = components::get::<Crew>(crew.path()).unwrap();
        crew_data.roster = array![1, 2, 3].span();
        components::set::<Crew>(crew.path(), crew_data);
        crew_data = components::get::<Crew>(crew.path()).unwrap();

        // Try to re-arrange crew
        let roster: Span<u64> = array![3, 2, 1].span();
        let mut state = ArrangeCrew::contract_state_for_testing();
        ArrangeCrew::run(ref state, roster, crew, mocks::context('PLAYER'));

        crew_data = components::get::<Crew>(crew.path()).unwrap();
        assert(*crew_data.roster.at(0) == 3, 'incorrect crewmate');
        assert(*crew_data.roster.at(1) == 2, 'incorrect crewmate');
        assert(*crew_data.roster.at(2) == 1, 'incorrect crewmate');
    }

    #[test]
    #[available_gas(10000000)]
    #[should_panic(expected: ('E6010: incorrect crew size', ))]
    fn test_wrong_size() {
        helpers::init();
        config::set('TIME_ACCELERATION', 24);
        starknet::testing::set_block_timestamp(100);

        let asteroid = influence::test::mocks::asteroid();
        let crew = influence::test::mocks::delegated_crew(1, 'PLAYER');
        let station = influence::test::mocks::public_habitat(crew, 37);
        components::set::<Location>(crew.path(), LocationTrait::new(station));

        // Add a couple crewmates to crew
        let mut crew_data = components::get::<Crew>(crew.path()).unwrap();
        crew_data.roster = array![1, 2, 3].span();
        components::set::<Crew>(crew.path(), crew_data);
        crew_data = components::get::<Crew>(crew.path()).unwrap();

        // Try to re-arrange crew
        let roster: Span<u64> = array![3, 2].span();
        let mut state = ArrangeCrew::contract_state_for_testing();
        ArrangeCrew::run(ref state, roster, crew, mocks::context('PLAYER'));
    }

    #[test]
    #[available_gas(10000000)]
    #[should_panic(expected: ('E6011: crew roster mismatch', ))]
    fn test_mismatch() {
        helpers::init();
        config::set('TIME_ACCELERATION', 24);
        starknet::testing::set_block_timestamp(100);

        let asteroid = influence::test::mocks::asteroid();
        let crew = influence::test::mocks::delegated_crew(1, 'PLAYER');
        let station = influence::test::mocks::public_habitat(crew, 37);
        components::set::<Location>(crew.path(), LocationTrait::new(station));

        // Add a couple crewmates to crew
        let mut crew_data = components::get::<Crew>(crew.path()).unwrap();
        crew_data.roster = array![1, 2, 3].span();
        components::set::<Crew>(crew.path(), crew_data);
        crew_data = components::get::<Crew>(crew.path()).unwrap();

        // Try to re-arrange crew
        let roster: Span<u64> = array![3, 2, 4].span();
        let mut state = ArrangeCrew::contract_state_for_testing();
        ArrangeCrew::run(ref state, roster, crew, mocks::context('PLAYER'));
    }
}