#[starknet::contract]
mod AssembleShipFinish {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use starknet::contract_address::ContractAddress;
    use traits::{Into, TryInto};

    use cubit::f128::{Fixed, FixedTrait, ONE_u128};

    use influence::components;
    use influence::common::{crew::CrewDetailsTrait, inventory, position};
    use influence::components::{Building, BuildingTrait, Celestial, Crew, CrewTrait, Dock, DockTrait, Inventory,
        InventoryTrait, Location, LocationTrait, Station, StationTrait, Unique, UniqueTrait,
        modifier_type::types as modifier_types,
        dry_dock::{statuses as dry_dock_statuses, DryDock, DryDockTrait},
        ship::{statuses as ship_statuses, Ship, ShipTrait},
        ship_type::{types as ship_types, ShipTypeTrait}
    };
    use influence::config::{entities, errors, permissions};
    use influence::types::{Context, Entity, EntityTrait, InventoryItem, InventoryItemTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct ShipAssemblyFinished {
        ship: Entity,
        dry_dock: Entity,
        dry_dock_slot: u64,
        destination: Entity,
        finish_time: u64,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        ShipAssemblyFinished: ShipAssemblyFinished
    }

    #[external(v0)]
    fn run(
        ref self: ContractState,
        dry_dock: Entity,
        dry_dock_slot: u64,
        destination: Entity,
        caller_crew: Entity,
        context: Context
    ) {
        // Check that crew is delegated
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_delegated_to(context.caller);

        // Get ship configuration
        let mut dry_dock_path: Array<felt252> = Default::default();
        dry_dock_path.append(dry_dock.into());
        dry_dock_path.append(dry_dock_slot.into());
        let mut dry_dock_data = components::get::<DryDock>(dry_dock_path.span()).expect(errors::DRY_DOCK_NOT_FOUND);
        let ship = dry_dock_data.output_ship;
        let mut ship_data = components::get::<Ship>(ship.path()).expect(errors::SHIP_NOT_FOUND);
        let ship_config = ShipTypeTrait::by_type(ship_data.ship_type);

        // Ensure caller is either the owner of the ship or has permissions
        assert(
            caller_crew.controls(ship) || caller_crew.can(dry_dock, permissions::ASSEMBLE_SHIP),
            errors::ACCESS_DENIED
        );

        // Check the location of the destination
        let (dest_ast, dest_lot) = destination.to_position();
        let (dry_dock_ast, dry_dock_lot) = dry_dock.to_position();
        assert(dest_ast == dry_dock_ast, errors::DIFFERENT_ASTEROIDS);
        assert(dest_lot != 0, errors::IN_ORBIT);

        // Check valid destinations
        if destination.label == entities::LOT {
            assert(ship_config.landing, errors::LANDING_GEAR_REQUIRED);
            let mut unique_path: Array<felt252> = Default::default();
            unique_path.append('LotUse');
            unique_path.append(destination.into());
            assert(components::get::<Unique>(unique_path.span()).is_none(), errors::LOT_IN_USE);

            // Move ship to lot
            components::set::<Location>(ship.path(), LocationTrait::new(destination));
            components::set::<Unique>(unique_path.span(), UniqueTrait::new());
        } else {
            match components::get::<Dock>(destination.path()) {
                Option::Some(mut dock_data) => {
                    // Make sure building is operating
                    components::get::<Building>(destination.path()).expect(errors::BUILDING_NOT_FOUND)
                        .assert_operational();

                    let crew_can_dock = caller_crew.can(destination, permissions::DOCK_SHIP);
                    let ship_can_dock = ship.can(destination, permissions::DOCK_SHIP);
                    assert(crew_can_dock || ship_can_dock, errors::ACCESS_DENIED);

                    // Move ship to dock
                    components::set::<Location>(ship.path(), LocationTrait::new(destination));
                    dock_data.docked_ships += 1;
                    components::set::<Dock>(destination.path(), dock_data);
                },
                Option::None(_) => {
                    assert(false, errors::INCORRECT_LOCATION);
                }
            };
        }

        // Calculate time to move the ship
        let hopper_eff = crew_details.bonus(modifier_types::HOPPER_TRANSPORT_TIME, context.now);
        let dist_eff = crew_details.bonus(modifier_types::FREE_TRANSPORT_DISTANCE, context.now);
        let ast = components::get::<Celestial>(EntityTrait::new(entities::ASTEROID, dest_ast).path())
            .expect(errors::CELESTIAL_NOT_FOUND);

        let dry_dock_to_dest = position::hopper_travel_time(dry_dock_lot, dest_lot, ast.radius, hopper_eff, dist_eff);
        let finish_time = context.now + dry_dock_to_dest;

        // Update the ship
        ship_data.status = ship_statuses::AVAILABLE;
        ship_data.ready_at = finish_time;
        components::set::<Ship>(ship.path(), ship_data);

        // Add storage and station to ship
        let mut prop_path: Array<felt252> = Default::default();
        prop_path.append(ship.into());
        prop_path.append(ship_config.propellant_slot.into());

        let mut cargo_path: Array<felt252> = Default::default();
        cargo_path.append(ship.into());
        cargo_path.append(ship_config.cargo_slot.into());

        if ship_config.propellant_inventory_type != 0 {
            components::set::<Inventory>(prop_path.span(), InventoryTrait::new(ship_config.propellant_inventory_type));
        }

        if ship_config.cargo_inventory_type != 0 {
            components::set::<Inventory>(cargo_path.span(), InventoryTrait::new(ship_config.cargo_inventory_type));
        }

        if ship_config.station_type != 0 {
            components::set::<Station>(ship.path(), StationTrait::new(ship_config.station_type));
        }

        // Update the dry dock
        dry_dock_data.status = dry_dock_statuses::IDLE;
        dry_dock_data.output_ship = EntityTrait::new(0, 0);
        dry_dock_data.finish_time = 0;
        components::set::<DryDock>(dry_dock_path.span(), dry_dock_data);

        self.emit(ShipAssemblyFinished {
            ship: ship,
            dry_dock: dry_dock,
            dry_dock_slot: dry_dock_slot,
            destination: destination,
            finish_time: finish_time,
            caller_crew: caller_crew,
            caller: context.caller,
        });
    }
}

// TODO: tests