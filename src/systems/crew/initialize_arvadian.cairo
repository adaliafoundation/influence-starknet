#[starknet::contract]
mod InitializeArvadian {
    use array::{Array, ArrayTrait, SpanTrait};
    use clone::Clone;
    use option::OptionTrait;
    use starknet::ContractAddress;
    use traits::{Into, TryInto};

    use influence::{components, config, contracts};
    use influence::common::{packed, nft, crew::{CrewDetailsTrait, time_since_fed}};
    use influence::components::{Building, BuildingTrait, Control, ControlTrait, Crew, CrewTrait, Inventory,
        InventoryTrait, Location, LocationTrait, Name, NameTrait, Station, StationTrait,
        crewmate::{statuses as crewmate_statuses, classes, collections, crewmate_traits, Crewmate, CrewmateTrait},
        inventory_type::types as inventory_types,
        ship::{statuses as ship_statuses, Ship, ShipTrait},
        ship_type::{types as ship_types},
        station_type::{types as station_types, StationTypeTrait}
    };
    use influence::config::{entities, errors, permissions};
    use influence::contracts::crewmate::{ICrewmateDispatcher, ICrewmateDispatcherTrait};
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
    // @param crew: the crew to mint into (crew.id = 0 for new crew)
    // @param crewmate: the crewmate entity (id from NFT contract)
    #[external(v0)]
    fn run(
        ref self: ContractState,
        crewmate: Entity,
        impactful: Span<u64>,
        cosmetic: Span<u64>,
        mut name: felt252, // may be 0 if no name change
        station: Entity,
        mut caller_crew: Entity,
        context: Context
    ) {
        // Mint and delegate new crew if uninitialized
        assert(caller_crew.label == entities::CREW, errors::INCORRECT_ENTITY_TYPE);
        if components::get::<Crew>(caller_crew.path()).is_none() {
            let (new_crew, crew_data) = create_crew(station, context.caller);
            caller_crew = new_crew;
        }

        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        let mut crew_data = crew_details.component;

        crew_details.assert_delegated_to(context.caller);
        crew_details.assert_ready(context.now);

        let num_crewmates: u64 = crew_data.roster.len().into();
        assert(num_crewmates < 5, errors::INCORRECT_CREW_SIZE);

        // Make sure crewmate is minted in one of the allowed Adalian stations (first 96 habitats on AP)
        assert(station.id <= 100, 'invalid station');

        match components::get::<Location>(caller_crew.path()) {
            Option::Some(location_data) => {
                assert(location_data.location == station, 'not at a station');
            },
            Option::None(_) => {
                components::set::<Location>(caller_crew.path(), LocationTrait::new(station));
            }
        };

        // Check that the station supports recruitment
        let mut station_data = components::get::<Station>(station.path()).expect(errors::STATION_NOT_FOUND);
        components::get::<Building>(station.path()).expect(errors::BUILDING_NOT_FOUND).assert_operational();
        let station_config = StationTypeTrait::by_type(station_data.station_type);
        assert(station_config.recruitment, 'station can not recruit');

        // Check for permissions
        caller_crew.assert_can(station, permissions::RECRUIT_CREWMATE);

        // Check for ownership and that crewmate is not on a crew yet
        nft::assert_owner('Crewmate', crewmate, context.caller);
        assert(components::get::<Control>(crewmate.path()).is_none(), errors::INCORRECT_CONTROLLER);

        // Get features from NFT contract and convert to appearance format
        let crewmate_address = contracts::get('Crewmate');
        let raw_features = ICrewmateDispatcher { contract_address: crewmate_address }.get_features(crewmate.id);
        assert(raw_features != 0, errors::CREWMATE_NOT_FOUND); // Crewmate hasn't been bridged yet
        let converted = convert_features(raw_features);

        // Make sure the crewmate is not already initialized
        match components::get::<Crewmate>(crewmate.path()) {
            Option::Some(crewmate_data) => {
                assert(crewmate_data.status == crewmate_statuses::UNINITIALIZED, 'crewmate already initialized');
            },
            Option::None => ()
        };

        let mut crewmate_data = CrewmateTrait::new(*converted.at(8)); // collection
        crewmate_data.status = crewmate_statuses::INITIALIZED;
        crewmate_data.class = *converted.at(9);
        crewmate_data.title = *converted.at(10);
        crewmate_data.appearance = CrewmateTrait::pack_appearance(
            *converted.at(0),
            *converted.at(1),
            *converted.at(2),
            *converted.at(3),
            *converted.at(4),
            *converted.at(5),
            *converted.at(6),
            *converted.at(7)
        );

        // Validate collection and class
        assert(
            (crewmate_data.collection == collections::ARVAD_SPECIALIST) ||
            (crewmate_data.collection == collections::ARVAD_CITIZEN) ||
            (crewmate_data.collection == collections::ARVAD_LEADERSHIP),
            'invalid collection'
        );

        // Validate cosmetic traits
        assert_drive(*cosmetic.at(0));
        assert_arvad_drive_dependent(*cosmetic.at(0), *cosmetic.at(1));
        assert_arvad_political(*cosmetic.at(0), *cosmetic.at(1), *cosmetic.at(2));
        assert_arvad_outlook(*cosmetic.at(3));
        assert_arvad_political_dep(*cosmetic.at(2), *cosmetic.at(4));
        crewmate_data.cosmetic = cosmetic;

        // Validate impactful traits
        assert_arvad_focus(*impactful.at(0));
        assert_arvad_class_dependent(crewmate_data.class, *impactful.at(1));
        assert_arvad_swap(crewmate_data.class, *impactful.at(1), *impactful.at(2));
        crewmate_data.impactful = impactful;

        // Set crewmate and control
        components::set::<Crewmate>(crewmate.path(), crewmate_data);
        components::set::<Control>(crewmate.path(), ControlTrait::new(caller_crew));

        // Update station population and store
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

        // Update name
        match components::get::<Name>(crewmate.path()) {
            Option::Some(name_data) => {
                name = name_data.name.value.try_into().unwrap();
            },
            Option::None(_) => {
                assert(name != 0, errors::NAME_REQUIRED);
                change_name(crewmate, StringTrait::new(name));
            }
        };

        // Update crew roster and save
        let mut new_roster = crew_data.roster.snapshot.clone();
        new_roster.append(crewmate.id);
        crew_data.roster = new_roster.span();
        components::set::<Crew>(caller_crew.path(), crew_data);

        self.emit(CrewmateRecruitedV1 {
            crewmate: crewmate,
            collection: crewmate_data.collection,
            class: crewmate_data.class,
            title: crewmate_data.title,
            impactful: impactful,
            cosmetic: cosmetic,
            gender: *converted.at(0),
            body: *converted.at(1),
            face: *converted.at(2),
            hair: *converted.at(3),
            hair_color: *converted.at(4),
            clothes: *converted.at(5),
            head: *converted.at(6),
            item: *converted.at(7),
            name: name,
            station: station,
            composition: new_roster.span(),
            caller_crew: caller_crew,
            caller: context.caller
        });
    }

    // Recruitment & Crew assignment cosmetic trait #1
    fn assert_drive(t: u64) {
        if t == crewmate_traits::DRIVE_SURVIVAL {
            return;
        } else if t == crewmate_traits::DRIVE_SERVICE {
            return;
        } else if t == crewmate_traits::DRIVE_GLORY {
            return;
        } else if t == crewmate_traits::DRIVE_COMMAND {
            return;
        }

        assert(false, 'invalid drive');
    }

    // Crew assignment cosmetic trait # 2
    fn assert_arvad_drive_dependent(drive: u64, t: u64) {
        if drive == crewmate_traits::DRIVE_SURVIVAL {
            if t == crewmate_traits::FRANTIC {
                return;
            } else if t == crewmate_traits::AMBITIOUS {
                return;
            } else if t == crewmate_traits::CREATIVE {
                return;
            } else if t == crewmate_traits::PRAGMATIC {
                return;
            } else if t == crewmate_traits::FLEXIBLE {
                return;
            } else if t == crewmate_traits::STEADFAST {
                return;
            } else if t == crewmate_traits::CAUTIOUS {
                return;
            } else if t == crewmate_traits::ADVENTUROUS {
                return;
            }
        } else if drive == crewmate_traits::DRIVE_SERVICE {
            if t == crewmate_traits::REGRESSIVE {
                return;
            } else if t == crewmate_traits::CURIOUS {
                return;
            } else if t == crewmate_traits::CAUTIOUS {
                return;
            } else if t == crewmate_traits::STEADFAST {
                return;
            } else if t == crewmate_traits::ADVENTUROUS {
                return;
            } else if t == crewmate_traits::LOYAL {
                return;
            } else if t == crewmate_traits::INDEPENDENT {
                return;
            }
        } else if drive == crewmate_traits::DRIVE_GLORY {
            if t == crewmate_traits::RECKLESS {
                return;
            } else if t == crewmate_traits::SERIOUS {
                return;
            } else if t == crewmate_traits::IRRATIONAL {
                return;
            } else if t == crewmate_traits::RATIONAL {
                return;
            } else if t == crewmate_traits::INDEPENDENT {
                return;
            } else if t == crewmate_traits::FIERCE {
                return;
            } else if t == crewmate_traits::AMBITIOUS {
                return;
            } else if t == crewmate_traits::LOYAL {
                return;
            }
        } else if drive == crewmate_traits::DRIVE_COMMAND {
            if t == crewmate_traits::ARROGANT {
                return;
            } else if t == crewmate_traits::HOPEFUL {
                return;
            } else if t == crewmate_traits::SERIOUS {
                return;
            } else if t == crewmate_traits::FIERCE {
                return;
            } else if t == crewmate_traits::AMBITIOUS {
                return;
            } else if t == crewmate_traits::LOYAL {
                return;
            }
        }

        assert(false, 'invalid drive dependent');
    }

    // Crew assignment cosmetic trait #3
    fn assert_arvad_political(drive: u64, drive_dep: u64, t: u64) {
        let mut valid = true;

        if drive == crewmate_traits::DRIVE_SURVIVAL {
            if (drive_dep == crewmate_traits::AMBITIOUS) && (t == crewmate_traits::COUNCIL_LOYALIST) {
                valid = false;
            } else if (drive_dep == crewmate_traits::FLEXIBLE) && (t == crewmate_traits::COUNCIL_LOYALIST) {
                valid = false;
            } else if (drive_dep == crewmate_traits::ADVENTUROUS) && (t == crewmate_traits::COUNCIL_LOYALIST) {
                valid = false;
            }
        } else if drive == crewmate_traits::DRIVE_SERVICE {
            if (drive_dep == crewmate_traits::CAUTIOUS) && (t == crewmate_traits::COUNCIL_LOYALIST) {
                valid = false;
            } else if (drive_dep == crewmate_traits::STEADFAST) && (t == crewmate_traits::COUNCIL_LOYALIST) {
                valid = false;
            } else if (drive_dep == crewmate_traits::ADVENTUROUS) && (t == crewmate_traits::COUNCIL_LOYALIST) {
                valid = false;
            } else if (drive_dep == crewmate_traits::INDEPENDENT) && (t == crewmate_traits::COUNCIL_LOYALIST) {
                valid = false;
            }
        } else if drive == crewmate_traits::DRIVE_GLORY {
            if (drive_dep == crewmate_traits::SERIOUS) && (t == crewmate_traits::INDEPENDENT_RADICAL) {
                valid = false;
            } else if (drive_dep == crewmate_traits::RATIONAL) && (t == crewmate_traits::INDEPENDENT_RADICAL) {
                valid = false;
            } else if (drive_dep == crewmate_traits::INDEPENDENT) && (t == crewmate_traits::INDEPENDENT_RADICAL) {
                valid = false;
            } else if (drive_dep == crewmate_traits::FIERCE) && (t == crewmate_traits::INDEPENDENT_RADICAL) {
                valid = false;
            } else if (drive_dep == crewmate_traits::LOYAL) && (t == crewmate_traits::INDEPENDENT_RADICAL) {
                valid = false;
            }
        } else if drive == crewmate_traits::DRIVE_COMMAND {
            if (drive_dep == crewmate_traits::HOPEFUL) && (t == crewmate_traits::INDEPENDENT_RADICAL) {
                valid = false;
            } else if (drive_dep == crewmate_traits::SERIOUS) && (t == crewmate_traits::INDEPENDENT_RADICAL) {
                valid = false;
            } else if (drive_dep == crewmate_traits::FIERCE) && (t == crewmate_traits::INDEPENDENT_RADICAL) {
                valid = false;
            } else if (drive_dep == crewmate_traits::LOYAL) && (t == crewmate_traits::INDEPENDENT_RADICAL) {
                valid = false;
            }
        }

        assert(valid, 'invalid political');
    }

    // Crew assignment cosmetic trait #4
    fn assert_arvad_outlook(t: u64) {
        if t == crewmate_traits::OPTIMISTIC {
            return;
        } else if t == crewmate_traits::THOUGHTFUL {
            return;
        } else if t == crewmate_traits::PESSIMISTIC {
            return;
        }

        assert(false, 'invalid outlook');
    }

    // Crew assignment cosmetic trait #5
    fn assert_arvad_political_dep(political: u64, t: u64) {
        if political == crewmate_traits::COUNCIL_LOYALIST {
            if t == crewmate_traits::RIGHTEOUS {
                return;
            } else if t == crewmate_traits::COMMUNAL {
                return;
            } else if t == crewmate_traits::IMPARTIAL {
                return;
            }
        } else if political == crewmate_traits::COUNCIL_MODERATE {
            if t == crewmate_traits::RIGHTEOUS {
                return;
            } else if t == crewmate_traits::COMMUNAL {
                return;
            } else if t == crewmate_traits::IMPARTIAL {
                return;
            } else if t == crewmate_traits::ENTERPRISING {
                return;
            }
        } else if political == crewmate_traits::INDEPENDENT_MODERATE {
            if t == crewmate_traits::COMMUNAL {
                return;
            } else if t == crewmate_traits::IMPARTIAL {
                return;
            } else if t == crewmate_traits::ENTERPRISING {
                return;
            } else if t == crewmate_traits::OPPORTUNISTIC {
                return;
            }
        } else if political == crewmate_traits::INDEPENDENT_RADICAL {
            if t == crewmate_traits::COMMUNAL {
                return;
            } else if t == crewmate_traits::ENTERPRISING {
                return;
            } else if t == crewmate_traits::OPPORTUNISTIC {
                return;
            }
        }

        assert(false, 'invalid political dependent');
    }

    // Crew assignment impactful trait #1
    fn assert_arvad_focus(t: u64) {
        if t == crewmate_traits::NAVIGATOR {
            return;
        } else if t == crewmate_traits::DIETITIAN {
            return;
        } else if t == crewmate_traits::REFINER {
            return;
        } else if t == crewmate_traits::SURVEYOR {
            return;
        } else if t == crewmate_traits::HAULER {
            return;
        };

        assert(false, 'invalid class independent');
    }

    // Crew assignment impactful trait #2
    fn assert_arvad_class_dependent(class: u64, t: u64) {
        let mut valid = false;

        if class == classes::PILOT {
            if t == crewmate_traits::BUSTER {
                return;
            } else if t == crewmate_traits::MOGUL {
                return;
            } else if t == crewmate_traits::SCHOLAR {
                return;
            } else if t == crewmate_traits::OPERATOR {
                return;
            } else if t == crewmate_traits::LOGISTICIAN {
                return;
            } else if t == crewmate_traits::EXPERIMENTER {
                return;
            }
        } else if class == classes::ENGINEER {
            if t == crewmate_traits::MECHANIC {
                return;
            } else if t == crewmate_traits::RECYCLER {
                return;
            } else if t == crewmate_traits::SCHOLAR {
                return;
            } else if t == crewmate_traits::BUILDER {
                return;
            } else if t == crewmate_traits::PROSPECTOR {
                return;
            } else if t == crewmate_traits::EXPERIMENTER {
                return;
            }
        } else if class == classes::MINER {
            if t == crewmate_traits::RECYCLER {
                return;
            } else if t == crewmate_traits::MOGUL {
                return;
            } else if t == crewmate_traits::MECHANIC {
                return;
            } else if t == crewmate_traits::PROSPECTOR {
                return;
            } else if t == crewmate_traits::LOGISTICIAN {
                return;
            } else if t == crewmate_traits::BUILDER {
                return;
            }
        } else if class == classes::MERCHANT {
            if t == crewmate_traits::MOGUL {
                return;
            } else if t == crewmate_traits::RECYCLER {
                return;
            } else if t == crewmate_traits::BUSTER {
                return;
            } else if t == crewmate_traits::LOGISTICIAN {
                return;
            } else if t == crewmate_traits::PROSPECTOR {
                return;
            } else if t == crewmate_traits::OPERATOR {
                return;
            }
        } else if class == classes::SCIENTIST {
            if t == crewmate_traits::SCHOLAR {
                return;
            } else if t == crewmate_traits::MECHANIC {
                return;
            } else if t == crewmate_traits::BUSTER {
                return;
            } else if t == crewmate_traits::EXPERIMENTER {
                return;
            } else if t == crewmate_traits::BUILDER {
                return;
            } else if t == crewmate_traits::OPERATOR {
                return;
            }
        }

        assert(false, 'invalid class dependent');
    }

    // Crew assignment impactful trait #3
    fn assert_arvad_swap(class: u64, class_dep: u64, t: u64) {
        if class == classes::PILOT {
            if t == crewmate_traits::BUILDER {
                return;
            } else if t == crewmate_traits::PROSPECTOR {
                return;
            } else if (t == crewmate_traits::BUSTER) && (class_dep == crewmate_traits::OPERATOR) {
                return;
            } else if (t == crewmate_traits::OPERATOR) && (class_dep != crewmate_traits::OPERATOR) {
                return;
            }
        } else if class == classes::ENGINEER {
            if t == crewmate_traits::LOGISTICIAN {
                return;
            } else if t == crewmate_traits::OPERATOR {
                return;
            } else if (t == crewmate_traits::MECHANIC) && (class_dep == crewmate_traits::BUILDER) {
                return;
            } else if (t == crewmate_traits::BUILDER) && (class_dep != crewmate_traits::BUILDER) {
                return;
            }
        } else if class == classes::MINER {
            if t == crewmate_traits::OPERATOR {
                return;
            } else if t == crewmate_traits::EXPERIMENTER {
                return;
            } else if (t == crewmate_traits::RECYCLER) && (class_dep == crewmate_traits::PROSPECTOR) {
                return;
            } else if (t == crewmate_traits::PROSPECTOR) && (class_dep != crewmate_traits::PROSPECTOR) {
                return;
            }
        } else if class == classes::MERCHANT {
            if t == crewmate_traits::BUILDER {
                return;
            } else if t == crewmate_traits::EXPERIMENTER {
                return;
            } else if (t == crewmate_traits::MOGUL) && (class_dep == crewmate_traits::LOGISTICIAN) {
                return;
            } else if (t == crewmate_traits::LOGISTICIAN) && (class_dep != crewmate_traits::LOGISTICIAN) {
                return;
            }
        } else if class == classes::SCIENTIST {
            if t == crewmate_traits::LOGISTICIAN {
                return;
            } else if t == crewmate_traits::PROSPECTOR {
                return;
            } else if (t == crewmate_traits::SCHOLAR) && (class_dep == crewmate_traits::EXPERIMENTER) {
                return;
            } else if (t == crewmate_traits::EXPERIMENTER) && (class_dep != crewmate_traits::EXPERIMENTER) {
                return;
            }
        }

        assert(false, 'invalid swap');
    }

    fn convert_features(features: u128) -> Span<u64> {
        let mut result: Array<u64> = Default::default();
        result.append(packed::unpack_u128(features, packed::EXP2_8, packed::EXP2_2).try_into().unwrap());
        result.append(packed::unpack_u128(features, packed::EXP2_10, packed::EXP2_16).try_into().unwrap());
        result.append(packed::unpack_u128(features, packed::EXP2_82, packed::EXP2_16).try_into().unwrap());
        result.append(packed::unpack_u128(features, packed::EXP2_66, packed::EXP2_16).try_into().unwrap());
        result.append(packed::unpack_u128(features, packed::EXP2_98, packed::EXP2_8).try_into().unwrap());
        result.append(packed::unpack_u128(features, packed::EXP2_50, packed::EXP2_16).try_into().unwrap());
        result.append(packed::unpack_u128(features, packed::EXP2_106, packed::EXP2_8).try_into().unwrap());
        result.append(packed::unpack_u128(features, packed::EXP2_114, packed::EXP2_8).try_into().unwrap());

        // Collection, class, title
        result.append(packed::unpack_u128(features, packed::EXP2_0, packed::EXP2_8).try_into().unwrap());
        result.append(packed::unpack_u128(features, packed::EXP2_26, packed::EXP2_8).try_into().unwrap());
        result.append(packed::unpack_u128(features, packed::EXP2_34, packed::EXP2_16).try_into().unwrap());
        return result.span();
    }
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use array::{ArrayTrait, SpanTrait};

    use influence::components;
    use influence::components::{Crew, CrewTrait, crewmate::{classes, crewmate_traits}};
    use influence::config::entities;
    use influence::contracts::crew::{Crew as CrewContract, ICrewDispatcher, ICrewDispatcherTrait};
    use influence::types::entity::EntityTrait;
    use influence::test::{helpers, mocks};

    use super::InitializeArvadian;

    #[test]
    #[available_gas(500000)]
    fn test_convert_features() {
        let features: u128 = 82397293850685768012593140600065; // from mainnet crewmate #42
        let result = InitializeArvadian::convert_features(features);
        assert(*result.at(0) == 1, 'wrong gender');
        assert(*result.at(1) == 3, 'wrong body');
        assert(*result.at(2) == 1, 'wrong face');
        assert(*result.at(3) == 2, 'wrong hair');
        assert(*result.at(4) == 4, 'wrong hair_color');
        assert(*result.at(5) == 4, 'wrong clothes');
        assert(*result.at(6) == 1, 'wrong head');
        assert(*result.at(7) == 0, 'wrong item');

        assert(*result.at(8) == 1, 'wrong collection');
        assert(*result.at(9) == 2, 'wrong class');
        assert(*result.at(10) == 35, 'wrong title');
    }
}

// Additionally tested via integration tests
