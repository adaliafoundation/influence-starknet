// This system does the initial seeding and setup of Adalia

#[starknet::contract]
mod SeedHabitat {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use starknet::contract_address::ContractAddress;
    use traits::Into;

    use cubit::{f64, f128};

    use influence::{components, config, contracts, entities::next_id};
    use influence::common::{position, nft};
    use influence::components::{Control, ControlTrait, Crew, CrewTrait, Dock, DockTrait, Exchange, ExchangeTrait,
        Location, LocationTrait, Orbit, PublicPolicy, PublicPolicyTrait, Station, StationTrait, Unique, UniqueTrait,
        building::{statuses as building_statuses, Building, BuildingTrait},
        celestial::{statuses as celestial_statuses, types as celestial_types, Celestial, CelestialTrait},
        crewmate::{statuses as crewmate_statuses, classes, collections, titles, crewmate_traits, Crewmate, CrewmateTrait},
        building_type::types as building_types,
        exchange_type::types as exchange_types,
        dock_type::types as dock_types,
        station_type::types as station_types};
    use influence::config::{entities, errors, permissions};
    use influence::contracts::crewmate::{ICrewmateDispatcher, ICrewmateDispatcherTrait};
    use influence::systems::helpers::{change_name, create_crew};
    use influence::systems::policies::helpers::policy_path;
    use influence::types::{Context, ContextTrait, Entity, EntityTrait, String, StringTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct ConstructionPlanned {
        building: Entity,
        building_type: u64,
        asteroid: Entity,
        lot: Entity,
        grace_period_end: u64,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[derive(Copy, Drop, starknet::Event)]
    struct ConstructionStarted {
        building: Entity,
        finish_time: u64,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[derive(Copy, Drop, starknet::Event)]
    struct ConstructionFinished {
        building: Entity,
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
        ConstructionPlanned: ConstructionPlanned,
        ConstructionStarted: ConstructionStarted,
        ConstructionFinished: ConstructionFinished,
        CrewmateRecruitedV1: CrewmateRecruitedV1
    }

    #[external(v0)]
    fn run(ref self: ContractState, context: Context) {
        // Check the caller is the admin
        assert(context.is_admin(), 'only admin can seed');

        // Set time acceleration
        config::set('TIME_ACCELERATION', 24);

        // Seed celestial and orbit data for Adalia Prime
        let asteroid = EntityTrait::new(entities::ASTEROID, 1);
        components::set::<Celestial>(asteroid.path(), Celestial {
            celestial_type: celestial_types::C_TYPE_ASTEROID,
            mass: f128::FixedTrait::new(5711148277301932455541959738129383424, false), // mass in tonnes
            radius: f64::FixedTrait::new(1611222621356, false), // radius in km
            purchase_order: 0,
            scan_status: celestial_statuses::SURFACE_SCANNED,
            scan_finish_time: 0,
            bonuses: 0,
            abundances: 0 // Will be assigned during additional settlement seeding
        });

        components::set::<Orbit>(asteroid.path(), Orbit {
            a: f128::FixedTrait::new(6049029247426345756235714160, false),
            ecc: f128::FixedTrait::new(5995191823955604275, false),
            inc: f128::FixedTrait::new(45073898850257648, false),
            raan: f128::FixedTrait::new(62919943230756093952, false),
            argp: f128::FixedTrait::new(97469086699478581248, false),
            m: f128::FixedTrait::new(17488672753899970560, false),
        });

        // Generate the initial habitat
        let lot = EntityTrait::from_position(1, 1602262);
        let habitat = EntityTrait::new(entities::BUILDING, next_id(entities::BUILDING.into()));
        components::set::<Building>(habitat.path(), Building {
            status: building_statuses::OPERATIONAL,
            building_type: building_types::HABITAT,
            planned_at: context.now,
            finish_time: context.now
        });

        // Reserve lot appropriately
        let mut unique_path: Array<felt252> = Default::default();
        unique_path.append('LotUse');
        unique_path.append(lot.id.into());
        components::set::<Unique>(unique_path.span(), Unique { unique: habitat.into() });

        // Assign policies
        components::set::<PublicPolicy>(
            policy_path(habitat, permissions::RECRUIT_CREWMATE), PublicPolicy { public: true }
        );

        components::set::<PublicPolicy>(
            policy_path(habitat, permissions::STATION_CREW), PublicPolicy { public: true }
        );

        components::set::<Location>(habitat.path(), LocationTrait::new(lot));

        // Create crew and delegate to caller
        let (crew, mut crew_data) = create_crew(habitat, context.caller);
        let mut roster: Array<u64> = Default::default();

        // Add five crewmates to crew
        let status = crewmate_statuses::INITIALIZED;
        let collection = collections::ADALIAN;
        let title = titles::ADALIAN_PRIME_COUNCIL;

        let mut c: Array<u64> = Default::default();
        c.append(crewmate_traits::DRIVE_SURVIVAL);
        c.append(crewmate_traits::RIGHTEOUS);
        c.append(crewmate_traits::ADVENTUROUS);
        c.append(crewmate_traits::INDEPENDENT);
        c.append(crewmate_traits::CURIOUS);
        let mut i: Array<u64> = Default::default();
        i.append(crewmate_traits::NAVIGATOR);
        i.append(crewmate_traits::BUSTER);
        i.append(crewmate_traits::OPERATOR);
        i.append(crewmate_traits::DIETITIAN);
        i.append(crewmate_traits::SURVEYOR);

        roster.append(15001);
        let pilot = create_crewmate(
            ref self,
            habitat,
            15001,
            classes::PILOT,
            2, 9, 0, 7, 2, 32, 0, 0,
            c.span(),
            i.span(),
            'Memory Hugin',
            roster.span(),
            crew,
            context.caller
        );

        let mut c: Array<u64> = Default::default();
        c.append(crewmate_traits::DRIVE_SERVICE);
        c.append(crewmate_traits::COMMUNAL);
        c.append(crewmate_traits::CAUTIOUS);
        c.append(crewmate_traits::FRANTIC);
        c.append(crewmate_traits::PRAGMATIC);
        let mut i: Array<u64> = Default::default();
        i.append(crewmate_traits::REFINER);
        i.append(crewmate_traits::BUILDER);
        i.append(crewmate_traits::MECHANIC);
        i.append(crewmate_traits::PROSPECTOR);
        i.append(crewmate_traits::MOGUL);

        roster.append(15002);
        let engineer = create_crewmate(
            ref self,
            habitat,
            15002,
            classes::ENGINEER,
            2, 8, 0, 6, 4, 35, 0, 0,
            c.span(),
            i.span(),
            'Sunshine Cornelis',
            roster.span(),
            crew,
            context.caller
        );

        let mut c: Array<u64> = Default::default();
        c.append(crewmate_traits::DRIVE_SURVIVAL);
        c.append(crewmate_traits::IMPARTIAL);
        c.append(crewmate_traits::SERIOUS);
        c.append(crewmate_traits::PRAGMATIC);
        c.append(crewmate_traits::CAUTIOUS);
        let mut i: Array<u64> = Default::default();
        i.append(crewmate_traits::PROSPECTOR);
        i.append(crewmate_traits::SURVEYOR);
        i.append(crewmate_traits::RECYCLER);
        i.append(crewmate_traits::NAVIGATOR);
        i.append(crewmate_traits::BUILDER);

        roster.append(15003);
        let miner = create_crewmate(
            ref self,
            habitat,
            15003,
            classes::MINER,
            1, 2, 4, 0, 4, 37, 0, 0,
            c.span(),
            i.span(),
            'Opal Fortuna',
            roster.span(),
            crew,
            context.caller
        );

        let mut c: Array<u64> = Default::default();
        c.append(crewmate_traits::DRIVE_COMMAND);
        c.append(crewmate_traits::OPPORTUNISTIC);
        c.append(crewmate_traits::AMBITIOUS);
        c.append(crewmate_traits::CREATIVE);
        c.append(crewmate_traits::INDEPENDENT);
        let mut i: Array<u64> = Default::default();
        i.append(crewmate_traits::LOGISTICIAN);
        i.append(crewmate_traits::MOGUL);
        i.append(crewmate_traits::HAULER);
        i.append(crewmate_traits::REFINER);
        i.append(crewmate_traits::SCHOLAR);

        roster.append(15004);
        let merchant = create_crewmate(
            ref self,
            habitat,
            15004,
            classes::MERCHANT,
            1, 3, 6, 1, 4, 39, 0, 0,
            c.span(),
            i.span(),
            'Finn Geld',
            roster.span(),
            crew,
            context.caller
        );

        let mut c: Array<u64> = Default::default();
        c.append(crewmate_traits::DRIVE_GLORY);
        c.append(crewmate_traits::ENTERPRISING);
        c.append(crewmate_traits::ARROGANT);
        c.append(crewmate_traits::RECKLESS);
        c.append(crewmate_traits::IRRATIONAL);
        let mut i: Array<u64> = Default::default();
        i.append(crewmate_traits::DIETITIAN);
        i.append(crewmate_traits::SCHOLAR);
        i.append(crewmate_traits::EXPERIMENTER);
        i.append(crewmate_traits::LOGISTICIAN);
        i.append(crewmate_traits::BUSTER);

        roster.append(15005);
        let scientist = create_crewmate(
            ref self,
            habitat,
            15005,
            classes::SCIENTIST,
            1, 5, 5, 5, 3, 40, 0, 0,
            c.span(),
            i.span(),
            'Frank Shelley',
            roster.span(),
            crew,
            context.caller
        );

        // Assign roster
        let mut roster: Array<u64> = Default::default();
        roster.append(pilot.id);
        roster.append(engineer.id);
        roster.append(miner.id);
        roster.append(merchant.id);
        roster.append(scientist.id);
        crew_data.roster = roster.span();
        components::set::<Crew>(crew.path(), crew_data);

        // Grant control and station newly created crew at habitat
        components::set::<Control>(asteroid.path(), ControlTrait::new(crew));
        components::set::<Control>(habitat.path(), ControlTrait::new(crew));
        components::set::<Location>(crew.path(), LocationTrait::new(habitat));
        components::set::<Station>(habitat.path(), Station {
            station_type: station_types::HABITAT,
            population: 5
        });

        self.emit(ConstructionPlanned {
            building: habitat,
            building_type: building_types::HABITAT,
            asteroid: asteroid,
            lot: lot,
            grace_period_end: context.now,
            caller_crew: crew,
            caller: context.caller
        });

        self.emit(ConstructionStarted {
            building: habitat,
            finish_time: context.now,
            caller_crew: crew,
            caller: context.caller
        });

        self.emit(ConstructionFinished {
            building: habitat,
            caller_crew: crew,
            caller: context.caller
        });
    }

    fn create_crewmate(
        ref self: ContractState,
        habitat: Entity,
        id: u64,
        class: u64,
        gender: u64,
        body: u64,
        face: u64,
        hair: u64,
        hair_color: u64,
        clothes: u64,
        head: u64,
        item: u64,
        cosmetic: Span<u64>,
        impactful: Span<u64>,
        name: felt252,
        composition: Span<u64>,
        caller_crew: Entity,
        caller: ContractAddress
    ) -> Entity {
        ICrewmateDispatcher { contract_address: contracts::get('Crewmate') }.mint_with_id(caller, id.into());
        let crewmate = EntityTrait::new(entities::CREWMATE, id);
        components::set::<Crewmate>(crewmate.path(), Crewmate {
            status: crewmate_statuses::INITIALIZED,
            collection: collections::ADALIAN,
            class: class,
            title: titles::ADALIAN_PRIME_COUNCIL,
            appearance: CrewmateTrait::pack_appearance(gender, body, face, hair, hair_color, clothes, head, item),
            cosmetic: cosmetic,
            impactful: impactful
        });

        components::set::<Control>(crewmate.path(), ControlTrait::new(caller_crew));

        self.emit(CrewmateRecruitedV1 {
            crewmate: crewmate,
            collection: collections::ADALIAN,
            class: class,
            title: titles::ADALIAN_PRIME_COUNCIL,
            impactful: impactful,
            cosmetic: cosmetic,
            gender: gender,
            body: body,
            face: face,
            hair: hair,
            hair_color: hair_color,
            clothes: clothes,
            head: head,
            item: item,
            name: name,
            station: habitat,
            composition: composition,
            caller_crew: caller_crew,
            caller: caller
        });

        return crewmate;
    }
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use traits::Into;

    use influence::{components, config};
    use influence::components::{Crew, CrewTrait, Location, LocationTrait, ship_type::types as ship_types};
    use influence::config::entities;
    use influence::contracts::crew::{ICrewDispatcher, ICrewDispatcherTrait};
    use influence::contracts::crewmate::{ICrewmateDispatcher, ICrewmateDispatcherTrait};
    use influence::types::{EntityTrait, StringTrait, Context};
    use influence::test::{helpers, mocks};

    use super::SeedHabitat;

    #[test]
    #[available_gas(15000000)]
    fn test_seed() {
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        helpers::init();
        let crew_address = helpers::deploy_crew();
        let crewmate_address = helpers::deploy_crewmate();
        mocks::ship_type(ship_types::ESCAPE_MODULE);

        starknet::testing::set_contract_address(starknet::contract_address_const::<'ADMIN'>());
        ICrewDispatcher { contract_address: crew_address }
            .add_grant(starknet::contract_address_const::<'DISPATCHER'>(), 2);

        ICrewmateDispatcher { contract_address: crewmate_address }
            .add_grant(starknet::contract_address_const::<'DISPATCHER'>(), 2);

        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        let mut state = SeedHabitat::contract_state_for_testing();
        SeedHabitat::run(ref state, mocks::context('ADMIN'));

        // Check for results
        assert(config::get('TIME_ACCELERATION') == 24, 'wrong time acceleration');

        let habitat = EntityTrait::new(entities::BUILDING, 1);
        let hab_location = components::get::<Location>(habitat.path()).unwrap();
        assert(hab_location.location == EntityTrait::from_position(1, 1602262), 'wrong hab location');

        let crew = EntityTrait::new(entities::CREW, 1);
        let crew_data = components::get::<Crew>(crew.path()).unwrap();
        let crew_location = components::get::<Location>(crew.path()).unwrap();
        assert(crew_data.roster.len() == 5, 'wrong crew size');
        assert(crew_location.location == habitat, 'wrong crew location');
    }
}
