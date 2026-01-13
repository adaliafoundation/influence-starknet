// Helpers do NO validation and should only be used in systems after validations are complete
use array::{ArrayTrait, SpanTrait};
use option::OptionTrait;
use starknet::ContractAddress;
use traits::{Into, TryInto};

use influence::{components, contracts};
use influence::components::{Crew, CrewTrait, Crewmate, CrewmateTrait, Location, LocationTrait, Name, NameTrait,
    Unique, UniqueTrait,
    inventory_type::types as inventory_types,
    inventory::{statuses as inventory_statuses, Inventory, InventoryTrait},
    ship::{statuses as ship_statuses, Ship, ShipTrait},
    ship_type::{types as ship_types, ShipTypeTrait}
};
use influence::config::{entities, errors};
use influence::contracts::crew::{ICrewDispatcher, ICrewDispatcherTrait};
use influence::types::{Entity, EntityTrait, String, StringTrait};

fn create_crew(station: Entity, caller: ContractAddress) -> (Entity, Crew) {
    // Mint crew NFT
    let id = ICrewDispatcher { contract_address: contracts::get('Crew') }.mint_with_auto_id(caller);

    // Create entity
    let crew = EntityTrait::new(entities::CREW, id.try_into().unwrap());

    // Crew component
    let crew_data = CrewTrait::new(caller);
    components::set::<Crew>(crew.path(), crew_data);

    // Attach station as location
    components::set::<Location>(crew.path(), LocationTrait::new(station));

    // Create escape module ship and attach
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

    // Create propellant inventory, lock and attach
    let mut path: Array<felt252> = Default::default();
    path.append(crew.into());
    path.append(ShipTypeTrait::by_type(ship_types::ESCAPE_MODULE).propellant_slot.into());
    let mut inventory_data = InventoryTrait::new(inventory_types::PROPELLANT_TINY);
    inventory_data.disable();
    components::set::<Inventory>(path.span(), inventory_data);

    return (crew, crew_data);
}

fn change_name(entity: Entity, name: String) {
    // Check for validity
    let config = NameTrait::config(entity.label);
    assert(
        name.is_empty() || name.is_valid(config.min, config.max, config.alpha, config.num, config.sym),
        errors::NAME_INVALID
    );

    // Check for uniqueness of the new name
    let mut path: Array<felt252> = Default::default();
    let mut old_path: Array<felt252> = Default::default();
    path.append('Name');
    old_path.append('Name');
    path.append(entity.label.into());
    old_path.append(entity.label.into());

    // For buildings, scope their uniqueness to the asteroid they're on
    if entity.label == entities::BUILDING {
        let (asteroid, _) = entity.to_position();
        path.append(asteroid.into());
        old_path.append(asteroid.into());
    }

    // If name currently exists, and rewrites are allowed, remove uniqueness
    if components::get::<Name>(entity.path()).is_some() {
        assert(config.rewrite, errors::NAME_ALREADY_SET);
        let name_data = components::get::<Name>(entity.path()).unwrap();
        old_path.append(name_data.name.value.try_into().unwrap());
        components::set::<Unique>(old_path.span(), Unique { unique: 0 });
    }

    path.append(name.value.try_into().unwrap());

    // Set name and uniqueness
    if (!name.is_empty()) {
        // Only set uniqueness if the name is not empty
        assert(components::get::<Unique>(path.span()).is_none(), errors::NOT_UNIQUE);
        components::set::<Unique>(path.span(), UniqueTrait::new());
    }

    components::set::<Name>(entity.path(), NameTrait::new(name));
}
