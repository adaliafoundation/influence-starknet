#[starknet::contract]
mod ProcessProductsStart {
    use array::{ArrayTrait, SpanTrait};
    use cmp::max;
    use option::OptionTrait;
    use starknet::contract_address::ContractAddress;
    use traits::{Into, TryInto};

    use cubit::f64::{Fixed, FixedTrait, ONE};

    use influence::{components, config};
    use influence::common::{inventory, position, crew::CrewDetailsTrait, math::RoundedDivTrait};
    use influence::components::{BuildingTypeTrait, Celestial, Crew, CrewTrait, Inventory, InventoryTrait,
        Location, LocationTrait, ProcessTypeTrait, Ship, ShipTrait,
        building::{statuses as building_statuses, Building, BuildingTrait},
        modifier_type::types as modifier_types,
        processor::{statuses, types, Processor, ProcessorTrait}};
    use influence::config::{actions, entities, errors, permissions};
    use influence::systems::production;
    use influence::types::{Context, Entity, EntityTrait, InventoryItem, InventoryItemTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct MaterialProcessingStarted {
        processor: Entity,
        processor_slot: u64,
        process: u64,
        inputs: Span<InventoryItem>,
        outputs: Span<InventoryItem>,
        destination: Entity,
        destination_slot: u64,
        finish_time: u64,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[derive(Copy, Drop, starknet::Event)]
    struct MaterialProcessingStartedV1 {
        processor: Entity,
        processor_slot: u64,
        process: u64,
        inputs: Span<InventoryItem>,
        origin: Entity,
        origin_slot: u64,
        outputs: Span<InventoryItem>,
        destination: Entity,
        destination_slot: u64,
        finish_time: u64,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        MaterialProcessingStartedV1: MaterialProcessingStartedV1
    }

    #[external(v0)]
    fn run(
        ref self: ContractState,
        processor: Entity,
        processor_slot: u64,
        process: u64,
        target_output: u64, // output product to focus
        recipes: Fixed, // # of recipes to process (positive Fixed value)
        origin: Entity,
        origin_slot: u64,
        destination: Entity,
        destination_slot: u64,
        caller_crew: Entity,
        context: Context
    ) {
        // Check that crew is delegated, and ready
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_all_ready_within(context.caller, context.now);
        let mut crew_data = crew_details.component;

        // Check that the processing slot is ready
        components::get::<Building>(processor.path()).expect(errors::BUILDING_NOT_FOUND).assert_operational();
        let mut processor_path: Array<felt252> = Default::default();
        processor_path.append(processor.into());
        processor_path.append(processor_slot.into());
        let mut processor_data = components::get::<Processor>(processor_path.span())
            .expect(errors::PROCESSOR_NOT_FOUND);
        processor_data.assert_ready();

        // Calculate inputs and outputs based on target
        assert(recipes > FixedTrait::ZERO(), 'invalid # of recipes');
        let process_config = ProcessTypeTrait::by_type(process);
        assert(process_config.processor_type == processor_data.processor_type, 'incorrect processor');
        let inputs = production::helpers::inputs(process_config.inputs, recipes);

        // Use secondary output bonus and store on processor component
        let secondary_eff = crew_details.bonus(modifier_types::SECONDARY_REFINING_YIELD, context.now);
        let outputs = production::helpers::outputs(process_config.outputs, target_output, recipes, secondary_eff);

        // Calculate the processing time based on Mx + B (ceil for bioreactor) and use modifer
        let process_eff = crew_details.bonus(modifier(processor_data.processor_type), context.now);
        let (setup_time, variable_time) = production::helpers::time(
            process_config.setup_time, process_config.recipe_time, process_config.batched, recipes, process_eff
        );

        // Check for permissions on origin and remove products
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
        let mut origin_path: Array<felt252> = Default::default();
        origin_path.append(origin.into());
        origin_path.append(origin_slot.into());
        let mut origin_data = components::get::<Inventory>(origin_path.span()).expect(errors::INVENTORY_NOT_FOUND);
        inventory::remove(ref origin_data, inputs);
        components::set::<Inventory>(origin_path.span(), origin_data);

        // Check that the destination exists and is ready to receive
        if destination.label == entities::BUILDING {
            let building_data = components::get::<Building>(destination.path()).expect(errors::BUILDING_NOT_FOUND);
            let config = BuildingTypeTrait::by_type(building_data.building_type);
            let planning = building_data.status == building_statuses::PLANNED && config.site_slot == destination_slot;

            assert(planning || building_data.status == building_statuses::OPERATIONAL, 'inventory inaccessible');
        } else if destination.label == entities::SHIP {
            components::get::<Ship>(destination.path()).expect(errors::SHIP_NOT_FOUND).assert_stationary();
            let location = components::get::<Location>(destination.path()).expect(errors::LOCATION_NOT_FOUND);

            match components::get::<Building>(location.location.path()) {
                Option::Some(building_data) => building_data.assert_operational(),
                Option::None(_) => ()
            };
        }

        let mut destination_path: Array<felt252> = Default::default();
        destination_path.append(destination.into());
        destination_path.append(destination_slot.into());
        let mut destination_data = components::get::<Inventory>(destination_path.span())
            .expect(errors::INVENTORY_NOT_FOUND);

        let mass_eff = crew_details.bonus(modifier_types::INVENTORY_MASS_CAPACITY, context.now);
        let volume_eff = crew_details.bonus(modifier_types::INVENTORY_VOLUME_CAPACITY, context.now);
        inventory::reserve(ref destination_data, outputs, mass_eff, volume_eff);
        components::set::<Inventory>(destination_path.span(), destination_data);

        // Check that all buildings are present on the same asteroid
        let (origin_ast, origin_lot) = origin.to_position();
        let (process_ast, process_lot) = processor.to_position();
        let (dest_ast, dest_lot) = destination.to_position();
        assert((origin_ast == dest_ast) && (origin_ast == process_ast), errors::DIFFERENT_ASTEROIDS);
        assert((origin_lot != 0) && (dest_lot != 0) && (process_lot != 0), errors::IN_ORBIT);

        // Calculate the hopper transfer times
        let hopper_eff = crew_details.bonus(modifier_types::HOPPER_TRANSPORT_TIME, context.now);
        let dist_eff = crew_details.bonus(modifier_types::FREE_TRANSPORT_DISTANCE, context.now);
        let ast = components::get::<Celestial>(EntityTrait::new(entities::ASTEROID, origin_ast).path())
            .expect(errors::CELESTIAL_NOT_FOUND);

        let origin_to_processor = position::hopper_travel_time(origin_lot, dest_lot, ast.radius, hopper_eff, dist_eff);
        let processor_to_dest = position::hopper_travel_time(process_lot, dest_lot, ast.radius, hopper_eff, dist_eff);

        // Total processing time
        assert(crew_details.asteroid_id() == origin_ast, errors::DIFFERENT_ASTEROIDS);
        assert(crew_details.lot_id() != 0, errors::IN_ORBIT);
        let crew_to_processor = position::hopper_travel_time(
            crew_details.lot_id(), process_lot, ast.radius, hopper_eff, dist_eff
        );

        let positioning_time = max(crew_to_processor, origin_to_processor);

        let max_time = config::get('MAX_PROCESS_TIME').try_into().unwrap() /
            config::get('TIME_ACCELERATION').try_into().unwrap();
        assert(positioning_time + setup_time + variable_time <= max_time, errors::MAX_PROCESS_TIME_EXCEEDED);
        let finish_time = crew_data.busy_until(context.now) +
            positioning_time + setup_time + variable_time + processor_to_dest;

        // Check that the crew has the necessary permissions given the processing time
        caller_crew.assert_can_until(processor, permissions::RUN_PROCESS, finish_time);
        caller_crew.assert_can_until(destination, permissions::ADD_PRODUCTS, finish_time);

        // Update the processor and save
        processor_data.status = statuses::RUNNING;
        processor_data.running_process = process;
        processor_data.output_product = target_output;
        processor_data.recipes = recipes;
        processor_data.secondary_eff = secondary_eff;
        processor_data.destination = destination;
        processor_data.destination_slot = destination_slot;
        processor_data.finish_time = finish_time;
        components::set::<Processor>(processor_path.span(), processor_data);

        // Update the crew & ship (there + wait for products + process time + back)
        let crew_time = (setup_time + variable_time).div_ceil(8);
        crew_data.add_busy(context.now, positioning_time + crew_time + crew_to_processor);
        crew_data.set_action(actions::PROCESS_PRODUCTS_STARTED, processor, crew_time, context.now);
        components::set::<Crew>(caller_crew.path(), crew_data);

        let (station_ship, mut station_ship_data) = crew_details.ship();
        if caller_crew != station_ship {
            station_ship_data.extend_ready(crew_data.ready_at);
            components::set::<Ship>(station_ship.path(), station_ship_data);
        }

        self.emit(MaterialProcessingStartedV1 {
            processor: processor,
            processor_slot: processor_slot,
            process: process,
            inputs: inputs,
            origin: origin,
            origin_slot: origin_slot,
            outputs: outputs,
            destination: destination,
            destination_slot: destination_slot,
            finish_time: finish_time,
            caller_crew: caller_crew,
            caller: context.caller,
        });
    }

    // Returns the applicable modifier type based on the processor type
    fn modifier(t: u64) -> u64 {
        if t == types::REFINERY {
            return modifier_types::REFINING_TIME;
        } else if t == types::FACTORY {
            return modifier_types::MANUFACTURING_TIME;
        } else if t == types::BIOREACTOR {
            return modifier_types::REACTION_TIME;
        } else if t == types::SHIPYARD {
            return modifier_types::MANUFACTURING_TIME;
        }

        assert(false, errors::PROCESSOR_NOT_FOUND);
        return 0;
    }
}
