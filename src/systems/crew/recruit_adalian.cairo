// Mint and delegate new crew if uninitialized

#[starknet::contract]
mod RecruitAdalian {
    use array::{Array, ArrayTrait, SpanTrait};
    use clone::Clone;
    use option::OptionTrait;
    use starknet::ContractAddress;
    use traits::{Into, TryInto};

    use influence::{components, config};
    use influence::common::{crewmate as crewmate_common, nft, crew::{CrewDetailsTrait, time_since_fed}};
    use influence::config::{entities, errors, permissions};
    use influence::components::{Building, BuildingTrait, Control, ControlTrait, Crew, CrewTrait, Inventory,
        InventoryTrait, Location, LocationTrait, Name, NameTrait, Station, StationTrait,
        crewmate::{collections, statuses, Crewmate, CrewmateTrait},
        inventory_type::types as inventory_types,
        ship::{statuses as ship_statuses, Ship, ShipTrait},
        ship_type::types as ship_types,
        station_type::{types as station_types, StationTypeTrait}
    };
    use influence::systems::helpers::{change_name, create_crew};
    use influence::types::{ArrayTraitExt, SpanTraitExt, Context, Entity, EntityTrait, String, StringTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct CrewmateRecruited {
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
        station: Entity,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[derive(Copy, Drop, starknet::Event)]
    struct CrewmateRecruitedV1 {
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
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        CrewmateRecruited: CrewmateRecruited,
        CrewmateRecruitedV1: CrewmateRecruitedV1
    }

    // Initializes a crewmate onto a crew, optionally creates the crew if needed
    // @param crewmate: the crewmate entity (crewmate.id = 0 for purchased Adalian crewmate)
    // @param caller_crew: the crew to mint into (crew.id = 0 for new crew)
    #[external(v0)]
    fn run(
        ref self: ContractState,
        mut crewmate: Entity,
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
        station: Entity,
        mut caller_crew: Entity,
        context: Context
    ) {
        assert(caller_crew.label == entities::CREW, errors::INCORRECT_ENTITY_TYPE);

        let maybe_crew_data = components::get::<Crew>(caller_crew.path());
        let mut target_crew = caller_crew;

        if maybe_crew_data.is_some() {
            maybe_crew_data.unwrap().assert_ready(context.now);
        } else {
            let (new_crew, _crew_data) = create_crew(station, context.caller);
            target_crew = new_crew;
        };

        // Allowed pre-launch
        let mut crew_details = CrewDetailsTrait::new(target_crew);
        crew_details.assert_delegated_to(context.caller);
        crew_details.assert_ready(context.now);
        crew_details.assert_not_in_emergency();
        crew_details.assert_building_operational();
        let mut crew_data = crew_details.component;

        let num_crewmates: u64 = crew_details.component.roster.len().into();
        assert(num_crewmates < 5, 'crew is full');

        // Get station data making sure the current location is a station
        match components::get::<Location>(target_crew.path()) {
            Option::Some(location_data) => {
                assert(location_data.location == station, 'not at a station');
            },
            Option::None(_) => {
                components::set::<Location>(target_crew.path(), LocationTrait::new(station));
            }
        };

        // Check that the station supports recruitment
        let mut station_data = components::get::<Station>(station.path()).expect(errors::STATION_NOT_FOUND);
        components::get::<Building>(station.path()).expect(errors::BUILDING_NOT_FOUND).assert_operational();
        let station_config = StationTypeTrait::by_type(station_data.station_type);
        assert(station_config.recruitment, 'station can not recruit');

        // Check for permissions to station crew
        target_crew.assert_can(station, permissions::RECRUIT_CREWMATE);

        // Retrieve or purchase crewmate (will revert if purchase price not approved first)
        let mut crewmate_data = nft::find_or_purchase_crewmate(ref crewmate, context.caller);
        assert(crewmate_data.status == statuses::UNINITIALIZED, errors::ALREADY_INITIALIZED);
        crewmate_data.status = statuses::INITIALIZED;

        crewmate_common::validate_adalian(
            class, impactful, cosmetic, gender, body, face, hair, hair_color, clothes, name
        );

        // Validate collection and class
        assert(crewmate_data.collection == collections::ADALIAN, 'invalid collection');
        crewmate_data.class = class;

        crewmate_data.cosmetic = cosmetic;

        crewmate_data.impactful = impactful;

        // Pack appearance and set crewmate
        crewmate_data.appearance = CrewmateTrait::pack_appearance(gender, body, face, hair, hair_color, clothes, 0, 0);
        components::set::<Crewmate>(crewmate.path(), crewmate_data);

        // Update station population and store (ignores station caps)
        station_data.population += 1;
        components::set::<Station>(station.path(), station_data);

        // Update last fed time, new crewmate comes with a full year of food
        let food_per_year = config::get('CREWMATE_FOOD_PER_YEAR').try_into().unwrap();
        let new_food = crew_details.current_food(context.now) * num_crewmates + food_per_year;
        let time_since_fed = time_since_fed(new_food / (num_crewmates + 1), crew_details.consume_mod());

        if time_since_fed < context.now {
            crew_data.last_fed = context.now - time_since_fed;
        } else {
            crew_data.last_fed = 0;
        }

        // Update crew as controller, update roster and save
        components::set::<Control>(crewmate.path(), ControlTrait::new(target_crew));
        let mut new_roster = crew_data.roster.snapshot.clone();
        new_roster.append(crewmate.id);
        crew_data.roster = new_roster.span();
        components::set::<Crew>(target_crew.path(), crew_data);

        // Update name
        change_name(crewmate, StringTrait::new(name));

        self.emit(CrewmateRecruitedV1 {
            crewmate: crewmate,
            collection: crewmate_data.collection,
            class: class,
            title: crewmate_data.title,
            impactful: impactful,
            cosmetic: cosmetic,
            gender: gender,
            body: body,
            face: face,
            hair: hair,
            hair_color: hair_color,
            clothes: clothes,
            head: 0,
            item: 0,
            name: name,
            station: station,
            composition: new_roster.span(),
            caller_crew: target_crew,
            caller: context.caller
        });
    }

}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use array::{Array, ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use starknet::testing;

    use influence::{config, components};
    use influence::components::{BuildingAllowance, Crew, CrewTrait, Location, LocationTrait, Ship, ShipTrait,
        StarterPack,
        crewmate::{classes, collections, crewmate_traits, Crewmate, CrewmateTrait}
    };
    use influence::config::entities;
    use influence::contracts::crew::{ICrewDispatcher, ICrewDispatcherTrait};
    use influence::types::entity::{Entity, EntityTrait};
    use influence::test::{helpers, mocks};

    use super::RecruitAdalian;

    #[test]
    #[available_gas(16000000)]
    fn test_recruit_adalian() {
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        helpers::init();
        mocks::constants();
        let crew_address = helpers::deploy_crew();

        starknet::testing::set_contract_address(starknet::contract_address_const::<'ADMIN'>());
        ICrewDispatcher { contract_address: crew_address }
            .add_grant(starknet::contract_address_const::<'DISPATCHER'>(), 2);

        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        let _asteroid = influence::test::mocks::asteroid();
        let crew = influence::test::mocks::delegated_crew(1, 'PLAYER');
        let mut crew_data = components::get::<Crew>(crew.path()).unwrap();
        crew_data.last_fed = 1703165866;
        components::set::<Crew>(crew.path(), crew_data);

        let station = influence::test::mocks::public_habitat(crew, 37);
        components::set::<Location>(crew.path(), LocationTrait::new(station));

        let crewmate = EntityTrait::new(entities::CREWMATE, 56);
        components::set::<Crewmate>(crewmate.path(), CrewmateTrait::new(collections::ADALIAN));

        let impactful = array![crewmate_traits::NAVIGATOR];
        let cosmetic = array![crewmate_traits::DRIVE_COMMAND, crewmate_traits::RIGHTEOUS, crewmate_traits::ADVENTUROUS];
        testing::set_block_timestamp(1703187661);
        let mut state = RecruitAdalian::contract_state_for_testing();
        RecruitAdalian::run(
            ref state,
            crewmate,
            classes::PILOT,
            impactful.span(),
            cosmetic.span(),
            1,
            1,
            1,
            0,
            3,
            33,
            'Test Name',
            station,
            EntityTrait::new(entities::CREW, 0),
            mocks::context('PLAYER')
        );

        let crewmate_data = components::get::<Crewmate>(crewmate.path()).unwrap();
        assert(crewmate_data.status == 1, 'crewmate not initialized');
        assert(crewmate_data.collection == collections::ADALIAN, 'invalid collection');
        assert(crewmate_data.class == classes::PILOT, 'invalid class');
        assert(*crewmate_data.impactful.at(0) == crewmate_traits::NAVIGATOR, 'invalid impactful');
        assert(*crewmate_data.cosmetic.at(0) == crewmate_traits::DRIVE_COMMAND, 'invalid cosmetic');
        assert(*crewmate_data.cosmetic.at(1) == crewmate_traits::RIGHTEOUS, 'invalid cosmetic');
        assert(*crewmate_data.cosmetic.at(2) == crewmate_traits::ADVENTUROUS, 'invalid cosmetic');
        assert(crewmate_data.appearance == CrewmateTrait::pack_appearance(1, 1, 1, 0, 3, 33, 0, 0), 'invalid appearance');
    }

    #[test]
    #[available_gas(16000000)]
    fn test_recruit_adalian_preserves_starter_pack() {
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        helpers::init();
        mocks::constants();

        let _asteroid = influence::test::mocks::asteroid();
        let crew = influence::test::mocks::delegated_crew(1, 'PLAYER');
        let mut crew_data = components::get::<Crew>(crew.path()).unwrap();
        crew_data.last_fed = 1703165866;
        components::set::<Crew>(crew.path(), crew_data);

        let station = influence::test::mocks::public_habitat(crew, 37);
        components::set::<Location>(crew.path(), LocationTrait::new(station));
        let allowances: Array<BuildingAllowance> = Default::default();
        components::set::<StarterPack>(crew.path(), StarterPack {
            product_id: 1,
            restricted_until: 200,
            valid: true,
            invalidated_at: 0,
            building_allowances: allowances.span(),
            lot_allowance: 0,
            food_reload_allowance: 1,
            core_sample_allowance: 1
        });

        let crewmate = EntityTrait::new(entities::CREWMATE, 56);
        components::set::<Crewmate>(crewmate.path(), CrewmateTrait::new(collections::ADALIAN));

        let impactful = array![crewmate_traits::NAVIGATOR];
        let cosmetic = array![crewmate_traits::DRIVE_COMMAND, crewmate_traits::RIGHTEOUS, crewmate_traits::ADVENTUROUS];
        testing::set_block_timestamp(1703187661);
        let mut state = RecruitAdalian::contract_state_for_testing();
        RecruitAdalian::run(
            ref state,
            crewmate,
            classes::PILOT,
            impactful.span(),
            cosmetic.span(),
            1,
            1,
            1,
            0,
            3,
            33,
            'Test Name',
            station,
            crew,
            mocks::context('PLAYER')
        );

        let starter_pack = components::get::<StarterPack>(crew.path()).unwrap();
        assert(starter_pack.valid, 'starter pack invalidated');
        assert(starter_pack.invalidated_at == 0, 'wrong invalidated at');
    }
}
