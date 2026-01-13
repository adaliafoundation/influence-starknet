
#[starknet::contract]
mod UndockShip {
    use array::ArrayTrait;
    use cmp::max;
    use option::OptionTrait;
    use starknet::ContractAddress;
    use traits::{Into, TryInto};

    use cubit::f64::FixedTrait;

    use influence::{components, config};
    use influence::common::{inventory, position, propulsion, crew::CrewDetailsTrait};
    use influence::config::{entities, errors, permissions};
    use influence::components::{Celestial, CelestialTrait, Control, ControlTrait, Crew, CrewTrait, Dock, DockTrait,
        Inventory, InventoryTrait, Location, LocationTrait, Ship, ShipTrait, ShipTypeTrait, ShipVariantTypeTrait, Unique,
        modifier_type::types as modifier_types,
        product_type::types as product_types
    };
    use influence::types::{Context, Entity, EntityTrait, InventoryItem, InventoryItemTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct ShipUndocked {
        ship: Entity,
        dock: Entity,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        ShipUndocked: ShipUndocked
    }

    // Handles:
    // - players to undock their ship from a dock or lot on an asteroid
    // - the controller of the dock or the lot to evict another player's ship
    #[external(v0)]
    fn run(ref self: ContractState, ship: Entity, powered: bool, caller_crew: Entity, context: Context) {
        let ship_crew = ship.controller();
        let mut ship_crew_details = CrewDetailsTrait::new(ship_crew);
        let mut ship_crew_data = ship_crew_details.component;

        // Get ship info and location (dock or lot)
        let mut ship_data = components::get::<Ship>(ship.path()).expect(errors::SHIP_NOT_FOUND);
        let ship_location = components::get::<Location>(ship.path()).expect(errors::LOCATION_NOT_FOUND).location;
        let (asteroid_id, _) = ship.to_position();
        let asteroid = EntityTrait::new(entities::ASTEROID, asteroid_id);

        // Get ship inventories
        let ship_config = ShipTypeTrait::by_type(ship_data.ship_type);
        let mut prop_path: Array<felt252> = Default::default();
        prop_path.append(ship.into());
        prop_path.append(ship_config.propellant_slot.into());
        let mut prop_inventory = components::get::<Inventory>(prop_path.span()).expect(errors::INVENTORY_NOT_FOUND);

        let mut cargo_path: Array<felt252> = Default::default();
        cargo_path.append(ship.into());
        cargo_path.append(ship_config.cargo_slot.into());
        let mut cargo_inventory = components::get::<Inventory>(cargo_path.span()).expect(errors::INVENTORY_NOT_FOUND);

        if ship_crew == caller_crew {
            // If piloting crew is undocking
            ship_crew_details.assert_all_ready(context.caller, context.now);
            ship_data.assert_ready(context.now);

            // Make sure crew is piloting the ship
            assert(ship_crew_details.asteroid_id() == asteroid_id, errors::DIFFERENT_ASTEROIDS);

            // Check that the ship has no inventory reservations
            assert(prop_inventory.reserved_mass + prop_inventory.reserved_volume == 0, errors::DELIVERY_IN_PROGRESS);
            assert(cargo_inventory.reserved_mass + cargo_inventory.reserved_volume == 0, errors::DELIVERY_IN_PROGRESS);
        } else {
            // If dock or lot controller is evicting
            let mut crew_details = CrewDetailsTrait::new(caller_crew);
            crew_details.assert_delegated_to(context.caller);
            crew_details.assert_manned();
            crew_details.assert_ready(context.now);

            // Make sure undocking isn't powered
            assert(!powered, 'eviction must be unpowered');

            // Make sure the evicting crew is on the same asteroid
            assert(crew_details.asteroid_id() == asteroid_id, errors::DIFFERENT_ASTEROIDS);

            // Check that ship controller doesn't have permission to be there
            if ship_location.label == entities::BUILDING {
                assert(
                    !ship_crew.can(ship_location, permissions::DOCK_SHIP) &&
                    !ship.can(ship_location, permissions::DOCK_SHIP),
                    errors::ACCESS_DENIED
                );
            } else if ship_location.label == entities::LOT {
                assert(!ship_crew.can(ship_location, permissions::USE_LOT), errors::ACCESS_DENIED);
            }
        }

        let mut ground_time = 0;

        if ship_location.label == entities::LOT {
            // If undocking from a lot
            let mut unique_path: Array<felt252> = Default::default();
            unique_path.append('LotUse');
            unique_path.append(ship_location.into());

            // Update lot use
            components::set::<Unique>(unique_path.span(), Unique { unique: 0 });
        } else if ship_location.label == entities::BUILDING {
            // If undocking from a spaceport
            let mut dock_data = components::get::<Dock>(ship_location.path()).expect(errors::DOCK_NOT_FOUND);

            // Queue ground operations
            let var_time = (dock_data.docked_ships * 720) / config::get('TIME_ACCELERATION').try_into().unwrap();
            ground_time = max(context.now, dock_data.ready_at) - context.now + var_time;

            dock_data.docked_ships -= 1;
            dock_data.ready_at = context.now + ground_time;
            components::set::<Dock>(ship_location.path(), dock_data);
        } else {
            assert(false, errors::INCORRECT_ENTITY_TYPE);
        }

        // Calculate time required to dock (get asteroid from ship position)
        let celestial_data = components::get::<Celestial>(asteroid.path()).unwrap();
        let mut travel_time = 0;

        if powered {
            // Check crew is piloting the ship
            let (crew_ship, _) = ship_crew_details.ship();
            assert(crew_ship == ship, errors::SHIP_UNMANNED);

            // Calculate escape velocity for specific asteroid
            let escape_v = propulsion::escape_velocity(celestial_data.mass, celestial_data.radius.into());

            // Get inventories
            let mut prop_path: Array<felt252> = Default::default();
            prop_path.append(ship.into());
            prop_path.append(ship_config.propellant_slot.into());
            let mut prop_inventory = components::get::<Inventory>(prop_path.span()).unwrap();

            let mut cargo_path: Array<felt252> = Default::default();
            cargo_path.append(ship.into());
            cargo_path.append(ship_config.cargo_slot.into());
            let cargo_inventory = components::get::<Inventory>(cargo_path.span()).unwrap();

            // Calculate propellant required from total ship mass
            let ship_bonus = ShipVariantTypeTrait::by_type(ship_data.variant).exhaust_velocity_modifier + FixedTrait::ONE();
            let efficiency = ship_crew_details.bonus(modifier_types::PROPELLANT_EXHAUST_VELOCITY, context.now) * ship_bonus;

            let req_propellant = propulsion::propellant_required(
                ship_config.hull_mass + prop_inventory.mass + cargo_inventory.mass,
                ship_config.exhaust_velocity,
                escape_v,
                efficiency.into()
            );

            // Remove required propellant from propellant inventory
            let mut prop_to_remove: Array<InventoryItem> = Default::default();
            prop_to_remove.append(InventoryItemTrait::new(product_types::HYDROGEN_PROPELLANT, req_propellant.into()));
            inventory::remove(ref prop_inventory, prop_to_remove.span());
            components::set::<Inventory>(prop_path.span(), prop_inventory);
        } else {
            let efficiency = ship_crew_details.bonus(modifier_types::HOPPER_TRANSPORT_TIME, context.now);
            let dist_eff = ship_crew_details.bonus(modifier_types::FREE_TRANSPORT_DISTANCE, context.now);
            travel_time = position::hopper_travel_time(
                ship_crew_details.lot_id(), 0, celestial_data.radius, efficiency, dist_eff
            );
        }

        // Update location of the ship and ready times
        components::set::<Location>(ship.path(), LocationTrait::new(asteroid));
        // Including busy until time here would be unfair to crew having their ship ejected
        ship_data.ready_at = context.now + ground_time + travel_time;
        components::set::<Ship>(ship.path(), ship_data);

        // Only update the crew ready time if the crew is piloting the ship
        if ship_crew_details.location() == ship {
            ship_crew_data.add_busy(context.now, ground_time + travel_time);
            components::set::<Crew>(ship_crew.path(), ship_crew_data);
        }

        self.emit(ShipUndocked {
            ship: ship,
            dock: ship_location,
            caller_crew: caller_crew,
            caller: context.caller
        });
    }
}
