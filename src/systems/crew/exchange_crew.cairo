#[starknet::contract]
mod ExchangeCrew {
    use array::{ArrayTrait, Span, SpanTrait};
    use cmp::max;
    use option::OptionTrait;
    use starknet::ContractAddress;
    use traits::{Into, TryInto};

    use influence::common::{crew::{CrewDetailsTrait, time_since_fed}};
    use influence::{components, contracts};
    use influence::components::{Control, ControlTrait, Crew, CrewTrait, Location, LocationTrait};
    use influence::config::{errors, entities};
    use influence::contracts::crew::{ICrewDispatcher, ICrewDispatcherTrait};
    use influence::contracts::crewmate::{ICrewmateDispatcher, ICrewmateDispatcherTrait};
    use influence::systems::helpers::create_crew;
    use influence::types::{SpanTraitExt, Context, Entity, EntityTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct CrewmatesExchanged {
        crew1: Entity,
        crew1_composition_old: Span<u64>,
        crew1_composition_new: Span<u64>,
        crew2: Entity,
        crew2_composition_old: Span<u64>,
        crew2_composition_new: Span<u64>,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        CrewmatesExchanged: CrewmatesExchanged
    }

    #[external(v0)]
    fn run(
        ref self: ContractState, crew1: Entity, comp1: Span<u64>, _crew2: Entity, comp2: Span<u64>, context: Context
    ) {
        // Get first crew, which must be pre-existing
        let mut crew1_details = CrewDetailsTrait::new(crew1);
        let mut crew1_data = crew1_details.component;
        let crew1_delegated = crew1_data.delegated_to == context.caller;

        // Get second crew which may be new / empty
        let crew2 = match components::get::<Crew>(_crew2.path()) {
            Option::Some(data) => _crew2,
            Option::None(_) => {
                let (crew, _) = create_crew(crew1_details.location(), context.caller);
                crew
            }
        };

        let mut crew2_details = CrewDetailsTrait::new(crew2);
        let mut crew2_data = crew2_details.component;

        let location2 = components::get::<Location>(crew2.path()).expect(errors::LOCATION_NOT_FOUND);
        let crew2_delegated = crew2_data.delegated_to == context.caller;

        // Ensure crews are co-located
        assert(crew1_details.location() == location2.location, errors::INCORRECT_LOCATION);

        // Ensure total crewmates match before / after
        let current_length = crew1_data.roster.len() + crew2_data.roster.len();
        let new_length = comp1.len() + comp2.len();
        assert(new_length == current_length, errors::INCORRECT_CREW_SIZE);

        // Cache how much food each crewmate has
        let crew1_food_per_crewmate = crew1_details.current_food(context.now);
        let crew2_food_per_crewmate = crew2_details.current_food(context.now);
        let mut crew1_food_new = 0;
        let mut crew2_food_new = 0;

        // Checks that each crewmate is present in the new roster and not duplicated
        let mut length = crew1_data.roster.len();
        let mut iter = 0;

        // Checks for crewmates moved to crew 2
        loop {
            if (iter >= length) { break; }

            let to_check = crew1_data.roster.at(iter);
            let in1 = comp1.occurrences_of(*to_check);
            let in2 = comp2.occurrences_of(*to_check);
            assert(in1 + in2 == 1, errors::CREW_ROSTER_MISMATCH);

            // Checks if the crewmate is moved, then checks the move is allowed
            if in2 == 1 {
                assert_can_move_crewmate(context.caller, crew1_delegated, crew2_delegated, *to_check);
                let crewmate = EntityTrait::new(entities::CREWMATE, *to_check);
                components::set::<Control>(crewmate.path(), ControlTrait::new(crew2));
                crew2_food_new += crew1_food_per_crewmate;
            } else {
                crew1_food_new += crew1_food_per_crewmate;
            }

            iter += 1;
        };

        length = crew2_data.roster.len();
        iter = 0;

        // Checks for crewmates moved to crew 1
        loop {
            if (iter >= length) { break; }

            let to_check = crew2_data.roster.at(iter);
            let in1 = comp1.occurrences_of(*to_check);
            let in2 = comp2.occurrences_of(*to_check);
            assert(in1 + in2 == 1, errors::CREW_ROSTER_MISMATCH);

            // Checks if the crewmate is moved, then checks the move is allowed
            if in1 == 1 {
                assert_can_move_crewmate(context.caller, crew2_delegated, crew1_delegated, *to_check);
                let crewmate = EntityTrait::new(entities::CREWMATE, *to_check);
                components::set::<Control>(crewmate.path(), ControlTrait::new(crew1));
                crew1_food_new += crew2_food_per_crewmate;
            } else {
                crew2_food_new += crew2_food_per_crewmate;
            }

            iter += 1;
        };

        let crew1_old = crew1_data.roster;
        let crew2_old = crew2_data.roster;
        crew1_data.roster = comp1;
        crew2_data.roster = comp2;

        // Divide new crew food by new roster len (unless crew is empty)
        let crew1_new_length: felt252 = comp1.len().into();
        let crew1_since_fed = match crew1_new_length {
            0 => context.now,
            _ => time_since_fed(crew1_food_new / crew1_new_length.try_into().unwrap(), crew1_details.consume_mod())
        };

        let crew2_new_length: felt252 = comp2.len().into();

        let crew2_since_fed = match crew2_new_length {
            0 => context.now,
            _ => time_since_fed(crew2_food_new / crew2_new_length.try_into().unwrap(), crew2_details.consume_mod())
        };

        // Update last fed times
        if crew1_since_fed < context.now {
            crew1_data.last_fed = context.now - crew1_since_fed;
        } else {
            crew1_data.last_fed = 0;
        }

        if crew2_since_fed < context.now {
            crew2_data.last_fed = context.now - crew2_since_fed;
        } else {
            crew2_data.last_fed = 0;
        }

        // Update ready times
        let latest_ready_at = max(crew1_data.ready_at, crew2_data.ready_at);
        crew1_data.ready_at = latest_ready_at;
        crew2_data.ready_at = latest_ready_at;

        // Ensure the second crew is set to the same location (i.e. if it was empty)
        components::set::<Location>(crew2.path(), LocationTrait::new(crew1_details.location()));

        // Update the crews
        components::set::<Crew>(crew1.path(), crew1_data);
        components::set::<Crew>(crew2.path(), crew2_data);

        self.emit(CrewmatesExchanged {
            crew1: crew1,
            crew1_composition_old: crew1_old,
            crew1_composition_new: crew1_data.roster,
            crew2: crew2,
            crew2_composition_old: crew2_old,
            crew2_composition_new: crew2_data.roster,
            caller: context.caller
        });
    }

    fn assert_can_move_crewmate(caller: ContractAddress, origin_delegate: bool, dest_delegate: bool, crewmate: u64) {
        let crewmate_address = contracts::get('Crewmate');
        let owner = ICrewmateDispatcher { contract_address: crewmate_address }.owner_of(crewmate.into());

        if (!dest_delegate) {
            assert(false, errors::INCORRECT_DELEGATE);
        } else if (!origin_delegate && owner != caller) {
            assert(false, errors::INCORRECT_OWNER);
        }
    }
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use traits::Into;

    use influence::{components, config};
    use influence::components::{Crew, CrewTrait, Location, LocationTrait,
        crewmate::{classes, collections, Crewmate, CrewmateTrait}};
    use influence::config::entities;
    use influence::contracts::crew::{ICrewDispatcher, ICrewDispatcherTrait};
    use influence::contracts::crewmate::{ICrewmateDispatcher, ICrewmateDispatcherTrait};
    use influence::test::{helpers, mocks};
    use influence::types::{Entity, EntityTrait};

    use super::ExchangeCrew;

    #[test]
    #[available_gas(25000000)]
    fn test_exchange_crew() {
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        helpers::init();
        mocks::constants();
        starknet::testing::set_block_timestamp(100);

        let crewmate_address = helpers::deploy_crewmate();

        starknet::testing::set_contract_address(starknet::contract_address_const::<'ADMIN'>());
        ICrewmateDispatcher { contract_address: crewmate_address }
            .add_grant(starknet::contract_address_const::<'DISPATCHER'>(), 2);

        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        let player = starknet::contract_address_const::<'PLAYER'>();

        let default_crewmate = Crewmate {
            status: 1,
            collection: collections::ADALIAN,
            class: classes::MINER,
            title: 0,
            appearance: 0,
            impactful: Default::default().span(),
            cosmetic: Default::default().span()
        };

        ICrewmateDispatcher { contract_address: crewmate_address }.mint_with_auto_id(player);
        components::set::<Crewmate>(EntityTrait::new(entities::CREWMATE, 1).path(), default_crewmate);
        ICrewmateDispatcher { contract_address: crewmate_address }.mint_with_auto_id(player);
        components::set::<Crewmate>(EntityTrait::new(entities::CREWMATE, 2).path(), default_crewmate);
        ICrewmateDispatcher { contract_address: crewmate_address }.mint_with_auto_id(player);
        components::set::<Crewmate>(EntityTrait::new(entities::CREWMATE, 3).path(), default_crewmate);
        ICrewmateDispatcher { contract_address: crewmate_address }.mint_with_auto_id(player);
        components::set::<Crewmate>(EntityTrait::new(entities::CREWMATE, 4).path(), default_crewmate);

        let asteroid = influence::test::mocks::asteroid();

        // Add a couple crewmates to crew
        let crew1 = influence::test::mocks::delegated_crew(1, 'PLAYER');
        let station = influence::test::mocks::public_habitat(crew1, 37);
        components::set::<Location>(crew1.path(), LocationTrait::new(station));
        let mut crew1_data = components::get::<Crew>(crew1.path()).unwrap();
        crew1_data.roster = array![1, 2, 3].span();
        components::set::<Crew>(crew1.path(), crew1_data);
        crew1_data = components::get::<Crew>(crew1.path()).unwrap();

        // Add some to another crew
        let crew2 = influence::test::mocks::delegated_crew(2, 'PLAYER');
        components::set::<Location>(crew2.path(), LocationTrait::new(station));
        let mut crew2_data = components::get::<Crew>(crew2.path()).unwrap();
        crew2_data.roster = array![4].span();
        components::set::<Crew>(crew2.path(), crew2_data);
        crew2_data = components::get::<Crew>(crew2.path()).unwrap();

        // Try to re-arrange crew
        let roster1: Span<u64> = array![1, 2].span();
        let roster2: Span<u64> = array![3, 4].span();
        let mut state = ExchangeCrew::contract_state_for_testing();
        ExchangeCrew::run(ref state, crew1, roster1, crew2, roster2, mocks::context('PLAYER'));

        // Check rosters
        crew1_data = components::get::<Crew>(crew1.path()).unwrap();
        assert(crew1_data.roster.len() == roster1.len(), 'crew 1 roster incorrect');
        crew2_data = components::get::<Crew>(crew2.path()).unwrap();
        assert(crew2_data.roster.len() == roster2.len(), 'crew 2 roster incorrect');
    }

    #[test]
    #[available_gas(20000000)]
    fn test_exchange_to_new_crew() {
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        helpers::init();
        mocks::constants();
        starknet::testing::set_block_timestamp(100);

        let crewmate_address = helpers::deploy_crewmate();
        let crew_address = helpers::deploy_crew();

        starknet::testing::set_contract_address(starknet::contract_address_const::<'ADMIN'>());
        ICrewmateDispatcher { contract_address: crewmate_address }
            .add_grant(starknet::contract_address_const::<'DISPATCHER'>(), 2);

        ICrewDispatcher { contract_address: crew_address }
            .add_grant(starknet::contract_address_const::<'DISPATCHER'>(), 2);

        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        let player = starknet::contract_address_const::<'PLAYER'>();

        let default_crewmate = Crewmate {
            status: 1,
            collection: collections::ADALIAN,
            class: classes::MINER,
            title: 0,
            appearance: 0,
            impactful: Default::default().span(),
            cosmetic: Default::default().span()
        };

        ICrewmateDispatcher { contract_address: crewmate_address }.mint_with_auto_id(player);
        components::set::<Crewmate>(EntityTrait::new(entities::CREWMATE, 1).path(), default_crewmate);
        ICrewmateDispatcher { contract_address: crewmate_address }.mint_with_auto_id(player);
        components::set::<Crewmate>(EntityTrait::new(entities::CREWMATE, 2).path(), default_crewmate);
        ICrewmateDispatcher { contract_address: crewmate_address }.mint_with_auto_id(player);
        components::set::<Crewmate>(EntityTrait::new(entities::CREWMATE, 3).path(), default_crewmate);
        ICrewmateDispatcher { contract_address: crewmate_address }.mint_with_auto_id(player);
        components::set::<Crewmate>(EntityTrait::new(entities::CREWMATE, 4).path(), default_crewmate);

        let asteroid = influence::test::mocks::asteroid();

        // Add a couple crewmates to crew
        let crew1 = influence::test::mocks::delegated_crew(1, 'PLAYER');
        let station = influence::test::mocks::public_habitat(crew1, 37);
        components::set::<Location>(crew1.path(), LocationTrait::new(station));
        let mut crew1_data = components::get::<Crew>(crew1.path()).unwrap();
        crew1_data.roster = array![1, 2, 3, 4].span();
        components::set::<Crew>(crew1.path(), crew1_data);
        crew1_data = components::get::<Crew>(crew1.path()).unwrap();

        // Try to re-arrange crew
        let roster1: Span<u64> = array![1, 2].span();
        let roster2: Span<u64> = array![3, 4].span();
        let mut state = ExchangeCrew::contract_state_for_testing();
        ExchangeCrew::run(
            ref state, crew1, roster1, EntityTrait::new(entities::CREW, 0), roster2, mocks::context('PLAYER')
        );

        // Check rosters
        crew1_data = components::get::<Crew>(crew1.path()).unwrap();
        assert(crew1_data.roster.len() == roster1.len(), 'crew 1 roster incorrect');
    }
}
