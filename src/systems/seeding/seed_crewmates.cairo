#[starknet::contract]
mod SeedCrewmates {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use traits::Into;

    use influence::components;
    use influence::components::{Name, NameTrait, Unique, UniqueTrait};
    use influence::config::entities;
    use influence::{contracts, systems};
    use influence::interfaces::erc721::{IERC721Dispatcher, IERC721DispatcherTrait};
    use influence::types::context::{Context, ContextTrait};
    use influence::types::entity::{Entity, EntityTrait};
    use influence::types::string::{String, StringTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, Serde)]
    struct SeededCrewmate {
        crewmate_id: u64,
        name: felt252
    }

    // Seed crewmates names based on L1 data
    // @param crewmate_id The ID of the asteroid to seed
    // @param name The name of the crewmate
    #[external(v0)]
    fn run(ref self: ContractState, crewmates: Span<SeededCrewmate>, context: Context) {
        // Check the caller is the admin
        assert(context.is_admin(), 'only admin can seed');

        let mut iter = 0;
        // Loop through the crewmates and seed them
        loop {
            if iter >= crewmates.len() { break; }
            let to_seed = *crewmates.at(iter);

            // Check that the crewmate hasn't already been seeded
            let crewmate = EntityTrait::new(entities::CREWMATE, to_seed.crewmate_id);
            assert(components::get::<Name>(crewmate.path()).is_none(), 'crewmate already seeded');

            // If there's a name, set it and assume it's going to be unique (since they should all be new)
            if to_seed.name != 0 {
                components::set::<Name>(crewmate.path(), NameTrait::new(StringTrait::new(to_seed.name)));
                components::set::<Unique>(array![crewmate.label.into(), to_seed.name].span(), UniqueTrait::new());
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

    use influence::components;
    use influence::components::Name;
    use influence::config::entities;
    use influence::contracts::dispatcher::Dispatcher;
    use influence::types::{Context, EntityTrait, StringTrait};
    use influence::test::{helpers, mocks};

    use super::{SeedCrewmates};

    #[test]
    #[available_gas(3000000)]
    fn test_seed() {
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        helpers::init();

        let crewmates = array![
            SeedCrewmates::SeededCrewmate { crewmate_id: 1, name: 'Austin Powers' },
            SeedCrewmates::SeededCrewmate { crewmate_id: 2, name: 'Pink Power Ranger' }
        ];

        let mut state = SeedCrewmates::contract_state_for_testing();
        SeedCrewmates::run(ref state, crewmates.span(), mocks::context('ADMIN'));

        let mut name_data = components::get::<Name>(EntityTrait::new(entities::CREWMATE, 1).path()).unwrap();
        assert(name_data.name == StringTrait::new('Austin Powers'), 'name');

        let mut name_data = components::get::<Name>(EntityTrait::new(entities::CREWMATE, 2).path()).unwrap();
        assert(name_data.name == StringTrait::new('Pink Power Ranger'), 'name');
    }

    #[test]
    #[available_gas(3000000)]
    #[should_panic(expected: ('only admin can seed', ))]
    fn test_not_admin() {
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        helpers::init();

        let crewmates = array![SeedCrewmates::SeededCrewmate { crewmate_id: 1, name: 'Austin Powers' }];
        let mut state = SeedCrewmates::contract_state_for_testing();
        SeedCrewmates::run(ref state, crewmates.span(), Context {
            caller: starknet::contract_address_const::<1>(),
            now: starknet::get_block_timestamp(),
            payment_to: starknet::contract_address_const::<0>(),
            payment_amount: 0
        });
    }

    #[test]
    #[available_gas(5000000)]
    #[should_panic(expected: ('crewmate already seeded', ))]
    fn test_already_exists() {
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        helpers::init();

        let crewmates = array![SeedCrewmates::SeededCrewmate { crewmate_id: 1, name: 'Austin Powers' }];
        let mut state = SeedCrewmates::contract_state_for_testing();
        SeedCrewmates::run(ref state, crewmates.span(), mocks::context('ADMIN'));
        SeedCrewmates::run(ref state, crewmates.span(), mocks::context('ADMIN'));
    }
}
