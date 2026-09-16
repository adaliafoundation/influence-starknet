#[starknet::contract]
mod GrantOffchainCrewmate {
    use array::{ArrayTrait, SpanTrait};
    use clone::Clone;
    use option::OptionTrait;
    use starknet::{ContractAddress, get_contract_address};
    use starknet::storage::Map;
    use traits::{Into, TryInto};

    use influence::{components, config, contracts};
    use influence::common::{crewmate as crewmate_common, nft, crew::{CrewDetailsTrait, time_since_fed}};
    use influence::components::{Building, BuildingTrait, Control, ControlTrait, Crew, CrewTrait, Location,
        LocationTrait, Station, StationTrait,
        crewmate::{collections, Crewmate, CrewmateTrait},
        station_type::StationTypeTrait};
    use influence::config::{entities, errors, permissions, roles};
    use influence::contracts::crewmate::{ICrewmateDispatcher, ICrewmateDispatcherTrait};
    use influence::systems::helpers::change_name;
    use influence::types::{Context, ContextTrait, Entity, EntityTrait, StringTrait};

    #[storage]
    struct Storage {
        // Shared by offchain grant systems so an external payment reference can only be used once.
        external_refs: Map::<felt252, bool>
    }

    #[derive(Copy, Drop, starknet::Event)]
    struct OffchainCrewmateGranted {
        external_ref: felt252,
        recipient: ContractAddress,
        crewmate: Entity,
        collection: u64,
        class: u64,
        title: u64,
        impactful: Span<u64>,
        cosmetic: Span<u64>,
        gender: u64,
        body: u64,
        face: u64,
        hair: u64,
        hair_color: u64,
        clothes: u64,
        head: u64,
        item: u64,
        name: felt252,
        station: Entity,
        composition: Span<u64>,
        caller_crew: Entity,
        restricted_until: u64,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        OffchainCrewmateGranted: OffchainCrewmateGranted
    }

    #[external(v0)]
    fn run(
        ref self: ContractState,
        recipient: ContractAddress,
        external_ref: felt252,
        restricted_until: u64,
        station: Entity,
        caller_crew: Entity,
        class: u64,
        impactful: Span<u64>,
        cosmetic: Span<u64>,
        gender: u64,
        body: u64,
        face: u64,
        hair: u64,
        hair_color: u64,
        clothes: u64,
        name: felt252,
        context: Context
    ) {
        assert(
            context.is_admin() || context.has_role(roles::OFFCHAIN_STARTER_PACK_GRANTER),
            'not starter pack granter'
        );
        assert(!recipient.is_zero(), 'invalid recipient');
        assert(external_ref != 0, 'external ref required');
        assert(!self.external_refs.read(external_ref), 'external ref used');
        assert(caller_crew.label == entities::CREW, errors::INCORRECT_ENTITY_TYPE);

        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_ready(context.now);
        crew_details.assert_not_in_emergency();
        crew_details.assert_building_operational();
        let mut crew_data = crew_details.component;
        let num_crewmates: u64 = crew_data.roster.len().into();
        assert(num_crewmates < 5, 'crew is full');

        nft::assert_owner('Crew', caller_crew, recipient);
        let location = components::get::<Location>(caller_crew.path()).expect(errors::LOCATION_NOT_FOUND);
        assert(location.location == station, 'not at a station');

        let mut station_data = components::get::<Station>(station.path()).expect(errors::STATION_NOT_FOUND);
        components::get::<Building>(station.path()).expect(errors::BUILDING_NOT_FOUND).assert_operational();
        assert(StationTypeTrait::by_type(station_data.station_type).recruitment, 'station can not recruit');
        caller_crew.assert_can(station, permissions::RECRUIT_CREWMATE);

        let mut crewmate_data = CrewmateTrait::new(collections::ADALIAN);
        crewmate_common::provision_adalian(
            ref crewmate_data,
            class,
            impactful,
            cosmetic,
            gender,
            body,
            face,
            hair,
            hair_color,
            clothes,
            name
        );

        self.external_refs.write(external_ref, true);

        let contract_address = get_contract_address();
        let crewmate_contract = ICrewmateDispatcher { contract_address: contracts::get('Crewmate') };
        let crewmate_id = crewmate_contract.mint_with_auto_id(contract_address);
        crewmate_contract.transfer_with_restriction(
            contract_address, recipient, crewmate_id, restricted_until, context.caller
        );
        let crewmate = EntityTrait::new(entities::CREWMATE, crewmate_id.try_into().unwrap());
        components::set::<Crewmate>(crewmate.path(), crewmate_data);
        components::set::<Control>(crewmate.path(), ControlTrait::new(caller_crew));
        change_name(crewmate, StringTrait::new(name));

        station_data.population += 1;
        components::set::<Station>(station.path(), station_data);

        let food_per_year = config::get('CREWMATE_FOOD_PER_YEAR').try_into().unwrap();
        let new_food = crew_details.current_food(context.now) * num_crewmates + food_per_year;
        let elapsed_since_fed = time_since_fed(new_food / (num_crewmates + 1), crew_details.consume_mod());
        crew_data.last_fed = if elapsed_since_fed < context.now { context.now - elapsed_since_fed } else { 0 };

        let mut composition = crew_data.roster.snapshot.clone();
        composition.append(crewmate.id);
        crew_data.roster = composition.span();
        components::set::<Crew>(caller_crew.path(), crew_data);

        self.emit(OffchainCrewmateGranted {
            external_ref,
            recipient,
            crewmate,
            collection: crewmate_data.collection,
            class,
            title: crewmate_data.title,
            impactful,
            cosmetic,
            gender,
            body,
            face,
            hair,
            hair_color,
            clothes,
            head: 0,
            item: 0,
            name,
            station,
            composition: composition.span(),
            caller_crew,
            restricted_until,
            caller: context.caller
        });
    }
}

#[cfg(test)]
mod tests {
    use array::{Array, ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use starknet::testing;

    use influence::{components, contracts};
    use influence::components::{Control, Crew, CrewTrait, Location, LocationTrait, Station,
        crewmate::{classes, collections, crewmate_traits, statuses, Crewmate, CrewmateTrait}};
    use influence::config::{entities, roles};
    use influence::contracts::Dispatcher;
    use influence::contracts::crew::{ICrewDispatcher, ICrewDispatcherTrait};
    use influence::contracts::crewmate::{ICrewmateDispatcher, ICrewmateDispatcherTrait};
    use influence::test::{helpers, mocks};
    use influence::types::{Context, Entity, EntityTrait};

    use super::GrantOffchainCrewmate;

    #[test]
    #[available_gas(30000000)]
    fn test_grants_provisioned_crewmate_with_offchain_role() {
        let (crew, station) = setup();
        let mut state = GrantOffchainCrewmate::contract_state_for_testing();
        grant(
            ref state,
            crew,
            station,
            starknet::contract_address_const::<'PLAYER'>(),
            'stripe:crewmate:1',
            classes::PILOT,
            mocks::context('STRIPE_JOB')
        );

        let crewmate = EntityTrait::new(entities::CREWMATE, 20000);
        let crewmate_data = components::get::<Crewmate>(crewmate.path()).unwrap();
        assert(crewmate_data.status == statuses::INITIALIZED, 'crewmate not initialized');
        assert(crewmate_data.collection == collections::ADALIAN, 'wrong collection');
        assert(crewmate_data.class == classes::PILOT, 'wrong class');
        assert(*crewmate_data.impactful.at(0) == crewmate_traits::NAVIGATOR, 'wrong impactful');
        assert(*crewmate_data.cosmetic.at(0) == crewmate_traits::DRIVE_COMMAND, 'wrong cosmetic');
        assert(
            crewmate_data.appearance == CrewmateTrait::pack_appearance(1, 1, 1, 0, 3, 33, 0, 0),
            'wrong appearance'
        );
        assert(components::get::<Control>(crewmate.path()).unwrap().controller == crew, 'wrong controller');

        let crew_data = components::get::<Crew>(crew.path()).unwrap();
        assert(crew_data.roster.len() == 2, 'wrong crew size');
        assert(*crew_data.roster.at(1) == crewmate.id, 'crewmate not added');
        assert(components::get::<Station>(station.path()).unwrap().population == 1, 'wrong population');

        let crewmate_contract = ICrewmateDispatcher { contract_address: contracts::get('Crewmate') };
        assert(
            crewmate_contract.ownerOf(crewmate.id.into()) == starknet::contract_address_const::<'PLAYER'>(),
            'wrong owner'
        );
        assert(crewmate_contract.is_restricted(crewmate.id.into()), 'crewmate unrestricted');
        let restriction = crewmate_contract.restriction(crewmate.id.into());
        assert(restriction.restricted_until == 2000000000, 'wrong restriction');
        assert(
            restriction.restriction_authority == starknet::contract_address_const::<'STRIPE_JOB'>(),
            'wrong authority'
        );
    }

    #[test]
    #[available_gas(30000000)]
    #[should_panic(expected: ('external ref used', ))]
    fn test_rejects_duplicate_external_ref() {
        let (crew, station) = setup();
        let mut state = GrantOffchainCrewmate::contract_state_for_testing();
        grant(
            ref state,
            crew,
            station,
            starknet::contract_address_const::<'PLAYER'>(),
            'stripe:duplicate',
            classes::PILOT,
            mocks::context('STRIPE_JOB')
        );
        grant(
            ref state,
            crew,
            station,
            starknet::contract_address_const::<'PLAYER'>(),
            'stripe:duplicate',
            classes::PILOT,
            mocks::context('STRIPE_JOB')
        );
    }

    #[test]
    #[available_gas(30000000)]
    #[should_panic(expected: ('not starter pack granter', ))]
    fn test_rejects_unauthorized_caller() {
        let (crew, station) = setup();
        let mut state = GrantOffchainCrewmate::contract_state_for_testing();
        grant(
            ref state,
            crew,
            station,
            starknet::contract_address_const::<'PLAYER'>(),
            'stripe:unauthorized',
            classes::PILOT,
            mocks::context('PLAYER')
        );
    }

    #[test]
    #[available_gas(30000000)]
    #[should_panic(expected: ('not owner', ))]
    fn test_rejects_recipient_that_does_not_own_crew() {
        let (crew, station) = setup();
        let mut state = GrantOffchainCrewmate::contract_state_for_testing();
        grant(
            ref state,
            crew,
            station,
            starknet::contract_address_const::<'PLAYER2'>(),
            'stripe:not-owner',
            classes::PILOT,
            mocks::context('STRIPE_JOB')
        );
    }

    #[test]
    #[available_gas(30000000)]
    #[should_panic(expected: ('crew is full', ))]
    fn test_rejects_full_crew() {
        let (crew, station) = setup();
        let mut crew_data = components::get::<Crew>(crew.path()).unwrap();
        crew_data.roster = array![1, 2, 3, 4, 5].span();
        components::set::<Crew>(crew.path(), crew_data);

        let mut state = GrantOffchainCrewmate::contract_state_for_testing();
        grant(
            ref state,
            crew,
            station,
            starknet::contract_address_const::<'PLAYER'>(),
            'stripe:full',
            classes::PILOT,
            mocks::context('STRIPE_JOB')
        );
    }

    #[test]
    #[available_gas(30000000)]
    #[should_panic(expected: ('invalid class', ))]
    fn test_rejects_invalid_attributes() {
        let (crew, station) = setup();
        let mut state = GrantOffchainCrewmate::contract_state_for_testing();
        grant(
            ref state,
            crew,
            station,
            starknet::contract_address_const::<'PLAYER'>(),
            'stripe:invalid',
            99,
            mocks::context('STRIPE_JOB')
        );
    }

    fn setup() -> (Entity, Entity) {
        testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        testing::set_block_timestamp(1703187661);
        helpers::init();
        mocks::constants();

        let crew_address = helpers::deploy_crew();
        let crewmate_address = helpers::deploy_crewmate();

        testing::set_contract_address(starknet::contract_address_const::<'ADMIN'>());
        ICrewDispatcher { contract_address: crew_address }
            .add_grant(starknet::contract_address_const::<'DISPATCHER'>(), 2);
        ICrewmateDispatcher { contract_address: crewmate_address }
            .add_grant(starknet::contract_address_const::<'DISPATCHER'>(), 2);

        testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        ICrewDispatcher { contract_address: crew_address }
            .mint_with_auto_id(starknet::contract_address_const::<'PLAYER'>());
        let crew = mocks::delegated_crew(1, 'PLAYER');
        let station = mocks::public_habitat(crew, 37);
        components::set::<Location>(crew.path(), LocationTrait::new(station));

        let mut dispatcher_state = Dispatcher::contract_state_for_testing();
        testing::set_caller_address(starknet::contract_address_const::<'ADMIN'>());
        Dispatcher::add_grant(
            ref dispatcher_state,
            starknet::contract_address_const::<'STRIPE_JOB'>(),
            roles::OFFCHAIN_STARTER_PACK_GRANTER
        );
        testing::set_caller_address(starknet::contract_address_const::<'DISPATCHER'>());
        return (crew, station);
    }

    fn grant(
        ref state: GrantOffchainCrewmate::ContractState,
        crew: Entity,
        station: Entity,
        recipient: starknet::ContractAddress,
        external_ref: felt252,
        class: u64,
        context: Context
    ) {
        GrantOffchainCrewmate::run(
            ref state,
            recipient,
            external_ref,
            2000000000,
            station,
            crew,
            class,
            array![crewmate_traits::NAVIGATOR].span(),
            array![
                crewmate_traits::DRIVE_COMMAND,
                crewmate_traits::RIGHTEOUS,
                crewmate_traits::ADVENTUROUS
            ].span(),
            1,
            1,
            1,
            0,
            3,
            33,
            'Test Name',
            context
        );
    }
}
