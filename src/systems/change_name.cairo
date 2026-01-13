#[starknet::contract]
mod ChangeName {
    use array::{Array, ArrayTrait};
    use option::OptionTrait;
    use starknet::ContractAddress;
    use traits::{Into, TryInto};

    use influence::components;
    use influence::components::{Crew, CrewTrait, Name, NameTrait, Unique, UniqueTrait};
    use influence::config::{entities, errors};
    use influence::systems::helpers::change_name;
    use influence::types::{Context, Entity, EntityTrait, String, StringTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct NameChanged {
        entity: Entity,
        name: String,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        NameChanged: NameChanged
    }

    #[external(v0)]
    fn run(ref self: ContractState, entity: Entity, name: String, caller_crew: Entity, context: Context) {
        components::get::<Crew>(caller_crew.path()).unwrap().assert_delegated_to(context.caller);
        caller_crew.assert_controls(entity);

        change_name(entity, name);

        self.emit(NameChanged {
            entity: entity,
            name: name,
            caller_crew: caller_crew,
            caller: context.caller
        });
    }
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use array::{Array, ArrayTrait, SpanTrait};
    use option::{Option, OptionTrait};
    use traits::{Into, TryInto};
    use starknet::contract_address::{ContractAddressIntoFelt252, ContractAddress};

    use influence::config::entities;
    use influence::components;
    use influence::components::{Control, ControlTrait, Crew, CrewTrait, Location, LocationTrait, Name};
    use influence::types::{Entity, EntityIntoFelt252, EntityTrait, String, StringTrait};
    use influence::test::{helpers, mocks};

    use super::ChangeName;

    #[test]
    #[available_gas(3000000)]
    fn test_sets_name() {
        let entity = EntityTrait::new(entities::SHIP, 1);
        let crew = EntityTrait::new(entities::CREW, 1);
        components::set::<Control>(entity.path(), ControlTrait::new(crew));
        components::set::<Crew>(crew.path(), CrewTrait::new(starknet::contract_address_const::<'PLAYER'>()));

        let mut state = ChangeName::contract_state_for_testing();
        ChangeName::run(ref state, entity, StringTrait::new('Austin Powers'), crew, mocks::context('PLAYER'));
        let read_name = components::get::<Name>(entity.path()).unwrap();
        assert(read_name.name == StringTrait::new('Austin Powers'), 'name wrong');
    }

    #[test]
    #[should_panic(expected: ('E6014: not unique', ))]
    #[available_gas(5000000)]
    fn test_sets_duplicate_name() {
        let entity1 = EntityTrait::new(entities::SHIP, 1);
        let entity2 = EntityTrait::new(entities::SHIP, 2);
        let crew = EntityTrait::new(entities::CREW, 1);
        components::set::<Control>(entity1.path(), ControlTrait::new(crew));
        components::set::<Control>(entity2.path(), ControlTrait::new(crew));
        components::set::<Crew>(crew.path(), CrewTrait::new(starknet::contract_address_const::<'PLAYER'>()));

        let mut state = ChangeName::contract_state_for_testing();
        ChangeName::run(ref state, entity1, StringTrait::new('Austin Powers'), crew, mocks::context('PLAYER'));
        ChangeName::run(ref state, entity2, StringTrait::new('Austin Powers'), crew, mocks::context('PLAYER'));
    }

    #[test]
    #[available_gas(10000000)]
    fn test_allow_building_dupe_diff() {
        let entity1 = EntityTrait::new(entities::BUILDING, 1);
        let entity2 = EntityTrait::new(entities::BUILDING, 2);
        let ap = influence::test::mocks::adalia_prime();
        let asteroid = influence::test::mocks::asteroid();
        components::set::<Location>(entity1.path(), LocationTrait::new(EntityTrait::from_position(ap.id, 1)));
        components::set::<Location>(entity2.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1)));

        let crew = EntityTrait::new(entities::CREW, 1);
        components::set::<Control>(entity1.path(), ControlTrait::new(crew));
        components::set::<Control>(entity2.path(), ControlTrait::new(crew));
        components::set::<Crew>(crew.path(), CrewTrait::new(starknet::contract_address_const::<'PLAYER'>()));

        let mut state = ChangeName::contract_state_for_testing();
        ChangeName::run(ref state, entity1, StringTrait::new('Austin Powers'), crew, mocks::context('PLAYER'));
        ChangeName::run(ref state, entity2, StringTrait::new('Austin Powers'), crew, mocks::context('PLAYER'));
    }

    #[test]
    #[available_gas(5000000)]
    fn test_allow_dupe_with_diff_unique_key() {
        let entity = EntityTrait::new(entities::SHIP, 1);
        let crew = EntityTrait::new(entities::CREW, 1);
        components::set::<Control>(entity.path(), ControlTrait::new(crew));
        components::set::<Crew>(crew.path(), CrewTrait::new(starknet::contract_address_const::<'PLAYER'>()));

        let mut state = ChangeName::contract_state_for_testing();
        ChangeName::run(ref state, entity, StringTrait::new('Austin Powers'), crew, mocks::context('PLAYER'));
        ChangeName::run(ref state, crew, StringTrait::new('Austin Powers'), crew, mocks::context('PLAYER'));
    }

    #[test]
    #[available_gas(5000000)]
    #[should_panic(expected: ('E6007: name already set', ))]
    fn test_rewriting_fails() {
        let entity = EntityTrait::new(entities::CREWMATE, 1);
        let crew = EntityTrait::new(entities::CREW, 1);
        components::set::<Control>(entity.path(), ControlTrait::new(crew));
        components::set::<Crew>(crew.path(), CrewTrait::new(starknet::contract_address_const::<'PLAYER'>()));

        let mut state = ChangeName::contract_state_for_testing();
        ChangeName::run(ref state, entity, StringTrait::new('Austin Powers'), crew, mocks::context('PLAYER'));
        ChangeName::run(ref state, entity, StringTrait::new('Austin More Powers'), crew, mocks::context('PLAYER'));
    }

    #[test]
    #[available_gas(7000000)]
    fn test_sets_name_to_previous() {
        let entity = EntityTrait::new(entities::SHIP, 1);
        let crew = EntityTrait::new(entities::CREW, 1);
        components::set::<Control>(entity.path(), ControlTrait::new(crew));
        components::set::<Crew>(crew.path(), CrewTrait::new(starknet::contract_address_const::<'PLAYER'>()));

        let mut state = ChangeName::contract_state_for_testing();
        ChangeName::run(ref state, entity, StringTrait::new('Austin Powers'), crew, mocks::context('PLAYER'));
        ChangeName::run(ref state, entity, StringTrait::new('Austin Powers 2'), crew, mocks::context('PLAYER'));
        ChangeName::run(ref state, entity, StringTrait::new('Austin Powers'), crew, mocks::context('PLAYER'));
        let read_name = components::get::<Name>(entity.path()).unwrap();
        assert(read_name.name == StringTrait::new('Austin Powers'), 'name wrong');
    }

    #[test]
    #[available_gas(6000000)]
    fn test_sets_name_to_empty() {
        let entity = EntityTrait::new(entities::SHIP, 1);
        let crew = EntityTrait::new(entities::CREW, 1);
        components::set::<Control>(entity.path(), ControlTrait::new(crew));
        components::set::<Crew>(crew.path(), CrewTrait::new(starknet::contract_address_const::<'PLAYER'>()));

        let mut state = ChangeName::contract_state_for_testing();
        ChangeName::run(ref state, entity, StringTrait::new('Austin Powers'), crew, mocks::context('PLAYER'));
        ChangeName::run(ref state, entity, StringTrait::new(''), crew, mocks::context('PLAYER'));
        assert(components::get::<Name>(entity.path()).is_none(), 'name not removed');
    }
}