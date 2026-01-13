#[starknet::contract]
mod DockShip {
    use array::ArrayTrait;
    use cmp::{max, min};
    use option::OptionTrait;
    use starknet::ContractAddress;
    use traits::{Into, TryInto};

    use cubit::f64::FixedTrait;

    use influence::{components, config};
    use influence::common::{inventory, position, propulsion, crew::CrewDetailsTrait};
    use influence::config::{entities, errors, permissions};
    use influence::components::{Building, BuildingTrait, Celestial, CelestialTrait, Control, ControlTrait, Crew,
        CrewTrait, Dock, DockTrait, Inventory, InventoryTrait, Location, LocationTrait, Ship, ShipTrait, ShipTypeTrait,
        ShipVariantTypeTrait, Unique,
        dock_type::{types as dock_types, DockTypeTrait},
        modifier_type::types as modifier_types,
        product_type::types as product_types
    };
    use influence::types::{Context, Entity, EntityTrait, InventoryItem, InventoryItemTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct ShipDocked {
        ship: Entity,
        dock: Entity,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        ShipDocked: ShipDocked
    }

    #[external(v0)]
    fn run(ref self: ContractState, target: Entity, powered: bool, caller_crew: Entity, context: Context) {
        // Check that crew is delegated and ready
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_all_ready(context.caller, context.now);
        let mut crew_data = crew_details.component;

        // Ensure the crew controls / is piloting the ship
        let (ship, mut ship_data) = crew_details.ship();
        ship_data.assert_ready(context.now);
        caller_crew.assert_controls(ship);

        // Ensure the ship is in orbit around the same asteroid the dock is on
        let (ship_ast, ship_lot) = ship.to_position();
        let (target_ast, target_lot) = target.to_position();
        assert(ship_ast == target_ast, errors::DIFFERENT_ASTEROIDS);
        assert(ship_lot == 0, errors::NOT_IN_ORBIT);

        let ship_config = ShipTypeTrait::by_type(ship_data.ship_type);
        let mut ground_time = 0;

        if target.label == entities::LOT {
            // On a lot, ensure the ship can land, and that the lot is empty
            assert(ship_config.landing, errors::SHIP_CANNOT_LAND);
            let mut unique_path: Array<felt252> = Default::default();
            unique_path.append('LotUse');
            unique_path.append(target.into());
            assert(components::get::<Unique>(unique_path.span()).is_none(), errors::LOT_IN_USE);

            // Update lot use
            components::set::<Unique>(unique_path.span(), Unique { unique: ship.into() });
        } else if target.label == entities::BUILDING {
            // At a building, ensure the ship can dock, and permissions are present
            components::get::<Building>(target.path()).expect(errors::BUILDING_NOT_FOUND).assert_operational();
            assert(ship_config.docking, errors::SHIP_CANNOT_DOCK);
            assert(
                caller_crew.can(target, permissions::DOCK_SHIP) || ship.can(target, permissions::DOCK_SHIP),
                errors::ACCESS_DENIED
            );

            let mut dock_data = components::get::<Dock>(target.path()).expect(errors::DOCK_NOT_FOUND);
            let dock_config = DockTypeTrait::by_type(dock_data.dock_type);
            let eff_docked_ships = dock_data.docked_ships - min(dock_data.docked_ships, dock_config.cap / 2);
            let var_time = (eff_docked_ships * 720) / config::get('TIME_ACCELERATION').try_into().unwrap();
            ground_time = max(context.now, dock_data.ready_at) - context.now + var_time;

            // Update dock data
            dock_data.docked_ships += 1;
            assert(dock_data.docked_ships <= dock_config.cap, 'dock is full');
            components::set::<Dock>(target.path(), dock_data);
        } else {
            assert(false, errors::INCORRECT_ENTITY_TYPE);
        }

        // Check that the asteroid has been short-range scanned before landing
        let asteroid = EntityTrait::new(entities::ASTEROID, target_ast);
        let celestial_data = components::get::<Celestial>(asteroid.path()).expect(errors::CELESTIAL_NOT_FOUND);
        celestial_data.assert_resource_scanned();

        // Calculate time required to dock
        let mut travel_time = 0;

        if powered {
            let mut total_mass = ship_config.hull_mass;

            let mut prop_path: Array<felt252> = Default::default();
            prop_path.append(ship.into());
            prop_path.append(ship_config.propellant_slot.into());
            let mut prop_inventory = components::get::<Inventory>(prop_path.span()).expect(errors::INVENTORY_NOT_FOUND);
            total_mass += prop_inventory.mass;

            let mut cargo_path: Array<felt252> = Default::default();
            cargo_path.append(ship.into());
            cargo_path.append(ship_config.cargo_slot.into());
            match components::get::<Inventory>(cargo_path.span()) {
                Option::Some(cargo_data) => {
                    total_mass += cargo_data.mass;
                },
                Option::None(_) => ()
            }

            // Calculate propellant required from total ship mass
            let ship_bonus = ShipVariantTypeTrait::by_type(ship_data.variant).exhaust_velocity_modifier + FixedTrait::ONE();
            let efficiency = crew_details.bonus(modifier_types::PROPELLANT_EXHAUST_VELOCITY, context.now) * ship_bonus;

            let escape_v = propulsion::escape_velocity(celestial_data.mass, celestial_data.radius.into());
            let req_propellant = propulsion::propellant_required(
                total_mass, ship_config.exhaust_velocity, escape_v, efficiency.into()
            );

            // Remove required propellant from propellant inventory
            let mut prop_to_remove: Array<InventoryItem> = Default::default();
            prop_to_remove.append(InventoryItemTrait::new(product_types::HYDROGEN_PROPELLANT, req_propellant.into()));
            inventory::remove(ref prop_inventory, prop_to_remove.span());
            components::set::<Inventory>(prop_path.span(), prop_inventory);
        } else {
            let efficiency = crew_details.bonus(modifier_types::HOPPER_TRANSPORT_TIME, context.now);
            let dist_eff = crew_details.bonus(modifier_types::FREE_TRANSPORT_DISTANCE, context.now);
            travel_time = position::hopper_travel_time(0, target_lot, celestial_data.radius, efficiency, dist_eff);
        }

        // Update location of the ship and ready times
        components::set::<Location>(ship.path(), LocationTrait::new(target));
        ship_data.ready_at = crew_data.busy_until(context.now) + travel_time + ground_time;
        components::set::<Ship>(ship.path(), ship_data);
        crew_data.add_busy(context.now, travel_time + ground_time);
        components::set::<Crew>(caller_crew.path(), crew_data);

        self.emit(ShipDocked {
            ship: ship,
            dock: target,
            caller_crew: caller_crew,
            caller: context.caller
        });
    }
}
