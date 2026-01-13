// - Schedulable

#[starknet::contract]
mod AssembleShipStart {
    use array::{ArrayTrait, SpanTrait};
    use cmp::max;
    use option::OptionTrait;
    use starknet::contract_address::ContractAddress;
    use traits::{Into, TryInto};

    use cubit::f64::FixedTrait;

    use influence::{components, config, contracts};
    use influence::common::{crew::CrewDetailsTrait, inventory, math::RoundedDivTrait, position};
    use influence::components::{Building, BuildingTrait, Celestial, Control, ControlTrait, Crew, CrewTrait,
        Inventory, InventoryTrait, Location, LocationTrait, ProcessTypeTrait,
        modifier_type::types as modifier_types,
        dry_dock::{statuses as dry_dock_statuses, DryDock, DryDockTrait},
        ship::{variants as ship_variants, Ship, ShipTrait},
        ship_type::{types as ship_types, ShipTypeTrait}
    };
    use influence::config::{actions, entities, errors, permissions};
    use influence::contracts::ship::{IShipDispatcher, IShipDispatcherTrait};
    use influence::systems::production;
    use influence::types::{Context, Entity, EntityTrait, InventoryItem, InventoryItemTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct ShipAssemblyStarted {
        ship: Entity,
        dry_dock: Entity,
        dry_dock_slot: u64,
        ship_type: u64,
        finish_time: u64,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[derive(Copy, Drop, starknet::Event)]
    struct ShipAssemblyStartedV1 {
        ship: Entity,
        ship_type: u64,
        dry_dock: Entity,
        dry_dock_slot: u64,
        origin: Entity,
        origin_slot: u64,
        finish_time: u64,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        ShipAssemblyStarted: ShipAssemblyStarted,
        ShipAssemblyStartedV1: ShipAssemblyStartedV1
    }

    #[external(v0)]
    fn run(
        ref self: ContractState,
        dry_dock: Entity,
        dry_dock_slot: u64,
        ship_type: u64,
        origin: Entity,
        origin_slot: u64,
        caller_crew: Entity,
        context: Context
    ) {
        // Check that crew is delegated, and ready
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_all_ready_within(context.caller, context.now);
        let mut crew_data = crew_details.component;

        // Check origin is operational
        if origin.label == entities::BUILDING {
            components::get::<Building>(origin.path()).expect(errors::BUILDING_NOT_FOUND).assert_operational();
        } else if origin.label == entities::SHIP {
            components::get::<Ship>(origin.path()).expect(errors::SHIP_NOT_FOUND).assert_stationary();
            let location = components::get::<Location>(origin.path()).expect(errors::LOCATION_NOT_FOUND);

            match components::get::<Building>(location.location.path()) {
                Option::Some(building_data) => building_data.assert_operational(),
                Option::None(_) => ()
            };
        }

        caller_crew.assert_can(origin, permissions::REMOVE_PRODUCTS);

        // Check the dry dock is available
        let mut dry_dock_path: Array<felt252> = Default::default();
        dry_dock_path.append(dry_dock.into());
        dry_dock_path.append(dry_dock_slot.into());
        let mut dry_dock_data = components::get::<DryDock>(dry_dock_path.span()).expect(errors::DRY_DOCK_NOT_FOUND);
        components::get::<Building>(dry_dock.path()).expect(errors::BUILDING_NOT_FOUND).assert_operational();
        dry_dock_data.assert_ready(context.now);

        // Check that the dry dock is on the same asteroid as the origin
        let (dry_dock_ast, dry_dock_lot) = dry_dock.to_position();
        let (origin_ast, origin_lot) = origin.to_position();
        assert(dry_dock_ast == origin_ast, errors::DIFFERENT_ASTEROIDS);
        assert(origin_lot != 0, errors::IN_ORBIT);

        // Check that crew is on surface of asteroid
        let (crew_ast, crew_lot) = caller_crew.to_position();
        assert(crew_ast == dry_dock_ast, errors::DIFFERENT_ASTEROIDS);
        assert(crew_lot != 0, errors::IN_ORBIT);

        // Retrieve process settings
        let process_config = ProcessTypeTrait::by_type(ShipTypeTrait::by_type(ship_type).process_type);

        // Calculate the hopper transport times
        let hopper_eff = crew_details.bonus(modifier_types::HOPPER_TRANSPORT_TIME, context.now);
        let dist_eff = crew_details.bonus(modifier_types::FREE_TRANSPORT_DISTANCE, context.now);
        let asteroid = EntityTrait::new(entities::ASTEROID, crew_ast);
        let celestial_data = components::get::<Celestial>(asteroid.path()).expect(errors::CELESTIAL_NOT_FOUND);
        let crew_to_lot = position::hopper_travel_time(
            crew_lot, dry_dock_lot, celestial_data.radius, hopper_eff, dist_eff
        );

        let origin_to_lot = position::hopper_travel_time(
            origin_lot, dry_dock_lot, celestial_data.radius, hopper_eff, dist_eff
        );

        // Calculate the finish time
        let integration_eff = crew_details.bonus(modifier_types::SHIP_INTEGRATION_TIME, context.now);
        let (setup_time, variable_time) = production::helpers::time(
            process_config.setup_time,
            process_config.recipe_time,
            process_config.batched,
            FixedTrait::ONE(),
            integration_eff
        );

        let positioning_time = max(crew_to_lot, origin_to_lot);
        let finish_time = crew_data.busy_until(context.now) + positioning_time + setup_time + variable_time;

        // Check that the crew has the necessary permissions given the processing time
        caller_crew.assert_can_until(dry_dock, permissions::ASSEMBLE_SHIP, finish_time);

        // Update the origin inventory
        let mut origin_path: Array<felt252> = Default::default();
        origin_path.append(origin.into());
        origin_path.append(origin_slot.into());
        let mut inv_data = components::get::<Inventory>(origin_path.span()).expect(errors::INVENTORY_NOT_FOUND);
        inventory::remove(ref inv_data, process_config.inputs);
        components::set::<Inventory>(origin_path.span(), inv_data);

        // Mint ship
        let id = IShipDispatcher { contract_address: contracts::get('Ship') }.mint_with_auto_id(context.caller);
        let ship = EntityTrait::new(entities::SHIP, id.try_into().unwrap());
        components::set::<Ship>(ship.path(), ShipTrait::new(ship_type, ship_variants::STANDARD));
        components::set::<Control>(ship.path(), ControlTrait::new(caller_crew));
        components::set::<Location>(ship.path(), LocationTrait::new(dry_dock));

        // TODO: ensure that the dry dock has the capacity for the type of ship

        // Update the dry dock
        dry_dock_data.status = dry_dock_statuses::RUNNING;
        dry_dock_data.output_ship = ship;
        dry_dock_data.finish_time = finish_time;
        components::set::<DryDock>(dry_dock_path.span(), dry_dock_data);

        // Update the crew
        let crew_time = (setup_time + variable_time).div_ceil(8);
        crew_data.add_busy(context.now, positioning_time + crew_time + crew_to_lot);
        crew_data.set_action(actions::ASSEMBLE_SHIP_STARTED, dry_dock, crew_time, context.now);
        components::set::<Crew>(caller_crew.path(), crew_data);

        let (station_ship, mut station_ship_data) = crew_details.ship();
        if caller_crew != station_ship {
            station_ship_data.extend_ready(crew_data.ready_at);
            components::set::<Ship>(station_ship.path(), station_ship_data);
        }

        self.emit(ShipAssemblyStartedV1 {
            ship: ship,
            ship_type: ship_type,
            dry_dock: dry_dock,
            dry_dock_slot: dry_dock_slot,
            origin: origin,
            origin_slot: origin_slot,
            finish_time: finish_time,
            caller_crew: caller_crew,
            caller: context.caller,
        });
    }
}

// TODO: tests