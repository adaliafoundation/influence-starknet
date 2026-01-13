#[starknet::contract]
mod SeedColony {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use starknet::contract_address::ContractAddress;
    use traits::Into;

    use cubit::{f64, f128};

    use influence::{components, config, contracts, entities::next_id};
    use influence::common::{position, nft};
    use influence::components::{Control, ControlTrait, Crew, CrewTrait, Dock, DockTrait, Exchange, ExchangeTrait,
        Location, LocationTrait, Name, NameTrait, Orbit, PublicPolicy, PublicPolicyTrait, Station, StationTrait,
        Unique, UniqueTrait,
        building::{statuses as building_statuses, Building, BuildingTrait},
        building_type::{types as building_types, BuildingTypeTrait},
        celestial::{statuses as celestial_statuses, types as celestial_types, Celestial, CelestialTrait},
        crewmate::{statuses as crewmate_statuses, classes, collections, titles, crewmate_traits, Crewmate, CrewmateTrait},
        dock_type::types as dock_types,
        exchange_type::types as exchange_types,
        inventory::{statuses as inventory_statuses, Inventory, InventoryTrait},
        inventory_type::types as inventory_types,
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
    struct NameChanged {
        entity: Entity,
        name: String,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        ConstructionPlanned: ConstructionPlanned,
        ConstructionStarted: ConstructionStarted,
        ConstructionFinished: ConstructionFinished,
        NameChanged: NameChanged
    }

    #[derive(Copy, Drop)]
    struct HabitatSettings {
        lot: u64,
        name: felt252
    }

    #[derive(Copy, Drop)]
    struct MarketplaceSettings {
        lot: u64,
        name: felt252,
        allowed_products: Span<u64>
    }

    #[derive(Copy, Drop)]
    struct SpaceportSettings {
        lot: u64,
        name: felt252
    }

    #[derive(Copy, Drop)]
    struct WarehouseSettings {
        lot: u64,
        name: felt252,
        public: bool
    }

    // 1 = Colony A (Arkos)
    // 2 = Colony B (Yaaxche)
    // 3 = Colony C (Saline)
    #[external(v0)]
    fn run(ref self: ContractState, colony: u64, building_type: u64, context: Context) {
        // Check the caller is the admin
        assert(context.is_admin(), 'only admin can seed');

        let asteroid = EntityTrait::new(entities::ASTEROID, 1);
        let crew = EntityTrait::new(entities::CREW, 1);

        // Seed habitats
        if building_type == building_types::HABITAT {
            let habitats = colony_habitats(colony);
            let mut iter = 0;

            loop {
                if iter == habitats.len() { break; }

                // Generate the habitats
                let habitat = EntityTrait::new(entities::BUILDING, next_id(entities::BUILDING.into()));
                let building_data = Building {
                    status: building_statuses::OPERATIONAL,
                    building_type: building_types::HABITAT,
                    planned_at: context.now,
                    finish_time: context.now
                };

                let lot = EntityTrait::from_position(asteroid.id, *habitats.at(iter).lot);
                let created = common_setup(
                    ref self,
                    asteroid,
                    lot,
                    habitat,
                    building_types::HABITAT,
                    *habitats.at(iter).name,
                    crew,
                    context
                );

                if created {
                    components::set::<Building>(habitat.path(), building_data);

                    // Create the site inventory
                    let config = BuildingTypeTrait::by_type(building_data.building_type);
                    let mut site_path: Array<felt252> = Default::default();
                    site_path.append(habitat.into());
                    site_path.append(1);
                    let mut site_data = InventoryTrait::new(config.site_type);
                    site_data.status = inventory_statuses::UNAVAILABLE;
                    components::set::<Inventory>(site_path.span(), site_data);

                    // Assign policies
                    components::set::<PublicPolicy>(
                        policy_path(habitat, permissions::RECRUIT_CREWMATE), PublicPolicy { public: true }
                    );

                    components::set::<PublicPolicy>(
                        policy_path(habitat, permissions::STATION_CREW), PublicPolicy { public: true }
                    );

                    components::set::<Station>(
                        habitat.path(), Station { station_type: station_types::HABITAT, population: 0 }
                    );

                    common_events(
                        ref self,
                        asteroid,
                        lot,
                        habitat,
                        building_types::HABITAT,
                        *habitats.at(iter).name,
                        crew,
                        context
                    );
                }

                iter += 1;
            };
        }

        // Seed spaceports
        if building_type == building_types::SPACEPORT {
            let spaceports = colony_spaceports(colony);
            let mut iter = 0;

            loop {
                if iter == spaceports.len() { break; }

                // Generate the spaceports
                let spaceport = EntityTrait::new(entities::BUILDING, next_id(entities::BUILDING.into()));
                let building_data = Building {
                    status: building_statuses::OPERATIONAL,
                    building_type: building_types::SPACEPORT,
                    planned_at: context.now,
                    finish_time: context.now
                };

                let lot = EntityTrait::from_position(asteroid.id, *spaceports.at(iter).lot);
                let created = common_setup(
                    ref self,
                    asteroid,
                    lot,
                    spaceport,
                    building_types::SPACEPORT,
                    *spaceports.at(iter).name,
                    crew,
                    context
                );

                if created {
                    components::set::<Building>(spaceport.path(), building_data);

                    // Create the site inventory
                    let config = BuildingTypeTrait::by_type(building_data.building_type);
                    let mut site_path: Array<felt252> = Default::default();
                    site_path.append(spaceport.into());
                    site_path.append(1);
                    let mut site_data = InventoryTrait::new(config.site_type);
                    site_data.status = inventory_statuses::UNAVAILABLE;
                    components::set::<Inventory>(site_path.span(), site_data);

                    components::set::<PublicPolicy>(
                        policy_path(spaceport, permissions::DOCK_SHIP), PublicPolicy { public: true }
                    ); // Assign public policy

                    components::set::<Dock>(spaceport.path(), Dock {
                        dock_type: dock_types::BASIC,
                        docked_ships: 0,
                        ready_at: context.now
                    });

                    common_events(
                        ref self,
                        asteroid,
                        lot,
                        spaceport,
                        building_types::SPACEPORT,
                        *spaceports.at(iter).name,
                        crew,
                        context
                    );
                }

                iter += 1;
            };
        }

        // Seed marketplaces
        if building_type == building_types::MARKETPLACE {
            let marketplaces = colony_marketplaces(colony);
            let mut iter = 0;

            loop {
                if iter == marketplaces.len() { break; }

                // Generate the marketplaces
                let marketplace = EntityTrait::new(entities::BUILDING, next_id(entities::BUILDING.into()));
                let building_data = Building {
                    status: building_statuses::OPERATIONAL,
                    building_type: building_types::MARKETPLACE,
                    planned_at: context.now,
                    finish_time: context.now
                };

                let lot = EntityTrait::from_position(asteroid.id, *marketplaces.at(iter).lot);
                let created = common_setup(
                    ref self,
                    asteroid,
                    lot,
                    marketplace,
                    building_types::SPACEPORT,
                    *marketplaces.at(iter).name,
                    crew,
                    context
                );

                if created {
                    components::set::<Building>(marketplace.path(), building_data);

                    // Create the site inventory
                    let config = BuildingTypeTrait::by_type(building_data.building_type);
                    let mut site_path: Array<felt252> = Default::default();
                    site_path.append(marketplace.into());
                    site_path.append(1);
                    let mut site_data = InventoryTrait::new(config.site_type);
                    site_data.status = inventory_statuses::UNAVAILABLE;
                    components::set::<Inventory>(site_path.span(), site_data);

                    // Assign policies
                    components::set::<PublicPolicy>(
                        policy_path(marketplace, permissions::BUY), PublicPolicy { public: true }
                    );

                    components::set::<PublicPolicy>(
                        policy_path(marketplace, permissions::SELL), PublicPolicy { public: true }
                    );

                    components::set::<PublicPolicy>(
                        policy_path(marketplace, permissions::LIMIT_BUY), PublicPolicy { public: true }
                    );

                    components::set::<PublicPolicy>(
                        policy_path(marketplace, permissions::LIMIT_SELL), PublicPolicy { public: true }
                    );

                    components::set::<Exchange>(marketplace.path(), Exchange {
                        exchange_type: exchange_types::BASIC,
                        maker_fee: 0,
                        taker_fee: 0,
                        orders: 0, // count of open orders
                        allowed_products: *marketplaces.at(iter).allowed_products
                    });

                    common_events(
                        ref self,
                        asteroid,
                        lot,
                        marketplace,
                        building_types::MARKETPLACE,
                        *marketplaces.at(iter).name,
                        crew,
                        context
                    );
                }

                iter += 1;
            };
        }

        // Seed public warehouses
        if building_type == building_types::WAREHOUSE {
            let warehouses = colony_warehouses(colony);
            let mut iter = 0;

            loop {
                if iter == warehouses.len() { break; }

                // Generate the warehouses
                let warehouse = EntityTrait::new(entities::BUILDING, next_id(entities::BUILDING.into()));
                let building_data = Building {
                    status: building_statuses::OPERATIONAL,
                    building_type: building_types::WAREHOUSE,
                    planned_at: context.now,
                    finish_time: context.now
                };

                let lot = EntityTrait::from_position(asteroid.id, *warehouses.at(iter).lot);
                let created = common_setup(
                    ref self,
                    asteroid,
                    lot,
                    warehouse,
                    building_types::SPACEPORT,
                    *warehouses.at(iter).name,
                    crew,
                    context
                );

                if created {
                    components::set::<Building>(warehouse.path(), building_data);

                    // Create the site inventory
                    let config = BuildingTypeTrait::by_type(building_data.building_type);
                    let mut site_path: Array<felt252> = Default::default();
                    site_path.append(warehouse.into());
                    site_path.append(1);
                    let mut site_data = InventoryTrait::new(config.site_type);
                    site_data.status = inventory_statuses::UNAVAILABLE;
                    components::set::<Inventory>(site_path.span(), site_data);

                    if *warehouses.at(iter).public {
                        // Assign policies
                        components::set::<PublicPolicy>(
                            policy_path(warehouse, permissions::ADD_PRODUCTS), PublicPolicy { public: true }
                        );

                        components::set::<PublicPolicy>(
                            policy_path(warehouse, permissions::REMOVE_PRODUCTS), PublicPolicy { public: true }
                        );
                    }

                    site_path = Default::default();
                    site_path.append(warehouse.into());
                    site_path.append(2); // inventory slot
                    components::set::<Inventory>(
                        site_path.span(), InventoryTrait::new(inventory_types::WAREHOUSE_PRIMARY)
                    );

                    common_events(
                        ref self,
                        asteroid,
                        lot,
                        warehouse,
                        building_types::WAREHOUSE,
                        *warehouses.at(iter).name,
                        crew,
                        context
                    );
                }

                iter += 1;
            };
        }
    }

    fn common_setup(
        ref self: ContractState,
        asteroid: Entity,
        lot: Entity,
        building: Entity,
        building_type: u64,
        name: felt252,
        crew: Entity,
        context: Context
    ) -> bool {
        // Reserve lot appropriately
        let mut unique_path: Array<felt252> = Default::default();
        unique_path.append('LotUse');
        unique_path.append(lot.into());

        if components::get::<Unique>(unique_path.span()).is_some() {
            return false;
        }

        components::set::<Unique>(unique_path.span(), Unique { unique: building.into() });

        // Give control to the crew
        components::set::<Control>(building.path(), ControlTrait::new(crew));

        // Set location of building
        components::set::<Location>(building.path(), LocationTrait::new(lot));

        // Set a name if there is one
        if name != 0 {
            let mut path: Array<felt252> = Default::default();
            path.append('Name');
            path.append(building.label.into());
            path.append(asteroid.id.into());
            path.append(name);

            let name_data = NameTrait::new(String { value: name.into() });
            components::set::<Name>(building.path(), name_data);
            components::set::<Unique>(path.span(), UniqueTrait::new());
        }

        return true;
    }

    fn common_events(
        ref self: ContractState,
        asteroid: Entity,
        lot: Entity,
        building: Entity,
        building_type: u64,
        name: felt252,
        crew: Entity,
        context: Context
    ) {
        self.emit(ConstructionPlanned {
            building: building,
            building_type: building_type,
            asteroid: asteroid,
            lot: lot,
            grace_period_end: context.now,
            caller_crew: crew,
            caller: context.caller
        });

        self.emit(ConstructionStarted {
            building: building,
            finish_time: context.now,
            caller_crew: crew,
            caller: context.caller
        });

        self.emit(ConstructionFinished {
            building: building,
            caller_crew: crew,
            caller: context.caller
        });

        if name != 0 {
            self.emit(NameChanged {
                entity: building,
                name: String { value: name.into() },
                caller_crew: crew,
                caller: context.caller
            });
        }
    }

    // 1 = Colony A (Arkos)
    // 2 = Colony B (Yaaxche)
    // 3 = Colony C (Saline)
    fn colony_habitats(colony: u64) -> Span<HabitatSettings> {
        let mut habitats: Array<HabitatSettings> = Default::default();

        if colony == 1 {
            habitats.append(HabitatSettings { lot: 1597471, name: 'Arcadia' });
            habitats.append(HabitatSettings { lot: 1598458, name: 'Schuyler' });
            habitats.append(HabitatSettings { lot: 1599445, name: 'Napolitania' });
            habitats.append(HabitatSettings { lot: 1600432, name: 'Al-Khwarismi' });
            habitats.append(HabitatSettings { lot: 1601419, name: 'Alamosa' });
            habitats.append(HabitatSettings { lot: 1597094, name: 'Zubov' });
            habitats.append(HabitatSettings { lot: 1598081, name: 'Ashkova' });
            habitats.append(HabitatSettings { lot: 1599068, name: 'Kroll' });
            habitats.append(HabitatSettings { lot: 1600055, name: 'Nye' });
            habitats.append(HabitatSettings { lot: 1601042, name: 'Zhang Heng' });
            habitats.append(HabitatSettings { lot: 1602029, name: 'Gellivara' });
            habitats.append(HabitatSettings { lot: 1603016, name: 'Degenfeld' });
            habitats.append(HabitatSettings { lot: 1604003, name: 'Hadfield' });
            habitats.append(HabitatSettings { lot: 1597704, name: 'Aquilegia' });
            habitats.append(HabitatSettings { lot: 1598691, name: 'Carolus Quartus' });
            habitats.append(HabitatSettings { lot: 1599678, name: 'Sabonis' });
            habitats.append(HabitatSettings { lot: 1600665, name: 'Armstrong' });
            habitats.append(HabitatSettings { lot: 1601652, name: 'Krylania' });
            habitats.append(HabitatSettings { lot: 1602639, name: 'Kopff' });
            habitats.append(HabitatSettings { lot: 1603626, name: 'Teutonia' });
            habitats.append(HabitatSettings { lot: 1604613, name: 'Lemmon' });
            habitats.append(HabitatSettings { lot: 1598314, name: 'Kilimanjaro' });
            habitats.append(HabitatSettings { lot: 1599301, name: 'Grubba' });
            habitats.append(HabitatSettings { lot: 1600288, name: 'Gerti' });
            habitats.append(HabitatSettings { lot: 1601275, name: 'Wallenbergia' });
            habitats.append(HabitatSettings { lot: 1603249, name: 'Gianrix' });
            habitats.append(HabitatSettings { lot: 1604236, name: 'Gagarin' });
            habitats.append(HabitatSettings { lot: 1605223, name: 'Maxwell' });
            habitats.append(HabitatSettings { lot: 1606210, name: 'Korolev' });
            habitats.append(HabitatSettings { lot: 1599911, name: 'Bratijchuk' });
            habitats.append(HabitatSettings { lot: 1600898, name: 'Hephaistos' });
            habitats.append(HabitatSettings { lot: 1601885, name: 'Vishnu' });
            habitats.append(HabitatSettings { lot: 1602872, name: 'Kacivelia' });
            habitats.append(HabitatSettings { lot: 1603859, name: 'Lunaria' });
            habitats.append(HabitatSettings { lot: 1604846, name: 'Tycho Brahe' });
            habitats.append(HabitatSettings { lot: 1605833, name: 'Soyuz-Apollo' });
            habitats.append(HabitatSettings { lot: 1606820, name: 'Betulia' });
            habitats.append(HabitatSettings { lot: 1601508, name: 'Stropek' });
            habitats.append(HabitatSettings { lot: 1602495, name: 'Beatrice Tinsley' });
            habitats.append(HabitatSettings { lot: 1603482, name: 'Hyperborea' });
            habitats.append(HabitatSettings { lot: 1604469, name: 'Alainagarza' });
            habitats.append(HabitatSettings { lot: 1605456, name: 'Monchicourt' });
            habitats.append(HabitatSettings { lot: 1606443, name: 'Lincoln' });
            habitats.append(HabitatSettings { lot: 1607430, name: 'Sputnik' });
            habitats.append(HabitatSettings { lot: 1603105, name: 'Felix' });
            habitats.append(HabitatSettings { lot: 1604092, name: 'Stuber' });
            habitats.append(HabitatSettings { lot: 1605079, name: 'Noether' });
            habitats.append(HabitatSettings { lot: 1606066, name: 'Meeus' });
            habitats.append(HabitatSettings { lot: 1607053, name: 'Besixdouze' });
        } else if colony == 2 {
            habitats.append(HabitatSettings{ lot: 443082, name: 'Aguaribay' });
            habitats.append(HabitatSettings{ lot: 445666, name: 'Ancar' });
            habitats.append(HabitatSettings{ lot: 447263, name: 'Rowan' });
            habitats.append(HabitatSettings{ lot: 444679, name: 'Ironwood' });
            habitats.append(HabitatSettings{ lot: 442095, name: 'Olive' });
            habitats.append(HabitatSettings{ lot: 441108, name: 'Lacebark Elm' });
            habitats.append(HabitatSettings{ lot: 446276, name: 'Gheetree' });
            habitats.append(HabitatSettings{ lot: 442705, name: 'Tamarisk' });
            habitats.append(HabitatSettings{ lot: 444302, name: 'Frangipani' });
            habitats.append(HabitatSettings{ lot: 441718, name: 'Sweet Buckeye' });
            habitats.append(HabitatSettings{ lot: 443315, name: 'Linden' });
            habitats.append(HabitatSettings{ lot: 445378, name: 'Nukanuka' });
            habitats.append(HabitatSettings{ lot: 446975, name: 'Dragon\'s Blood' });
            habitats.append(HabitatSettings{ lot: 444391, name: 'Carpathian Walnut' });
            habitats.append(HabitatSettings{ lot: 445988, name: 'Flannelbush' });
            habitats.append(HabitatSettings{ lot: 445001, name: 'Sugar Maple' });
            habitats.append(HabitatSettings{ lot: 450169, name: 'Teak' });
            habitats.append(HabitatSettings{ lot: 451766, name: 'Ponderosa Pine' });
            habitats.append(HabitatSettings{ lot: 449182, name: 'Yoshino Cherry' });
            habitats.append(HabitatSettings{ lot: 446598, name: 'Crepe Myrtle' });
            habitats.append(HabitatSettings{ lot: 450779, name: 'Pagoda Dogwood' });
            habitats.append(HabitatSettings{ lot: 448195, name: 'Cycad' });
            habitats.append(HabitatSettings{ lot: 470375, name: 'Black Birch' });
            habitats.append(HabitatSettings{ lot: 469388, name: 'Seringueira' });
            habitats.append(HabitatSettings{ lot: 476153, name: 'Kauri' });
            habitats.append(HabitatSettings{ lot: 473569, name: 'Iva Kozya' });
            habitats.append(HabitatSettings{ lot: 470985, name: 'Eaglewood' });
            habitats.append(HabitatSettings{ lot: 477750, name: 'Ceiba' });
            habitats.append(HabitatSettings{ lot: 476763, name: 'Baobab' });
            habitats.append(HabitatSettings{ lot: 474179, name: 'Sequoia' });
            habitats.append(HabitatSettings{ lot: 471595, name: 'Bur Oak' });
            habitats.append(HabitatSettings{ lot: 470608, name: 'Hemp Willow' });
            habitats.append(HabitatSettings{ lot: 472205, name: 'Black Tupelo' });
        } else if colony == 3 {
            habitats.append(HabitatSettings{ lot: 1083942, name: 'Orpiment' });
            habitats.append(HabitatSettings{ lot: 1090330, name: 'Zircon' });
            habitats.append(HabitatSettings{ lot: 1096718, name: 'Kyawthuite' });
            habitats.append(HabitatSettings{ lot: 1086903, name: 'Siderotil' });
            habitats.append(HabitatSettings{ lot: 1093291, name: 'Purpurite' });
            habitats.append(HabitatSettings{ lot: 1099679, name: 'Bystrite' });
            habitats.append(HabitatSettings{ lot: 1089864, name: 'Melonite' });
            habitats.append(HabitatSettings{ lot: 1102640, name: 'Topaz' });
            habitats.append(HabitatSettings{ lot: 1092825, name: 'Roscoelite' });
            habitats.append(HabitatSettings{ lot: 1099213, name: 'Scotlandite' });
            habitats.append(HabitatSettings{ lot: 1105601, name: 'Kyanite' });
            habitats.append(HabitatSettings{ lot: 1095786, name: 'Glaucophane' });
            habitats.append(HabitatSettings{ lot: 1102174, name: 'Eudialyte' });
            habitats.append(HabitatSettings{ lot: 1108562, name: 'Diopside' });
            habitats.append(HabitatSettings{ lot: 1098747, name: 'Chrysocolla' });
            habitats.append(HabitatSettings{ lot: 1105135, name: 'Khatyrkite' });
            habitats.append(HabitatSettings{ lot: 1111523, name: 'Marcasite' });
        } else if colony == 4 {
            habitats.append(HabitatSettings{ lot: 446726, name: 'Butterbough' });
        }

        return habitats.span();
    }

    fn colony_spaceports(colony: u64) -> Span<SpaceportSettings> {
        let mut spaceports: Array<SpaceportSettings> = Default::default();

        if colony == 1 {
            spaceports.append(SpaceportSettings { lot: 1593379, name: 'Arkos North Port' });
            spaceports.append(SpaceportSettings { lot: 1615038, name: 'Arkos Southeast Port' });
            spaceports.append(SpaceportSettings { lot: 1599356, name: 'Arkos Southwest Port' });
        } else if colony == 2 {
            spaceports.append(SpaceportSettings { lot: 458065, name: 'Ya\'axche Spaceport Xylem' });
            spaceports.append(SpaceportSettings { lot: 455481, name: 'Ya\'axche Spaceport Phloem' });
        } else if colony == 3 {
            spaceports.append(SpaceportSettings { lot: 1096252, name: 'Saline Regional Spaceport' });
        }

        return spaceports.span();
    }

    fn colony_marketplaces(colony: u64) -> Span<MarketplaceSettings> {
        let mut marketplaces: Array<MarketplaceSettings> = Default::default();

        if colony == 1 {
            let mut allowed_products: Array<u64> = Default::default();
            allowed_products.append(67);
            allowed_products.append(99);
            allowed_products.append(119);
            allowed_products.append(120);
            allowed_products.append(152);
            allowed_products.append(153);
            allowed_products.append(157);
            allowed_products.append(158);
            allowed_products.append(174);
            allowed_products.append(187);
            allowed_products.append(201);
            allowed_products.append(202);
            allowed_products.append(203);
            allowed_products.append(213);
            allowed_products.append(136);
            allowed_products.append(162);
            allowed_products.append(100);
            allowed_products.append(181);
            allowed_products.append(97);
            allowed_products.append(219);
            marketplaces.append(MarketplaceSettings {
                lot: 1591782, name: 'PC-A Electronics and Misc.', allowed_products: allowed_products.span()
            });

            allowed_products = Default::default();
            allowed_products.append(121);
            allowed_products.append(126);
            allowed_products.append(127);
            allowed_products.append(130);
            allowed_products.append(132);
            allowed_products.append(133);
            allowed_products.append(154);
            allowed_products.append(155);
            allowed_products.append(156);
            allowed_products.append(183);
            allowed_products.append(204);
            allowed_products.append(205);
            allowed_products.append(206);
            allowed_products.append(209);
            allowed_products.append(210);
            allowed_products.append(214);
            allowed_products.append(215);
            allowed_products.append(42);
            allowed_products.append(125);
            allowed_products.append(128);
            marketplaces.append(MarketplaceSettings {
                lot: 1592769, name: 'PC-A Mechanical and Fabric', allowed_products: allowed_products.span()
            });

            allowed_products = Default::default();
            allowed_products.append(235);
            allowed_products.append(236);
            allowed_products.append(237);
            allowed_products.append(238);
            allowed_products.append(239);
            allowed_products.append(240);
            allowed_products.append(241);
            allowed_products.append(242);
            allowed_products.append(243);
            allowed_products.append(244);
            allowed_products.append(245);
            allowed_products.append(173);
            allowed_products.append(186);
            allowed_products.append(211);
            allowed_products.append(212);
            allowed_products.append(66);
            allowed_products.append(169);
            allowed_products.append(207);
            allowed_products.append(208);
            marketplaces.append(MarketplaceSettings {
                lot: 1593989, name: 'PC-A Modules and Optics', allowed_products: allowed_products.span()
            });

            allowed_products = Default::default();
            allowed_products.append(145);
            allowed_products.append(146);
            allowed_products.append(147);
            allowed_products.append(148);
            allowed_products.append(149);
            allowed_products.append(150);
            allowed_products.append(167);
            allowed_products.append(144);
            allowed_products.append(221);
            allowed_products.append(222);
            allowed_products.append(224);
            allowed_products.append(225);
            allowed_products.append(226);
            allowed_products.append(227);
            allowed_products.append(229);
            allowed_products.append(230);
            allowed_products.append(231);
            allowed_products.append(232);
            allowed_products.append(233);
            allowed_products.append(234);
            marketplaces.append(MarketplaceSettings {
                lot: 1594976, name: 'PC-A Hull and Engine Parts', allowed_products: allowed_products.span()
            });

            allowed_products = Default::default();
            allowed_products.append(9);
            allowed_products.append(10);
            allowed_products.append(11);
            allowed_products.append(12);
            allowed_products.append(13);
            allowed_products.append(14);
            allowed_products.append(19);
            allowed_products.append(18);
            allowed_products.append(20);
            allowed_products.append(21);
            allowed_products.append(17);
            allowed_products.append(16);
            allowed_products.append(15);
            allowed_products.append(22);
            allowed_products.append(34);
            allowed_products.append(217);
            allowed_products.append(48);
            allowed_products.append(192);
            allowed_products.append(77);
            allowed_products.append(28);
            marketplaces.append(MarketplaceSettings {
                lot: 1597759, name: 'PC-A Raws and Carbonates', allowed_products: allowed_products.span()
            });

            allowed_products = Default::default();
            allowed_products.append(2);
            allowed_products.append(1);
            allowed_products.append(3);
            allowed_products.append(6);
            allowed_products.append(7);
            allowed_products.append(8);
            allowed_products.append(4);
            allowed_products.append(5);
            allowed_products.append(24);
            allowed_products.append(220);
            allowed_products.append(180);
            allowed_products.append(81);
            allowed_products.append(82);
            allowed_products.append(54);
            allowed_products.append(83);
            allowed_products.append(55);
            allowed_products.append(59);
            allowed_products.append(84);
            allowed_products.append(90);
            allowed_products.append(89);
            marketplaces.append(MarketplaceSettings {
                lot: 1598369, name: 'PC-A Volatiles and Redox', allowed_products: allowed_products.span()
            });

            allowed_products = Default::default();
             allowed_products.append(25);
            allowed_products.append(110);
            allowed_products.append(142);
            allowed_products.append(93);
            allowed_products.append(143);
            allowed_products.append(47);
            allowed_products.append(78);
            allowed_products.append(105);
            allowed_products.append(159);
            allowed_products.append(49);
            allowed_products.append(36);
            allowed_products.append(46);
            allowed_products.append(45);
            allowed_products.append(117);
            allowed_products.append(113);
            allowed_products.append(139);
            allowed_products.append(37);
            allowed_products.append(38);
            allowed_products.append(40);
            allowed_products.append(39);
            marketplaces.append(MarketplaceSettings {
                lot: 1600343, name: 'PC-A Salts and Sulfides', allowed_products: allowed_products.span()
            });

            allowed_products = Default::default();
            allowed_products.append(80);
            allowed_products.append(94);
            allowed_products.append(184);
            allowed_products.append(185);
            allowed_products.append(179);
            allowed_products.append(195);
            allowed_products.append(193);
            allowed_products.append(196);
            allowed_products.append(73);
            allowed_products.append(107);
            allowed_products.append(197);
            allowed_products.append(27);
            allowed_products.append(33);
            allowed_products.append(50);
            allowed_products.append(134);
            allowed_products.append(53);
            allowed_products.append(51);
            allowed_products.append(76);
            allowed_products.append(116);
            allowed_products.append(23);
            marketplaces.append(MarketplaceSettings {
                lot: 1600953, name: 'PC-A Nonmetals and Misc.', allowed_products: allowed_products.span()
            });

            allowed_products = Default::default();
            allowed_products.append(88);
            allowed_products.append(79);
            allowed_products.append(218);
            allowed_products.append(161);
            allowed_products.append(63);
            allowed_products.append(87);
            allowed_products.append(65);
            allowed_products.append(137);
            allowed_products.append(86);
            allowed_products.append(32);
            allowed_products.append(109);
            allowed_products.append(26);
            allowed_products.append(163);
            allowed_products.append(138);
            allowed_products.append(85);
            allowed_products.append(96);
            allowed_products.append(115);
            allowed_products.append(35);
            allowed_products.append(131);
            marketplaces.append(MarketplaceSettings {
                lot: 1614051, name: 'PC-A Oxides and Misc.', allowed_products: allowed_products.span()
            });

            allowed_products = Default::default();
            allowed_products.append(52);
            allowed_products.append(57);
            allowed_products.append(95);
            allowed_products.append(98);
            allowed_products.append(118);
            allowed_products.append(141);
            allowed_products.append(151);
            allowed_products.append(182);
            allowed_products.append(43);
            allowed_products.append(69);
            allowed_products.append(70);
            allowed_products.append(71);
            allowed_products.append(72);
            allowed_products.append(101);
            allowed_products.append(122);
            allowed_products.append(123);
            allowed_products.append(124);
            allowed_products.append(171);
            allowed_products.append(172);
            allowed_products.append(44);
            marketplaces.append(MarketplaceSettings {
                lot: 1614428, name: 'PC-A Alloys, Metals, Cement', allowed_products: allowed_products.span()
            });

            allowed_products = Default::default();
            allowed_products.append(175);
            allowed_products.append(170);
            allowed_products.append(129);
            allowed_products.append(103);
            allowed_products.append(92);
            allowed_products.append(91);
            allowed_products.append(64);
            allowed_products.append(140);
            allowed_products.append(108);
            allowed_products.append(200);
            allowed_products.append(56);
            allowed_products.append(114);
            allowed_products.append(189);
            allowed_products.append(191);
            allowed_products.append(190);
            allowed_products.append(58);
            allowed_products.append(74);
            allowed_products.append(102);
            marketplaces.append(MarketplaceSettings {
                lot: 1615648, name: 'PC-A Prop, Food, Tools, Crops', allowed_products: allowed_products.span()
            });

            allowed_products = Default::default();
            allowed_products.append(29);
            allowed_products.append(30);
            allowed_products.append(31);
            allowed_products.append(60);
            allowed_products.append(61);
            allowed_products.append(62);
            allowed_products.append(75);
            allowed_products.append(104);
            allowed_products.append(106);
            allowed_products.append(111);
            allowed_products.append(112);
            allowed_products.append(135);
            allowed_products.append(164);
            allowed_products.append(178);
            allowed_products.append(194);
            allowed_products.append(199);
            allowed_products.append(188);
            allowed_products.append(176);
            allowed_products.append(41);
            allowed_products.append(68);
            marketplaces.append(MarketplaceSettings {
                lot: 1616025, name: 'PC-A Refined Goods and Glass', allowed_products: allowed_products.span()
            });
        } else if colony == 2 {
            let mut allowed_products: Array<u64> = Default::default();
            allowed_products.append(80);
            allowed_products.append(94);
            allowed_products.append(184);
            allowed_products.append(185);
            allowed_products.append(179);
            allowed_products.append(195);
            allowed_products.append(193);
            allowed_products.append(196);
            allowed_products.append(73);
            allowed_products.append(107);
            allowed_products.append(197);
            allowed_products.append(27);
            allowed_products.append(33);
            allowed_products.append(50);
            allowed_products.append(134);
            allowed_products.append(53);
            allowed_products.append(51);
            allowed_products.append(76);
            allowed_products.append(116);
            allowed_products.append(23);
            marketplaces.append(MarketplaceSettings {
                lot: 447496, name: 'PC-Y Nonmetals and Misc.', allowed_products: allowed_products.span()
            });

            allowed_products = Default::default();
            allowed_products.append(29);
            allowed_products.append(30);
            allowed_products.append(31);
            allowed_products.append(60);
            allowed_products.append(61);
            allowed_products.append(62);
            allowed_products.append(75);
            allowed_products.append(104);
            allowed_products.append(106);
            allowed_products.append(111);
            allowed_products.append(112);
            allowed_products.append(135);
            allowed_products.append(164);
            allowed_products.append(178);
            allowed_products.append(194);
            allowed_products.append(199);
            allowed_products.append(188);
            allowed_products.append(176);
            allowed_products.append(41);
            allowed_products.append(68);
            marketplaces.append(MarketplaceSettings {
                lot: 448949, name: 'PC-Y Refined Goods and Glass', allowed_products: allowed_products.span()
            });

            allowed_products = Default::default();
            allowed_products.append(2);
            allowed_products.append(1);
            allowed_products.append(3);
            allowed_products.append(6);
            allowed_products.append(7);
            allowed_products.append(8);
            allowed_products.append(4);
            allowed_products.append(5);
            allowed_products.append(24);
            allowed_products.append(220);
            allowed_products.append(180);
            allowed_products.append(81);
            allowed_products.append(82);
            allowed_products.append(54);
            allowed_products.append(83);
            allowed_products.append(55);
            allowed_products.append(59);
            allowed_products.append(84);
            allowed_products.append(90);
            allowed_products.append(89);
            marketplaces.append(MarketplaceSettings {
                lot: 449470, name: 'PC-Y Volatiles and Redox', allowed_products: allowed_products.span()
            });

            allowed_products = Default::default();
            allowed_products.append(9);
            allowed_products.append(10);
            allowed_products.append(11);
            allowed_products.append(12);
            allowed_products.append(13);
            allowed_products.append(14);
            allowed_products.append(19);
            allowed_products.append(18);
            allowed_products.append(20);
            allowed_products.append(21);
            allowed_products.append(17);
            allowed_products.append(16);
            allowed_products.append(15);
            allowed_products.append(22);
            allowed_products.append(34);
            allowed_products.append(217);
            allowed_products.append(48);
            allowed_products.append(192);
            allowed_products.append(77);
            allowed_products.append(28);
            marketplaces.append(MarketplaceSettings {
                lot: 450080, name: 'PC-Y Raws and Carbonates', allowed_products: allowed_products.span()
            });

            allowed_products = Default::default();
            allowed_products.append(88);
            allowed_products.append(79);
            allowed_products.append(218);
            allowed_products.append(161);
            allowed_products.append(63);
            allowed_products.append(87);
            allowed_products.append(65);
            allowed_products.append(137);
            allowed_products.append(86);
            allowed_products.append(32);
            allowed_products.append(109);
            allowed_products.append(26);
            allowed_products.append(163);
            allowed_products.append(138);
            allowed_products.append(85);
            allowed_products.append(96);
            allowed_products.append(115);
            allowed_products.append(35);
            allowed_products.append(131);
            marketplaces.append(MarketplaceSettings {
                lot: 451533, name: 'PC-Y Oxides and Misc.', allowed_products: allowed_products.span()
            });

            allowed_products = Default::default();
            allowed_products.append(52);
            allowed_products.append(57);
            allowed_products.append(95);
            allowed_products.append(98);
            allowed_products.append(118);
            allowed_products.append(141);
            allowed_products.append(151);
            allowed_products.append(182);
            allowed_products.append(43);
            allowed_products.append(69);
            allowed_products.append(70);
            allowed_products.append(71);
            allowed_products.append(72);
            allowed_products.append(101);
            allowed_products.append(122);
            allowed_products.append(123);
            allowed_products.append(124);
            allowed_products.append(171);
            allowed_products.append(172);
            allowed_products.append(44);
            marketplaces.append(MarketplaceSettings {
                lot: 452143, name: 'PC-Y Alloys, Metals, Cement', allowed_products: allowed_products.span()
            });

            allowed_products = Default::default();
            allowed_products.append(175);
            allowed_products.append(170);
            allowed_products.append(129);
            allowed_products.append(103);
            allowed_products.append(92);
            allowed_products.append(91);
            allowed_products.append(64);
            allowed_products.append(140);
            allowed_products.append(108);
            allowed_products.append(200);
            allowed_products.append(56);
            allowed_products.append(114);
            allowed_products.append(189);
            allowed_products.append(191);
            allowed_products.append(190);
            allowed_products.append(58);
            allowed_products.append(74);
            allowed_products.append(102);
            marketplaces.append(MarketplaceSettings {
                lot: 464830, name: 'PC-Y Tools, Prop, Food, Crops', allowed_products: allowed_products.span()
            });

            allowed_products = Default::default();
            allowed_products.append(25);
            allowed_products.append(110);
            allowed_products.append(142);
            allowed_products.append(93);
            allowed_products.append(143);
            allowed_products.append(47);
            allowed_products.append(78);
            allowed_products.append(105);
            allowed_products.append(159);
            allowed_products.append(49);
            allowed_products.append(36);
            allowed_products.append(46);
            allowed_products.append(45);
            allowed_products.append(117);
            allowed_products.append(113);
            allowed_products.append(139);
            allowed_products.append(37);
            allowed_products.append(38);
            allowed_products.append(40);
            allowed_products.append(39);
            marketplaces.append(MarketplaceSettings {
                lot: 466804, name: 'PC-Y Salts and Sulfides', allowed_products: allowed_products.span()
            });

            allowed_products = Default::default();
            allowed_products.append(67);
            allowed_products.append(99);
            allowed_products.append(119);
            allowed_products.append(120);
            allowed_products.append(152);
            allowed_products.append(153);
            allowed_products.append(157);
            allowed_products.append(158);
            allowed_products.append(174);
            allowed_products.append(187);
            allowed_products.append(201);
            allowed_products.append(202);
            allowed_products.append(203);
            allowed_products.append(213);
            allowed_products.append(136);
            allowed_products.append(162);
            allowed_products.append(100);
            allowed_products.append(181);
            allowed_products.append(97);
            allowed_products.append(219);
            marketplaces.append(MarketplaceSettings {
                lot: 468024, name: 'PC-Y Electronics and Misc.', allowed_products: allowed_products.span()
            });
        } else if colony == 3 {
            let mut allowed_products: Array<u64> = Default::default();
            allowed_products.append(2);
            allowed_products.append(1);
            allowed_products.append(3);
            allowed_products.append(6);
            allowed_products.append(7);
            allowed_products.append(8);
            allowed_products.append(4);
            allowed_products.append(5);
            allowed_products.append(24);
            allowed_products.append(220);
            allowed_products.append(180);
            allowed_products.append(81);
            allowed_products.append(82);
            allowed_products.append(54);
            allowed_products.append(83);
            allowed_products.append(55);
            allowed_products.append(59);
            allowed_products.append(84);
            allowed_products.append(90);
            allowed_products.append(89);
            marketplaces.append(MarketplaceSettings {
                lot: 1089343, name: 'PC-S Volatiles and Redox', allowed_products: allowed_products.span()
            });

            allowed_products = Default::default();
            allowed_products.append(9);
            allowed_products.append(10);
            allowed_products.append(11);
            allowed_products.append(12);
            allowed_products.append(13);
            allowed_products.append(14);
            allowed_products.append(19);
            allowed_products.append(18);
            allowed_products.append(20);
            allowed_products.append(21);
            allowed_products.append(17);
            allowed_products.append(16);
            allowed_products.append(15);
            allowed_products.append(22);
            allowed_products.append(34);
            allowed_products.append(217);
            allowed_products.append(48);
            allowed_products.append(192);
            allowed_products.append(77);
            allowed_products.append(28);
            marketplaces.append(MarketplaceSettings {
                lot: 1092304, name: 'PC-S Raws and Carbonates', allowed_products: allowed_products.span()
            });

            allowed_products = Default::default();
            allowed_products.append(25);
            allowed_products.append(110);
            allowed_products.append(142);
            allowed_products.append(93);
            allowed_products.append(143);
            allowed_products.append(47);
            allowed_products.append(78);
            allowed_products.append(105);
            allowed_products.append(159);
            allowed_products.append(49);
            allowed_products.append(36);
            allowed_products.append(46);
            allowed_products.append(45);
            allowed_products.append(117);
            allowed_products.append(113);
            allowed_products.append(139);
            allowed_products.append(37);
            allowed_products.append(38);
            allowed_products.append(40);
            allowed_products.append(39);
            marketplaces.append(MarketplaceSettings {
                lot: 1095265, name: 'PC-S Salts and Sulfides', allowed_products: allowed_products.span()
            });

            allowed_products = Default::default();
            allowed_products.append(80);
            allowed_products.append(94);
            allowed_products.append(184);
            allowed_products.append(185);
            allowed_products.append(179);
            allowed_products.append(195);
            allowed_products.append(193);
            allowed_products.append(196);
            allowed_products.append(73);
            allowed_products.append(107);
            allowed_products.append(197);
            allowed_products.append(27);
            allowed_products.append(33);
            allowed_products.append(50);
            allowed_products.append(134);
            allowed_products.append(53);
            allowed_products.append(51);
            allowed_products.append(76);
            allowed_products.append(116);
            allowed_products.append(23);
            marketplaces.append(MarketplaceSettings {
                lot: 1098226, name: 'PC-S Nonmetals and Misc.', allowed_products: allowed_products.span()
            });

            allowed_products = Default::default();
            allowed_products.append(88);
            allowed_products.append(79);
            allowed_products.append(218);
            allowed_products.append(161);
            allowed_products.append(63);
            allowed_products.append(87);
            allowed_products.append(65);
            allowed_products.append(137);
            allowed_products.append(86);
            allowed_products.append(32);
            allowed_products.append(109);
            allowed_products.append(26);
            allowed_products.append(163);
            allowed_products.append(138);
            allowed_products.append(85);
            allowed_products.append(96);
            allowed_products.append(115);
            allowed_products.append(35);
            allowed_products.append(131);
            marketplaces.append(MarketplaceSettings {
                lot: 1101187, name: 'PC-S Oxides and Misc.', allowed_products: allowed_products.span()
            });

            allowed_products = Default::default();
            allowed_products.append(175);
            allowed_products.append(170);
            allowed_products.append(129);
            allowed_products.append(103);
            allowed_products.append(92);
            allowed_products.append(91);
            allowed_products.append(64);
            allowed_products.append(140);
            allowed_products.append(108);
            allowed_products.append(200);
            allowed_products.append(56);
            allowed_products.append(114);
            allowed_products.append(189);
            allowed_products.append(191);
            allowed_products.append(190);
            allowed_products.append(58);
            allowed_products.append(74);
            allowed_products.append(102);
            marketplaces.append(MarketplaceSettings {
                lot: 1104148, name: 'PC-S Tools, Prop, Food, Crops', allowed_products: allowed_products.span()
            });
        }

        return marketplaces.span();
    }

    fn colony_warehouses(colony: u64) -> Span<WarehouseSettings> {
        let mut warehouses: Array<WarehouseSettings> = Default::default();

        if colony == 1 {
            warehouses.append(WarehouseSettings { lot: 1598746, name: 'Arkos Freeshare SW1', public: true });
            warehouses.append(WarehouseSettings { lot: 1599966, name: 'Arkos Freeshare SW2', public: true });
            warehouses.append(WarehouseSettings { lot: 1613441, name: 'Arkos Freeshare SE1', public: true });
            warehouses.append(WarehouseSettings { lot: 1616635, name: 'Arkos Freeshare SE2', public: true });
            warehouses.append(WarehouseSettings { lot: 1592392, name: 'Arkos Freeshare N1', public: true });
            warehouses.append(WarehouseSettings { lot: 1594366, name: 'Arkos Freeshare N2', public: true });
            warehouses.append(WarehouseSettings { lot: 1595586, name: 'Arkos PC Depot N1', public: false });
            warehouses.append(WarehouseSettings { lot: 1597183, name: 'Arkos PC Depot N2', public: false });
            warehouses.append(WarehouseSettings { lot: 1598780, name: 'Arkos PC Depot N3', public: false });
            warehouses.append(WarehouseSettings { lot: 1600377, name: 'Arkos PC Depot N4', public: false });
            warehouses.append(WarehouseSettings { lot: 1601974, name: 'Arkos PC Depot N5', public: false });
            warehouses.append(WarehouseSettings { lot: 1602961, name: 'Arkos PC Depot N6', public: false });
            warehouses.append(WarehouseSettings { lot: 1604558, name: 'Arkos PC Depot N7', public: false });
            warehouses.append(WarehouseSettings { lot: 1605545, name: 'Arkos PC Depot N8', public: false });
            warehouses.append(WarehouseSettings { lot: 1592159, name: 'Arkos PC Depot N9', public: false });
            warehouses.append(WarehouseSettings { lot: 1591549, name: 'Arkos PC Depot N10', public: false });
            warehouses.append(WarehouseSettings { lot: 1590939, name: 'Arkos PC Depot N11', public: false });
            warehouses.append(WarehouseSettings { lot: 1590329, name: 'Arkos PC Depot N12', public: false });
            warehouses.append(WarehouseSettings { lot: 1591316, name: 'Arkos PC Depot N13', public: false });
            warehouses.append(WarehouseSettings { lot: 1590706, name: 'Arkos PC Depot N14', public: false });
            warehouses.append(WarehouseSettings { lot: 1591693, name: 'Arkos PC Depot N15', public: false });
            warehouses.append(WarehouseSettings { lot: 1591083, name: 'Arkos PC Depot N16', public: false });
            warehouses.append(WarehouseSettings { lot: 1597382, name: 'Arkos PC Depot SW1', public: false });
            warehouses.append(WarehouseSettings { lot: 1596395, name: 'Arkos PC Depot SW2', public: false });
            warehouses.append(WarehouseSettings { lot: 1595408, name: 'Arkos PC Depot SW3', public: false });
            warehouses.append(WarehouseSettings { lot: 1594421, name: 'Arkos PC Depot SW4', public: false });
            warehouses.append(WarehouseSettings { lot: 1593434, name: 'Arkos PC Depot SW5', public: false });
            warehouses.append(WarehouseSettings { lot: 1592447, name: 'Arkos PC Depot SW6', public: false });
            warehouses.append(WarehouseSettings { lot: 1591460, name: 'Arkos PC Depot SW7', public: false });
            warehouses.append(WarehouseSettings { lot: 1592070, name: 'Arkos PC Depot SW8', public: false });
            warehouses.append(WarehouseSettings { lot: 1601940, name: 'Arkos PC Depot SW9', public: false });
            warehouses.append(WarehouseSettings { lot: 1603537, name: 'Arkos PC Depot SW10', public: false });
            warehouses.append(WarehouseSettings { lot: 1605134, name: 'Arkos PC Depot SW11', public: false });
            warehouses.append(WarehouseSettings { lot: 1606731, name: 'Arkos PC Depot SW12', public: false });
            warehouses.append(WarehouseSettings { lot: 1608328, name: 'Arkos PC Depot SW13', public: false });
            warehouses.append(WarehouseSettings { lot: 1609925, name: 'Arkos PC Depot SW14', public: false });
            warehouses.append(WarehouseSettings { lot: 1610535, name: 'Arkos PC Depot SW15', public: false });
            warehouses.append(WarehouseSettings { lot: 1612132, name: 'Arkos PC Depot SW16', public: false });
            warehouses.append(WarehouseSettings { lot: 1613064, name: 'Arkos PC Depot SE1', public: false });
            warehouses.append(WarehouseSettings { lot: 1612077, name: 'Arkos PC Depot SE2', public: false });
            warehouses.append(WarehouseSettings { lot: 1612687, name: 'Arkos PC Depot SE3', public: false });
            warehouses.append(WarehouseSettings { lot: 1611700, name: 'Arkos PC Depot SE4', public: false });
            warehouses.append(WarehouseSettings { lot: 1610713, name: 'Arkos PC Depot SE5', public: false });
            warehouses.append(WarehouseSettings { lot: 1609116, name: 'Arkos PC Depot SE6', public: false });
            warehouses.append(WarehouseSettings { lot: 1608129, name: 'Arkos PC Depot SE7', public: false });
            warehouses.append(WarehouseSettings { lot: 1607142, name: 'Arkos PC Depot SE8', public: false });
            warehouses.append(WarehouseSettings { lot: 1615415, name: 'Arkos PC Depot SE9', public: false });
            warehouses.append(WarehouseSettings { lot: 1614805, name: 'Arkos PC Depot SE10', public: false });
            warehouses.append(WarehouseSettings { lot: 1614195, name: 'Arkos PC Depot SE11', public: false });
            warehouses.append(WarehouseSettings { lot: 1615182, name: 'Arkos PC Depot SE12', public: false });
            warehouses.append(WarehouseSettings { lot: 1614572, name: 'Arkos PC Depot SE13', public: false });
            warehouses.append(WarehouseSettings { lot: 1613962, name: 'Arkos PC Depot SE14', public: false });
            warehouses.append(WarehouseSettings { lot: 1613352, name: 'Arkos PC Depot SE15', public: false });
            warehouses.append(WarehouseSettings { lot: 1612742, name: 'Arkos PC Depot SE16', public: false });
        } else if colony == 2 {
            warehouses.append(WarehouseSettings { lot: 457078, name: 'Ya\'axche Freeshare Central', public: true });
            warehouses.append(WarehouseSettings { lot: 448483, name: 'Ya\'axche Freeshare Northeast', public: true });
            warehouses.append(WarehouseSettings { lot: 450546, name: 'Ya\'axche Freeshare Southeast', public: true });
            warehouses.append(WarehouseSettings { lot: 467414, name: 'Ya\'axche Freeshare West', public: true });
            warehouses.append(WarehouseSettings { lot: 454871, name: 'Ya\'axche PC Depot NE1', public: false });
            warehouses.append(WarehouseSettings { lot: 453274, name: 'Ya\'axche PC Depot NE2', public: false });
            warehouses.append(WarehouseSettings { lot: 451677, name: 'Ya\'axche PC Depot NE3', public: false });
            warehouses.append(WarehouseSettings { lot: 446886, name: 'Ya\'axche PC Depot NE5', public: false });
            warehouses.append(WarehouseSettings { lot: 448860, name: 'Ya\'axche PC Depot NE5', public: false });
            warehouses.append(WarehouseSettings { lot: 448250, name: 'Ya\'axche PC Depot NE6', public: false });
            warehouses.append(WarehouseSettings { lot: 446653, name: 'Ya\'axche PC Depot NE7', public: false });
            warehouses.append(WarehouseSettings { lot: 445289, name: 'Ya\'axche PC Depot NE8', public: false });
            warehouses.append(WarehouseSettings { lot: 444912, name: 'Ya\'axche PC Depot NE9', public: false });
            warehouses.append(WarehouseSettings { lot: 442328, name: 'Ya\'axche PC Depot NE10', public: false });
            warehouses.append(WarehouseSettings { lot: 440731, name: 'Ya\'axche PC Depot NE11', public: false });
            warehouses.append(WarehouseSettings { lot: 443692, name: 'Ya\'axche PC Depot NE12', public: false });
            warehouses.append(WarehouseSettings { lot: 454494, name: 'Ya\'axche PC Depot SE1', public: false });
            warehouses.append(WarehouseSettings { lot: 453507, name: 'Ya\'axche PC Depot SE2', public: false });
            warehouses.append(WarehouseSettings { lot: 452520, name: 'Ya\'axche PC Depot SE3', public: false });
            warehouses.append(WarehouseSettings { lot: 449559, name: 'Ya\'axche PC Depot SE4', public: false });
            warehouses.append(WarehouseSettings { lot: 446365, name: 'Ya\'axche PC Depot SE5', public: false });
            warehouses.append(WarehouseSettings { lot: 443781, name: 'Ya\'axche PC Depot SE6', public: false });
            warehouses.append(WarehouseSettings { lot: 442794, name: 'Ya\'axche PC Depot SE7', public: false });
            warehouses.append(WarehouseSettings { lot: 448572, name: 'Ya\'axche PC Depot SE8', public: false });
            warehouses.append(WarehouseSettings { lot: 452753, name: 'Ya\'axche PC Depot SE9', public: false });
            warehouses.append(WarehouseSettings { lot: 453363, name: 'Ya\'axche PC Depot SE10', public: false });
            warehouses.append(WarehouseSettings { lot: 452376, name: 'Ya\'axche PC Depot SE11', public: false });
            warehouses.append(WarehouseSettings { lot: 447585, name: 'Ya\'axche PC Depot SE12', public: false });
            warehouses.append(WarehouseSettings { lot: 456468, name: 'Ya\'axche PC Depot W1', public: false });
            warehouses.append(WarehouseSettings { lot: 459662, name: 'Ya\'axche PC Depot W2', public: false });
            warehouses.append(WarehouseSettings { lot: 462246, name: 'Ya\'axche PC Depot W3', public: false });
            warehouses.append(WarehouseSettings { lot: 469998, name: 'Ya\'axche PC Depot W4', public: false });
            warehouses.append(WarehouseSettings { lot: 467791, name: 'Ya\'axche PC Depot W5', public: false });
            warehouses.append(WarehouseSettings { lot: 468778, name: 'Ya\'axche PC Depot W6', public: false });
            warehouses.append(WarehouseSettings { lot: 471362, name: 'Ya\'axche PC Depot W7', public: false });
            warehouses.append(WarehouseSettings { lot: 472582, name: 'Ya\'axche PC Depot W8', public: false });
            warehouses.append(WarehouseSettings { lot: 469621, name: 'Ya\'axche PC Depot W9', public: false });
            warehouses.append(WarehouseSettings { lot: 471218, name: 'Ya\'axche PC Depot W10', public: false });
            warehouses.append(WarehouseSettings { lot: 473802, name: 'Ya\'axche PC Depot W11', public: false });
            warehouses.append(WarehouseSettings { lot: 475166, name: 'Ya\'axche PC Depot W12', public: false });
        } else if colony == 3 {
            warehouses.append(WarehouseSettings { lot: 1094655, name: 'Saline Freeshare Sodium', public: true });
            warehouses.append(WarehouseSettings { lot: 1097849, name: 'Saline Freeshare Chloride', public: true });
            warehouses.append(WarehouseSettings { lot: 1085539, name: 'Saline PC Depot 1A', public: false });
            warehouses.append(WarehouseSettings { lot: 1088733, name: 'Saline PC Depot 1B', public: false });
            warehouses.append(WarehouseSettings { lot: 1091927, name: 'Saline PC Depot 1C', public: false });
            warehouses.append(WarehouseSettings { lot: 1095121, name: 'Saline PC Depot 1D', public: false });
            warehouses.append(WarehouseSettings { lot: 1088500, name: 'Saline PC Depot 2A', public: false });
            warehouses.append(WarehouseSettings { lot: 1091694, name: 'Saline PC Depot 2B', public: false });
            warehouses.append(WarehouseSettings { lot: 1094888, name: 'Saline PC Depot 2C', public: false });
            warehouses.append(WarehouseSettings { lot: 1098082, name: 'Saline PC Depot 2D', public: false });
            warehouses.append(WarehouseSettings { lot: 1091461, name: 'Saline PC Depot 3A', public: false });
            warehouses.append(WarehouseSettings { lot: 1093058, name: 'Saline PC Depot 3B', public: false });
            warehouses.append(WarehouseSettings { lot: 1099446, name: 'Saline PC Depot 3C', public: false });
            warehouses.append(WarehouseSettings { lot: 1101043, name: 'Saline PC Depot 3D', public: false });
            warehouses.append(WarehouseSettings { lot: 1094422, name: 'Saline PC Depot 4A', public: false });
            warehouses.append(WarehouseSettings { lot: 1097616, name: 'Saline PC Depot 4B', public: false });
            warehouses.append(WarehouseSettings { lot: 1100810, name: 'Saline PC Depot 4C', public: false });
            warehouses.append(WarehouseSettings { lot: 1104004, name: 'Saline PC Depot 4D', public: false });
            warehouses.append(WarehouseSettings { lot: 1097383, name: 'Saline PC Depot 5A', public: false });
            warehouses.append(WarehouseSettings { lot: 1100577, name: 'Saline PC Depot 5B', public: false });
            warehouses.append(WarehouseSettings { lot: 1103771, name: 'Saline PC Depot 5C', public: false });
            warehouses.append(WarehouseSettings { lot: 1106965, name: 'Saline PC Depot 5D', public: false });
            warehouses.append(WarehouseSettings { lot: 1100344, name: 'Saline PC Depot 6A', public: false });
            warehouses.append(WarehouseSettings { lot: 1103538, name: 'Saline PC Depot 6B', public: false });
            warehouses.append(WarehouseSettings { lot: 1106732, name: 'Saline PC Depot 6C', public: false });
            warehouses.append(WarehouseSettings { lot: 1109926, name: 'Saline PC Depot 6D', public: false });
        }

        return warehouses.span();
    }
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use traits::Into;

    use cubit::{f64, f128};

    use influence::{components, config};
    use influence::components::{Crew, CrewTrait, Exchange, Location, LocationTrait, Name, Orbit,
        celestial::{statuses as celestial_statuses, types as celestial_types, Celestial, CelestialTrait},
        building_type::types as building_types};
    use influence::config::entities;
    use influence::contracts::crew::{ICrewDispatcher, ICrewDispatcherTrait};
    use influence::contracts::crewmate::{ICrewmateDispatcher, ICrewmateDispatcherTrait};
    use influence::types::{SpanTraitExt, Context, Entity, EntityTrait, InventoryItemTrait, StringTrait};
    use influence::test::{helpers, mocks};

    use super::SeedColony;

    #[test]
    #[available_gas(150000000)]
    fn test_seed() {
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        helpers::init();
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

        // Add building config
        mocks::building_type(building_types::WAREHOUSE);
        mocks::building_type(building_types::MARKETPLACE);
        mocks::building_type(building_types::HABITAT);
        mocks::building_type(building_types::SPACEPORT);

        let crew_address = helpers::deploy_crew();
        let crewmate_address = helpers::deploy_crewmate();

        starknet::testing::set_contract_address(starknet::contract_address_const::<'ADMIN'>());
        ICrewDispatcher { contract_address: crew_address }
            .add_grant(starknet::contract_address_const::<'DISPATCHER'>(), 2);

        ICrewmateDispatcher { contract_address: crewmate_address }
            .add_grant(starknet::contract_address_const::<'DISPATCHER'>(), 2);

        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        let mut state = SeedColony::contract_state_for_testing();
        SeedColony::run(ref state, 2, building_types::HABITAT, mocks::context('ADMIN'));

        // Check for results
        let habitat = EntityTrait::new(entities::BUILDING, 13);
        let hab_location = components::get::<Location>(habitat.path()).unwrap();
        assert(hab_location.location == EntityTrait::from_position(1, 446975), 'wrong hab location');

        // Check for name
        let hab_name = components::get::<Name>(habitat.path()).unwrap();
        assert(hab_name.name.value == 'Dragon\'s Blood', 'wrong hab name');

        SeedColony::run(ref state, 2, building_types::MARKETPLACE, mocks::context('ADMIN'));

        // Check for results
        let marketplace = EntityTrait::new(entities::BUILDING, 35);
        let market_location = components::get::<Location>(marketplace.path()).unwrap();
        assert(market_location.location == EntityTrait::from_position(1, 448949), 'wrong market location');

        // Check allowed products
        let exchange_data = components::get::<Exchange>(marketplace.path()).unwrap();
        assert(exchange_data.allowed_products.contains(112), 'missing product 112');
    }
}
