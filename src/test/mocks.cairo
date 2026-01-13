use array::ArrayTrait;
use option::OptionTrait;
use starknet::{contract_address_try_from_felt252, ContractAddress};
use starknet::storage_access::{StorageBaseAddress, storage_base_address_const};
use traits::Into;

use cubit::{f64, f128};

use influence::{components, config};
use influence::components::{Crew, CrewTrait, Crewmate, CrewmateTrait, Control, ControlTrait, Dock, DockTrait, DryDock,
    DryDockTrait, Exchange, ExchangeTrait, PublicPolicy, Station, StationTrait,
    building::{statuses as building_statuses, Building, BuildingTrait},
    building_type::{types as building_types, BuildingType},
    celestial::{types as celestial_types, statuses as celestial_statuses, Celestial, CelestialTrait},
    crewmate::{classes, crewmate_traits, departments},
    deposit::{statuses as deposit_statuses, Deposit, DepositTrait},
    dock_type::{types as dock_types, DockType},
    dry_dock_type::{types as dry_dock_types, DryDockType},
    exchange_type::{types as exchange_types, ExchangeType},
    extractor::{types as extractor_types, Extractor, ExtractorTrait},
    inventory::{Inventory, InventoryTrait, MAX_AMOUNT},
    inventory_type::{types as inventory_types, InventoryType},
    modifier_type::{types as modifier_types, ModifierType},
    process_type::{types as process_types, ProcessType},
    processor::{types as processor_types, Processor, ProcessorTrait},
    product_type::{types as product_types, ProductType},
    ship::{statuses as ship_statuses, Ship, ShipTrait},
    ship_type::{types as ship_types, ShipType, ShipTypeTrait},
    ship_variant_type::{types as ship_variant_types, ShipVariantType},
    station_type::{types as station_types, StationType}};
use influence::config::{entities, permissions};
use influence::systems::policies::helpers::policy_path;
use influence::types::{Context, Entity, EntityTrait, InventoryItem, InventoryItemTrait};

fn context(caller: felt252) -> Context {
    return Context {
        caller: contract_address_try_from_felt252(caller).unwrap(),
        now: starknet::get_block_timestamp(),
        payment_to: starknet::contract_address_const::<0>(),
        payment_amount: 0
    };
}

fn pilot(id: u64) -> Entity {
    let pilot = EntityTrait::new(entities::CREWMATE, id);
    let mut crew_data = CrewmateTrait::new(1);
    crew_data.class = 1;
    crew_data.status = 1;
    components::set::<Crewmate>(pilot.path(), crew_data);
    return pilot;
}

fn delegated_crew(id: u64, address: felt252) -> Entity {
    let pilot = EntityTrait::new(entities::CREWMATE, id);
    let mut crewmate_data = CrewmateTrait::new(1);
    crewmate_data.class = 1;
    crewmate_data.status = 1;
    components::set::<Crewmate>(pilot.path(), crewmate_data);

    let crew = EntityTrait::new(entities::CREW, id);
    let address = contract_address_try_from_felt252(address).unwrap();
    let mut crew_data = CrewTrait::new(address);
    let mut new_roster = Default::default();
    new_roster.append(pilot.id);
    crew_data.roster = new_roster.span();
    components::set::<Crew>(crew.path(), crew_data);

    components::set::<Ship>(crew.path(), Ship {
        ship_type: ship_types::ESCAPE_MODULE,
        status: ship_statuses::DISABLED,
        ready_at: 0,
        emergency_at: 0,
        variant: 1,
        transit_origin: EntityTrait::new(0, 0),
        transit_departure: 0,
        transit_destination: EntityTrait::new(0, 0),
        transit_arrival: 0
    });

    // Add configs
    modifier_type(modifier_types::FOOD_CONSUMPTION_TIME);
    modifier_type(modifier_types::FOOD_RATIONING_PENALTY);
    inventory_type(inventory_types::PROPELLANT_TINY);
    ship_type(ship_types::ESCAPE_MODULE);

    let ship_config = ShipTypeTrait::by_type(ship_types::ESCAPE_MODULE);
    let mut inv_path: Array<felt252> = Default::default();
    inv_path.append(crew.into());
    inv_path.append(ship_config.propellant_slot.into());

    let mut inv_data = InventoryTrait::new(inventory_types::PROPELLANT_TINY);
    inv_data.disable();
    components::set::<Inventory>(inv_path.span(), inv_data);

    return crew;
}

fn public_habitat(crew: Entity, id: u64) -> Entity {
    let station = EntityTrait::new(entities::BUILDING, id);
    components::set::<Control>(station.path(), ControlTrait::new(crew));
    components::set::<Building>(station.path(), Building {
        building_type: building_types::HABITAT,
        status: building_statuses::OPERATIONAL,
        planned_at: 0,
        finish_time: 0
    });

    station_type(station_types::HABITAT);

    components::set::<PublicPolicy>(policy_path(station, permissions::RECRUIT_CREWMATE), PublicPolicy { public: true });
    components::set::<Station>(station.path(), StationTrait::new(station_types::HABITAT));
    return station;
}

fn public_spaceport(crew: Entity, id: u64) -> Entity {
    let spaceport = EntityTrait::new(entities::BUILDING, id);
    components::set::<Control>(spaceport.path(), ControlTrait::new(crew));
    components::set::<Building>(spaceport.path(), Building {
        building_type: building_types::SPACEPORT,
        status: building_statuses::OPERATIONAL,
        planned_at: 0,
        finish_time: 0
    });

    components::set::<PublicPolicy>(policy_path(spaceport, permissions::DOCK_SHIP), PublicPolicy { public: true });
    components::set::<Dock>(spaceport.path(), DockTrait::new(dock_types::BASIC));
    return spaceport;
}

fn public_extractor(crew: Entity, id: u64) -> Entity {
    let extractor = EntityTrait::new(entities::BUILDING, id);
    components::set::<Control>(extractor.path(), ControlTrait::new(crew));
    components::set::<PublicPolicy>(
        policy_path(extractor, permissions::EXTRACT_RESOURCES), PublicPolicy { public: true }
    );

    components::set::<Building>(extractor.path(), Building {
        building_type: building_types::EXTRACTOR,
        status: building_statuses::OPERATIONAL,
        planned_at: 0,
        finish_time: 0
    });

    let mut extractor_path: Array<felt252> = Default::default();
    extractor_path.append(extractor.into());
    extractor_path.append(1);
    components::set::<Extractor>(extractor_path.span(), ExtractorTrait::new(extractor_types::BASIC));

    return extractor;
}

fn public_refinery(crew: Entity, id: u64) -> Entity {
    let refinery = EntityTrait::new(entities::BUILDING, id);
    components::set::<Control>(refinery.path(), ControlTrait::new(crew));
    components::set::<PublicPolicy>(policy_path(refinery, permissions::RUN_PROCESS), PublicPolicy { public: true });

    components::set::<Building>(refinery.path(), Building {
        building_type: building_types::REFINERY,
        status: building_statuses::OPERATIONAL,
        planned_at: 0,
        finish_time: 0
    });

    let mut processor_path: Array<felt252> = Default::default();
    processor_path.append(refinery.into());
    processor_path.append(1);
    components::set::<Processor>(processor_path.span(), ProcessorTrait::new(processor_types::REFINERY));

    return refinery;
}

fn public_bioreactor(crew: Entity, id: u64) -> Entity {
    let bioreactor = EntityTrait::new(entities::BUILDING, id);
    components::set::<Control>(bioreactor.path(), ControlTrait::new(crew));
    components::set::<PublicPolicy>(policy_path(bioreactor, permissions::RUN_PROCESS), PublicPolicy { public: true });

    components::set::<Building>(bioreactor.path(), Building {
        building_type: building_types::BIOREACTOR,
        status: building_statuses::OPERATIONAL,
        planned_at: 0,
        finish_time: 0
    });

    let mut processor_path: Array<felt252> = Default::default();
    processor_path.append(bioreactor.into());
    processor_path.append(1);
    components::set::<Processor>(processor_path.span(), ProcessorTrait::new(processor_types::BIOREACTOR));

    return bioreactor;
}

fn public_shipyard(crew: Entity, id: u64) -> Entity {
    let shipyard = EntityTrait::new(entities::BUILDING, id);
    components::set::<Control>(shipyard.path(), ControlTrait::new(crew));
    components::set::<PublicPolicy>(policy_path(shipyard, permissions::RUN_PROCESS), PublicPolicy { public: true });
    components::set::<PublicPolicy>(policy_path(shipyard, permissions::ASSEMBLE_SHIP), PublicPolicy { public: true });

    components::set::<Building>(shipyard.path(), Building {
        building_type: building_types::SHIPYARD,
        status: building_statuses::OPERATIONAL,
        planned_at: 0,
        finish_time: 0
    });

    let mut processor_path: Array<felt252> = Default::default();
    processor_path.append(shipyard.into());
    processor_path.append(1);
    components::set::<Processor>(processor_path.span(), ProcessorTrait::new(processor_types::SHIPYARD));
    components::set::<DryDock>(processor_path.span(), DryDockTrait::new(1));

    return shipyard;
}

fn public_marketplace(crew: Entity, id: u64) -> Entity {
    let marketplace = EntityTrait::new(entities::BUILDING, id);
    components::set::<Control>(marketplace.path(), ControlTrait::new(crew));
    components::set::<PublicPolicy>(policy_path(marketplace, permissions::LIMIT_SELL), PublicPolicy { public: true });
    components::set::<PublicPolicy>(policy_path(marketplace, permissions::LIMIT_BUY), PublicPolicy { public: true });
    components::set::<PublicPolicy>(policy_path(marketplace, permissions::SELL), PublicPolicy { public: true });
    components::set::<PublicPolicy>(policy_path(marketplace, permissions::BUY), PublicPolicy { public: true });

    components::set::<Building>(marketplace.path(), Building {
        building_type: building_types::MARKETPLACE,
        status: building_statuses::OPERATIONAL,
        planned_at: 0,
        finish_time: 0
    });

    let mut allowed_products: Array<u64> = Default::default();
    allowed_products.append(1);
    allowed_products.append(2);
    allowed_products.append(3);
    allowed_products.append(4);
    allowed_products.append(5);
    allowed_products.append(6);
    allowed_products.append(7);
    allowed_products.append(8);
    allowed_products.append(9);
    allowed_products.append(10);
    allowed_products.append(11);
    allowed_products.append(12);
    allowed_products.append(13);
    allowed_products.append(14);
    allowed_products.append(15);
    allowed_products.append(16);
    allowed_products.append(17);
    allowed_products.append(18);
    allowed_products.append(19);
    allowed_products.append(20);

    components::set::<Exchange>(marketplace.path(), Exchange {
        exchange_type: exchange_types::BASIC,
        maker_fee: 100, // fee in ten thousandths (i.e. 0.25% == 25)
        taker_fee: 100, // fee in ten thousandths
        orders: 0, // count of open orders
        allowed_products: allowed_products.span()
    });

    return marketplace;
}

fn public_warehouse(crew: Entity, id: u64) -> Entity {
    let warehouse = EntityTrait::new(entities::BUILDING, id);
    components::set::<Control>(warehouse.path(), ControlTrait::new(crew));
    components::set::<PublicPolicy>(policy_path(warehouse, permissions::RUN_PROCESS), PublicPolicy { public: true });

    building_type(building_types::WAREHOUSE);
    components::set::<Building>(warehouse.path(), Building {
        building_type: building_types::WAREHOUSE,
        status: building_statuses::OPERATIONAL,
        planned_at: 0,
        finish_time: 0
    });

    inventory_type(inventory_types::WAREHOUSE_PRIMARY);
    let mut inventory_path: Array<felt252> = Default::default();
    inventory_path.append(warehouse.into());
    inventory_path.append(2);
    components::set::<Inventory>(inventory_path.span(), InventoryTrait::new(inventory_types::WAREHOUSE_PRIMARY));

    return warehouse;
}

fn controlled_light_transport(crew: Entity, id: u64) -> Entity {
    let ship = EntityTrait::new(entities::SHIP, id);
    components::set::<Control>(ship.path(), ControlTrait::new(crew));
    components::set::<Ship>(ship.path(), Ship {
        ship_type: ship_types::LIGHT_TRANSPORT,
        status: 1,
        ready_at: 0,
        emergency_at: 0,
        variant: 1,
        transit_origin: EntityTrait::new(0, 0),
        transit_departure: 0,
        transit_destination: EntityTrait::new(0, 0),
        transit_arrival: 0
    });

    inventory_type(inventory_types::CARGO_MEDIUM);
    inventory_type(inventory_types::PROPELLANT_MEDIUM);
    station_type(station_types::STANDARD_QUARTERS);
    ship_type(ship_types::LIGHT_TRANSPORT);

    let config = ShipTypeTrait::by_type(ship_types::LIGHT_TRANSPORT);
    let mut prop_path: Array<felt252> = Default::default();
    prop_path.append(ship.into());
    prop_path.append(config.propellant_slot.into());
    components::set::<Inventory>(prop_path.span(), InventoryTrait::new(inventory_types::PROPELLANT_MEDIUM));

    let mut cargo_path: Array<felt252> = Default::default();
    cargo_path.append(ship.into());
    cargo_path.append(config.cargo_slot.into());
    components::set::<Inventory>(cargo_path.span(), InventoryTrait::new(inventory_types::CARGO_MEDIUM));

    components::set::<Station>(ship.path(), StationTrait::new(station_types::STANDARD_QUARTERS));

    return ship;
}

fn controlled_deposit(crew: Entity, id: u64, resource_type: u64) -> Entity {
    let deposit = EntityTrait::new(entities::DEPOSIT, id);
    components::set::<Control>(deposit.path(), ControlTrait::new(crew));
    let mut deposit_data = DepositTrait::new(resource_type);
    deposit_data.status = deposit_statuses::SAMPLED;
    deposit_data.initial_yield = 1000000;
    deposit_data.remaining_yield = 1000000;
    components::set::<Deposit>(deposit.path(), deposit_data);
    return deposit;
}

fn adalia_prime() -> Entity {
    let asteroid = EntityTrait::new(entities::ASTEROID, 1);
    let mass = f128::FixedTrait::new_unscaled(309601968481880060, false); // tonnes
    let radius = f64::FixedTrait::new(1611222621356, false); // 375.142 km
    components::set::<Celestial>(
        asteroid.path(), CelestialTrait::new(celestial_types::C_TYPE_ASTEROID, mass, radius)
    );
    return asteroid;
}

fn asteroid() -> Entity {
    let asteroid = EntityTrait::new(entities::ASTEROID, 104);
    let mass = f128::FixedTrait::new_unscaled(925571064959299, false); // tonnes
    let radius = f64::FixedTrait::new(177445387564, false); // 41.3147238 km
    components::set::<Celestial>(
        asteroid.path(), CelestialTrait::new(celestial_types::CMS_TYPE_ASTEROID, mass, radius)
    );
    return asteroid;
}

fn modifier_type(modifier_type: u64) {
    let mut config = ModifierType {
        class: 0,
        trait_type: 0,
        trait_eff: 0,
        dept_type: 0,
        dept_eff: 0,
        mgmt_eff: 0,
        further_modified: true
    };

    if modifier_type == modifier_types::CORE_SAMPLE_TIME {
        config.class = classes::MINER;
        config.trait_type = crewmate_traits::SURVEYOR;
        config.trait_eff = 1000;
        config.mgmt_eff = 50;
    } else if modifier_type == modifier_types::CORE_SAMPLE_QUALITY {
        config.class = classes::MINER;
        config.trait_type = crewmate_traits::PROSPECTOR;
        config.trait_eff = 500;
        config.further_modified = false;
    } else if modifier_type == modifier_types::EXTRACTION_TIME {
        config.class = classes::MINER;
        config.mgmt_eff = 50;
    } else if modifier_type == modifier_types::HOPPER_TRANSPORT_TIME {
        config.dept_type = departments::LOGISTICS;
        config.dept_eff = 125;
        config.trait_type = crewmate_traits::LOGISTICIAN;
        config.trait_eff = 500;
        config.mgmt_eff = 50;
    } else if modifier_type == modifier_types::FREE_TRANSPORT_DISTANCE {
        config.class = classes::MERCHANT;
    } else if modifier_type == modifier_types::INVENTORY_MASS_CAPACITY {
        config.trait_type = crewmate_traits::HAULER;
        config.trait_eff = 500;
        config.further_modified = false;
    } else if modifier_type == modifier_types::INVENTORY_VOLUME_CAPACITY {
        config.dept_type = departments::LOGISTICS;
        config.dept_eff = 125;
        config.further_modified = false;
    } else if modifier_type == modifier_types::PROPELLANT_EXHAUST_VELOCITY {
        config.class = classes::PILOT;
        config.dept_type = departments::NAVIGATION;
        config.dept_eff = 100;
        config.trait_type = crewmate_traits::NAVIGATOR;
        config.trait_eff = 200;
        config.further_modified = false;
    } else if modifier_type == modifier_types::PROPELLANT_FLOW_RATE {
        config.class = classes::PILOT;
        config.dept_type = departments::NAVIGATION;
        config.dept_eff = 100;
        config.trait_type = crewmate_traits::BUSTER;
        config.trait_eff = 200;
        config.further_modified = false;
    } else if modifier_type == modifier_types::CONSTRUCTION_TIME {
        config.class = classes::ENGINEER;
        config.trait_type = crewmate_traits::BUILDER;
        config.trait_eff = 500;
        config.mgmt_eff = 50;
    } else if modifier_type == modifier_types::DECONSTRUCTION_YIELD {
        config.trait_type = crewmate_traits::RECYCLER;
        config.trait_eff = 1000;
    } else if modifier_type == modifier_types::REFINING_TIME {
        config.class = classes::ENGINEER;
        config.trait_type = crewmate_traits::REFINER;
        config.trait_eff = 500;
        config.dept_type = departments::ENGINEERING;
        config.dept_eff = 125;
        config.mgmt_eff = 50;
    } else if modifier_type == modifier_types::SECONDARY_REFINING_YIELD {
        config.class = classes::SCIENTIST;
        config.further_modified = false;
    } else if modifier_type == modifier_types::MANUFACTURING_TIME {
        config.class = classes::ENGINEER;
        config.dept_type = departments::ENGINEERING;
        config.dept_eff = 125;
        config.mgmt_eff = 50;
    } else if modifier_type == modifier_types::REACTION_TIME {
        config.class = classes::SCIENTIST;
        config.dept_type = departments::FOOD_PRODUCTION;
        config.dept_eff = 250;
        config.mgmt_eff = 50;
    } else if modifier_type == modifier_types::FOOD_CONSUMPTION_TIME {
        config.trait_type = crewmate_traits::DIETITIAN;
        config.trait_eff = 500;
        config.dept_type = departments::FOOD_PREPARATION;
        config.dept_eff = 250;
    } else if modifier_type == modifier_types::FOOD_RATIONING_PENALTY {
        config.dept_type = departments::MEDICINE;
        config.dept_eff = 83;
    } else if modifier_type == modifier_types::MARKETPLACE_FEE_ENFORCEMENT {
        config.trait_type = crewmate_traits::MOGUL;
        config.trait_eff = 1600;
        config.further_modified = false;
    } else if modifier_type == modifier_types::MARKETPLACE_FEE_REDUCTION {
        config.class = classes::MERCHANT;
        config.dept_type = departments::ARTS_ENTERTAINMENT;
        config.dept_eff = 500;
    } else if modifier_type == modifier_types::SHIP_INTEGRATION_TIME {
        config.class = classes::ENGINEER;
        config.dept_type = departments::ENGINEERING;
        config.dept_eff = 125;
        config.mgmt_eff = 50;
    }

    let mut mod_path: Array<felt252> = Default::default();
    mod_path.append(modifier_type.into());
    components::set::<ModifierType>(mod_path.span(), config);
}

fn process_type(process_type: u64) {
    let mut inputs: Array<InventoryItem> = Default::default();
    let mut outputs: Array<InventoryItem> = Default::default();
    let mut config = ProcessType {
        setup_time: 0,
        recipe_time: 0,
        batched: false,
        processor_type: 0,
        inputs: inputs.span(),
        outputs: outputs.span()
    };

    if process_type == process_types::WAREHOUSE_CONSTRUCTION {
        config.setup_time = 1728000;
        inputs.append(InventoryItemTrait::new(product_types::CEMENT, 400000));
        inputs.append(InventoryItemTrait::new(product_types::STEEL_BEAM, 350000));
        inputs.append(InventoryItemTrait::new(product_types::STEEL_SHEET, 200000));
        config.inputs = inputs.span();
    } else if process_type == process_types::AMMONIA_CATALYTIC_CRACKING {
        config.setup_time = 79200;
        config.recipe_time = 97560;
        config.processor_type = processor_types::REFINERY;
        inputs.append(InventoryItemTrait::new(product_types::AMMONIA, 40));
        outputs.append(InventoryItemTrait::new(product_types::HYDROGEN, 6));
        outputs.append(InventoryItemTrait::new(product_types::PURE_NITROGEN, 34));
        config.inputs = inputs.span();
        config.outputs = outputs.span();
    } else if process_type == process_types::SHUTTLE_INTEGRATION {
        config.setup_time = 1658880;
        config.recipe_time = 414720000;
        config.processor_type = processor_types::SHIPYARD;
        inputs.append(InventoryItemTrait::new(product_types::SHUTTLE_HULL, 1));
        inputs.append(InventoryItemTrait::new(product_types::AVIONICS_MODULE, 1));
        inputs.append(InventoryItemTrait::new(product_types::ESCAPE_MODULE, 3));
        inputs.append(InventoryItemTrait::new(product_types::ATTITUDE_CONTROL_MODULE, 1));
        inputs.append(InventoryItemTrait::new(product_types::POWER_MODULE, 2));
        inputs.append(InventoryItemTrait::new(product_types::THERMAL_MODULE, 1));
        inputs.append(InventoryItemTrait::new(product_types::PROPULSION_MODULE, 1));
        config.inputs = inputs.span();
    } else if process_type == process_types::EXTRACTOR_CONSTRUCTION {
        config.setup_time = 2073600;
        inputs.append(InventoryItemTrait::new(product_types::CEMENT, 250000));
        inputs.append(InventoryItemTrait::new(product_types::STEEL_BEAM, 300000));
        inputs.append(InventoryItemTrait::new(product_types::POLYACRYLONITRILE_FABRIC, 3000));
        inputs.append(InventoryItemTrait::new(product_types::FLUIDS_AUTOMATION_MODULE, 1));
        inputs.append(InventoryItemTrait::new(product_types::POWER_MODULE, 6));
        config.inputs = inputs.span();
    }

    let mut process_path: Array<felt252> = Default::default();
    process_path.append(process_type.into());
    components::set::<ProcessType>(process_path.span(), config);
}

fn product_type(product_type: u64) {
    let mut config = ProductType { mass: 0, volume: 0 };

    if product_type == product_types::WATER {
        config.mass = 1000;
        config.volume = 971;
    } else if product_type == product_types::HYDROGEN {
        config.mass = 1000;
        config.volume = 14100;
    } else if product_type == product_types::AMMONIA {
        config.mass = 1000;
        config.volume = 1370;
    } else if product_type == product_types::NITROGEN {
        config.mass = 1000;
        config.volume = 1240;
    } else if product_type == product_types::HYDROGEN_PROPELLANT {
        config.mass = 1000;
        config.volume = 13300;
    } else if product_type == product_types::CEMENT {
        config.mass = 1000;
        config.volume = 1130;
    } else if product_type == product_types::STEEL_BEAM {
        config.mass = 1000;
        config.volume = 1100;
    } else if product_type == product_types::STEEL_SHEET {
        config.mass = 1000;
        config.volume = 150;
    } else if product_type == product_types::CORE_DRILL {
        config.mass = 30000;
        config.volume = 107100;
    } else if product_type == product_types::CARBON_MONOXIDE {
        config.mass = 1000;
        config.volume = 1250;
    } else if product_type == product_types::PURE_NITROGEN {
        config.mass = 1000;
        config.volume = 1240;
    } else if product_type == product_types::SHUTTLE_HULL {
        config.mass = 44600000;
        config.volume = 16011400000;
    } else if product_type == product_types::AVIONICS_MODULE {
        config.mass = 500000;
        config.volume = 12200000;
    } else if product_type == product_types::ESCAPE_MODULE {
        config.mass = 6665000;
        config.volume = 339915000;
    } else if product_type == product_types::ATTITUDE_CONTROL_MODULE {
        config.mass = 660000;
        config.volume = 2976600;
    } else if product_type == product_types::POWER_MODULE {
        config.mass = 1000000;
        config.volume = 3800000;
    } else if product_type == product_types::THERMAL_MODULE {
        config.mass = 1000000;
        config.volume = 399000;
    } else if product_type == product_types::PROPULSION_MODULE {
        config.mass = 32000000;
        config.volume = 106560000;
    } else if product_type == product_types::HYDROGEN_PROPELLANT {
        config.mass = 1000;
        config.volume = 13300;
    } else if product_type == product_types::FOOD {
        config.mass = 1000;
        config.volume = 1250;
    } else if product_type == product_types::POLYACRYLONITRILE_FABRIC {
        config.mass = 1000;
        config.volume = 2820;
    } else if product_type == product_types::FLUIDS_AUTOMATION_MODULE {
        config.mass = 3600000;
        config.volume = 301320000;
    } else if product_type == product_types::POWER_MODULE {
        config.mass = 1000000;
        config.volume = 3800000;
    } else if product_type == product_types::SPIRULINA_AND_CHLORELLA_ALGAE {
        config.mass = 1000;
        config.volume = 2500;
    } else if product_type == product_types::SOYBEANS {
        config.mass = 1000;
        config.volume = 1530;
    } else if product_type == product_types::BISPHENOL_A {
        config.mass = 1000;
        config.volume = 1040;
    } else if product_type == product_types::NOVOLAK_PREPOLYMER_RESIN {
        config.mass = 1000;
        config.volume = 1020;
    } else if product_type == product_types::PEDOT {
        config.mass = 1000;
        config.volume = 989;
    } else if product_type == product_types::SOIL {
        config.mass = 1000;
        config.volume = 714;
    }

    let mut product_path: Array<felt252> = Default::default();
    product_path.append(product_type.into());
    components::set::<ProductType>(product_path.span(), config);
}

fn inventory_type(inventory_type: u64) {
    let mut products: Array<InventoryItem> = Default::default();
    let mut config = InventoryType {
        mass: 0,
        volume: 0,
        modifiable: false,
        products: products.span()
    };

    if inventory_type == inventory_types::WAREHOUSE_PRIMARY {
        config.mass = 1500000000000;
        config.volume = 75000000000;
        config.modifiable = true;
    } else if inventory_type == inventory_types::WAREHOUSE_SITE {
        config.mass = 1125899906842623;
        config.volume = 1125899906842623;
        config.modifiable = false;
        products.append(InventoryItemTrait::new(product_types::CEMENT, 400000));
        products.append(InventoryItemTrait::new(product_types::STEEL_BEAM, 350000));
        products.append(InventoryItemTrait::new(product_types::STEEL_SHEET, 200000));
        config.products = products.span();
    } else if inventory_type == inventory_types::PROPELLANT_TINY {
        config.mass = 200000000;
        config.volume = 2660000000;
        config.modifiable = true;
        products.append(InventoryItemTrait::new(product_types::HYDROGEN_PROPELLANT, MAX_AMOUNT));
        config.products = products.span();
    } else if inventory_type == inventory_types::PROPELLANT_SMALL {
        config.mass = 2000000000;
        config.volume = 26600000000;
        config.modifiable = true;
        products.append(InventoryItemTrait::new(product_types::HYDROGEN_PROPELLANT, MAX_AMOUNT));
        config.products = products.span();
    } else if inventory_type == inventory_types::PROPELLANT_MEDIUM {
        config.mass = 4000000000;
        config.volume = 53200000000;
        config.modifiable = true;
        products.append(InventoryItemTrait::new(product_types::HYDROGEN_PROPELLANT, MAX_AMOUNT));
        config.products = products.span();
    } else if inventory_type == inventory_types::PROPELLANT_LARGE {
        config.mass = 24000000000;
        config.volume = 319200000000;
        config.modifiable = true;
        products.append(InventoryItemTrait::new(product_types::HYDROGEN_PROPELLANT, MAX_AMOUNT));
        config.products = products.span();
    } else if inventory_type == inventory_types::CARGO_SMALL {
        config.mass = 50000000;
        config.volume = 125000000;
        config.modifiable = true;
    } else if inventory_type == inventory_types::CARGO_MEDIUM {
        config.mass = 2000000000;
        config.volume = 5000000000;
        config.modifiable = true;
    } else if inventory_type == inventory_types::CARGO_LARGE {
        config.mass = 12000000000;
        config.volume = 30000000000;
        config.modifiable = true;
    }

    let mut inventory_path: Array<felt252> = Default::default();
    inventory_path.append(inventory_type.into());
    components::set::<InventoryType>(inventory_path.span(), config);
}

fn building_type(building_type: u64) {
    let mut config = BuildingType {
        process_type: 0,
        site_slot: 0,
        site_type: 0
    };

    if building_type == building_types::WAREHOUSE {
        config.process_type = process_types::WAREHOUSE_CONSTRUCTION;
        config.site_slot = 1;
        config.site_type = inventory_types::WAREHOUSE_SITE;
    } else if building_type == building_types::EXTRACTOR {
        config.process_type = process_types::EXTRACTOR_CONSTRUCTION;
        config.site_slot = 1;
        config.site_type = inventory_types::EXTRACTOR_SITE;
    } else if building_type == building_types::MARKETPLACE {
        config.process_type = process_types::MARKETPLACE_CONSTRUCTION;
        config.site_slot = 1;
        config.site_type = inventory_types::MARKETPLACE_SITE;
    } else if building_type == building_types::SPACEPORT {
        config.process_type = process_types::SPACEPORT_CONSTRUCTION;
        config.site_slot = 1;
        config.site_type = inventory_types::SPACEPORT_SITE;
    } else if building_type == building_types::HABITAT {
        config.process_type = process_types::HABITAT_CONSTRUCTION;
        config.site_slot = 1;
        config.site_type = inventory_types::HABITAT_SITE;
    }

    let mut building_path: Array<felt252> = Default::default();
    building_path.append(building_type.into());
    components::set::<BuildingType>(building_path.span(), config);
}

fn dry_dock_type(dry_dock_type: u64) {
    let mut config = DryDockType { max_mass: 0, max_volume: 0 };

    if dry_dock_type == dry_dock_types::BASIC {
        config.max_mass = 1000000;
        config.max_volume = 1000000;
    }

    let mut dry_dock_path: Array<felt252> = Default::default();
    dry_dock_path.append(dry_dock_type.into());
    components::set::<DryDockType>(dry_dock_path.span(), config);
}

fn dock_type(dock_type: u64) {
    let mut config = DockType { cap: 0, delay: 0 };

    if dock_type == dock_types::BASIC {
        config.cap = 50;
        config.delay = 720;
    }

    let mut dock_path: Array<felt252> = Default::default();
    dock_path.append(dock_type.into());
    components::set::<DockType>(dock_path.span(), config);
}

fn exchange_type(exchange_type: u64) {
    let mut config = ExchangeType { allowed_products: 0 };

    if exchange_type == exchange_types::BASIC {
        config.allowed_products = 20;
    }

    let mut exchange_path: Array<felt252> = Default::default();
    exchange_path.append(exchange_type.into());
    components::set::<ExchangeType>(exchange_path.span(), config);
}

fn station_type(station_type: u64) {
    let mut config = StationType { cap: 0, recruitment: false, efficiency: f64::FixedTrait::ONE() };

    if station_type == station_types::STANDARD_QUARTERS {
        config.cap = 5;
        config.recruitment = false;
        config.efficiency = f64::FixedTrait::ONE();
    } else if station_type == station_types::EXPANDED_QUARTERS {
        config.cap = 15;
        config.recruitment = false;
        config.efficiency = f64::FixedTrait::ONE();
    } else if station_type == station_types::HABITAT {
        config.cap = 1000;
        config.recruitment = true;
        config.efficiency = f64::FixedTrait::new(5153960755, false); // 1.2 efficiency
    }

    let mut station_path: Array<felt252> = Default::default();
    station_path.append(station_type.into());
    components::set::<StationType>(station_path.span(), config);
}

fn ship_type(ship_type: u64) {
    let mut config = ShipType {
        cargo_inventory_type: 0,
        cargo_slot: 0,
        docking: false,
        exhaust_velocity: f128::FixedTrait::new(0, false),
        hull_mass: 0,
        landing: false,
        process_type: 0,
        propellant_emergency_divisor: 0,
        propellant_inventory_type: 0,
        propellant_slot: 0,
        propellant_type: 0,
        station_type: 0
    };

    if ship_type == ship_types::ESCAPE_MODULE {
        config.propellant_slot = 1;
        config.propellant_inventory_type = inventory_types::PROPELLANT_TINY;
        config.propellant_type = product_types::HYDROGEN_PROPELLANT;
        config.propellant_emergency_divisor = 1;
        config.exhaust_velocity = f128::FixedTrait::new_unscaled(30, false);
        config.hull_mass = 5000000;
    } else if ship_type == ship_types::LIGHT_TRANSPORT {
        config.landing = true;
        config.docking = true;
        config.propellant_slot = 1;
        config.propellant_inventory_type = inventory_types::PROPELLANT_MEDIUM;
        config.propellant_type = product_types::HYDROGEN_PROPELLANT;
        config.propellant_emergency_divisor = 10;
        config.cargo_slot = 2;
        config.cargo_inventory_type = inventory_types::CARGO_MEDIUM;
        config.exhaust_velocity = f128::FixedTrait::new_unscaled(30, false);
        config.hull_mass = 185525000;
        config.station_type = station_types::STANDARD_QUARTERS;
        config.process_type = process_types::LIGHT_TRANSPORT_INTEGRATION;
    } else if ship_type == ship_types::HEAVY_TRANSPORT {
        config.docking = true;
        config.propellant_slot = 1;
        config.propellant_inventory_type = inventory_types::PROPELLANT_LARGE;
        config.propellant_type = product_types::HYDROGEN_PROPELLANT;
        config.propellant_emergency_divisor = 10;
        config.cargo_slot = 2;
        config.cargo_inventory_type = inventory_types::CARGO_LARGE;
        config.exhaust_velocity = f128::FixedTrait::new_unscaled(30, false);
        config.hull_mass = 969525000;
        config.station_type = station_types::STANDARD_QUARTERS;
        config.process_type = process_types::HEAVY_TRANSPORT_INTEGRATION;
    } else if ship_type == ship_types::SHUTTLE {
        config.docking = true;
        config.propellant_slot = 1;
        config.propellant_inventory_type = inventory_types::PROPELLANT_SMALL;
        config.propellant_type = product_types::HYDROGEN_PROPELLANT;
        config.propellant_emergency_divisor = 10;
        config.cargo_slot = 2;
        config.cargo_inventory_type = inventory_types::CARGO_SMALL;
        config.exhaust_velocity = f128::FixedTrait::new_unscaled(30, false);
        config.hull_mass = 100755000;
        config.station_type = station_types::EXPANDED_QUARTERS;
        config.process_type = process_types::SHUTTLE_INTEGRATION;
    }

    let mut ship_path: Array<felt252> = Default::default();
    ship_path.append(ship_type.into());
    components::set::<ShipType>(ship_path.span(), config);
}

fn ship_variant_type(ship_variant_type: u64) {
    let mut config = ShipVariantType {
        ship_type: 0,
        exhaust_velocity_modifier: f64::FixedTrait::ZERO()
    };

    if ship_variant_type == ship_variant_types::STANDARD {
        config.ship_type = 1;
        config.exhaust_velocity_modifier = f64::FixedTrait::ZERO();
    } else if ship_variant_type == ship_variant_types::COBALT_PIONEER {
        config.ship_type = 2;
        config.exhaust_velocity_modifier = f64::FixedTrait::new(429496730, false); // 10% bonus
    }

    let mut variant_path: Array<felt252> = Default::default();
    variant_path.append(ship_variant_type.into());
    components::set::<ShipVariantType>(variant_path.span(), config);
}

fn constants() {
    config::set('CONSTRUCTION_GRACE_PERIOD', 86400 * 2); // - grace period in IRL seconds after construction planned
    config::set('CORE_SAMPLING_TIME', 86400); // - in-game seconds to sample a deposit
    config::set('CREW_SCHEDULE_BUFFER', 86400); // - buffer in IRL seconds for crew scheduling
    config::set('CREWMATE_FOOD_PER_YEAR', 1000); // - kg / in-game year
    config::set('DECONSTRUCTION_PENALTY', 429496729); // - fraction of building materials lost at deconstruction (f64)
    config::set('EMERGENCY_PROP_GEN_TIME', 10368000); // - in-game seconds to generate emergency propellant up to 10%
    config::set('HOPPER_SPEED', 10737418240); // - hopper speed in km / in-game hr (f64)
    config::set('INSTANT_TRANSPORT_DISTANCE', 21474836480); // - instant transfer distance in km (f64)
    config::set('MAX_POLICY_DURATION', 31536000); // - maximum policy duration in IRL seconds
    config::set('MAX_PROCESS_TIME', 63072000); // - longest a process can run in in-game seconds
    config::set('SCANNING_TIME', 86400); // - time for asteroid scans in IRL seconds
    config::set('TIME_ACCELERATION', 24); // - time acceleration factor
}
