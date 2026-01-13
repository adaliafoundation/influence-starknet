#[starknet::contract]
mod ExtractResourceStart {
    use array::{Array, ArrayTrait};
    use option::OptionTrait;
    use starknet::ContractAddress;
    use traits::{Into, TryInto};

    use cubit::f64::{Fixed, FixedTrait, ONE};

    use influence::{components, config};
    use influence::common::{crew::CrewDetailsTrait, inventory, math::RoundedDivTrait, position, random};
    use influence::components::{Celestial, CelestialTrait, Crew, CrewTrait, Building, BuildingTrait, Inventory,
        InventoryTrait, Location, Ship, ShipTrait,
        modifier_type::types as modifier_types,
        deposit::{statuses as deposit_statuses, Deposit, DepositTrait, MAX_YIELD},
        extractor, extractor::{statuses as extractor_statuses, Extractor, ExtractorTrait}};
    use influence::config::{actions, entities, errors, permissions};
    use influence::types::{Context, Entity, EntityTrait, InventoryItem, InventoryItemTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct ResourceExtractionStarted {
        deposit: Entity,
        resource: u64,
        yield: u64,
        extractor: Entity,
        extractor_slot: u64,
        destination: Entity,
        destination_slot: u64,
        finish_time: u64,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        ResourceExtractionStarted: ResourceExtractionStarted
    }

    #[external(v0)]
    fn run(
        ref self: ContractState,
        deposit: Entity,
        yield: u64,
        extractor: Entity,
        extractor_slot: u64,
        destination: Entity,
        destination_slot: u64,
        caller_crew: Entity,
        context: Context
    ) {
        // Check that crew is delegated, and ready
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_all_ready_within(context.caller, context.now);
        let mut crew_data = crew_details.component;

        // Permissions checks
        caller_crew.assert_can(deposit, permissions::USE_DEPOSIT);

        // Check that the extraction slot is ready
        components::get::<Building>(extractor.path()).expect(errors::BUILDING_NOT_FOUND).assert_operational();
        let mut extractor_path: Array<felt252> = Default::default();
        extractor_path.append(extractor.into());
        extractor_path.append(extractor_slot.into());
        let mut extractor_data = components::get::<Extractor>(extractor_path.span())
            .expect(errors::EXTRACTOR_NOT_FOUND);

        extractor_data.assert_ready();

        // Check that deposit is valid
        let mut deposit_data = components::get::<Deposit>(deposit.path()).expect(errors::DEPOSIT_NOT_FOUND);
        deposit_data.assert_extractable();
        assert(deposit_data.remaining_yield >= yield, errors::INSUFFICIENT_YIELD);

        // Check that crew, deposit, and destination are all on the same asteroid
        let (ext_ast, ext_lot) = extractor.to_position();
        let (deposit_ast, deposit_lot) = deposit.to_position();
        assert(ext_ast == deposit_ast, errors::DIFFERENT_ASTEROIDS);
        assert(ext_lot == deposit_lot, errors::DIFFERENT_LOTS);

        let (dest_ast, dest_lot) = destination.to_position();
        assert((dest_ast == deposit_ast) && (crew_details.asteroid_id() == deposit_ast), errors::DIFFERENT_ASTEROIDS);
        assert((dest_lot != 0) && (crew_details.lot_id() != 0), errors::IN_ORBIT);

        // Check that the destination exists and is ready to receive
        if destination.label == entities::BUILDING {
            components::get::<Building>(destination.path()).expect(errors::BUILDING_NOT_FOUND).assert_operational();
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

        // Calculate extraction time
        // total time left with starting yield - total time left with ending yield (t = sqrt(yield))
        let max_yield = FixedTrait::new(extractor::MAX_YIELD_PER_RUN, false);
        let start_ratio = FixedTrait::new_unscaled(deposit_data.remaining_yield.into(), false) / max_yield;
        let end_ratio = FixedTrait::new_unscaled(deposit_data.remaining_yield.into() - yield.into(), false) / max_yield;
        let accel: u64 = config::get('TIME_ACCELERATION').try_into().unwrap();
        let extract_time_raw = (start_ratio.sqrt() - end_ratio.sqrt()) *
            FixedTrait::new(extractor::MAX_EXTRACTION_TIME * ONE / accel, false);

        // Get asteroid resource bonus and crew bonus
        let asteroid = EntityTrait::new(entities::ASTEROID, dest_ast);
        let celestial_data = components::get::<Celestial>(asteroid.path()).expect(errors::CELESTIAL_NOT_FOUND);
        let resource_bonus = celestial_data.bonus_by_resource(deposit_data.resource);
        let extract_eff = crew_details.bonus(modifier_types::EXTRACTION_TIME, context.now) * resource_bonus;
        let extract_time = (extract_time_raw / extract_eff).mag.div_ceil(ONE);

        // Calculate the crew and hopper transfer times
        let hopper_eff = crew_details.bonus(modifier_types::HOPPER_TRANSPORT_TIME, context.now);
        let dist_eff = crew_details.bonus(modifier_types::FREE_TRANSPORT_DISTANCE, context.now);
        let dep_to_dest = position::hopper_travel_time(
            deposit_lot, dest_lot, celestial_data.radius, hopper_eff, dist_eff
        );

        let crew_to_lot = position::hopper_travel_time(
            crew_details.lot_id(), deposit_lot, celestial_data.radius, hopper_eff, dist_eff
        );

        // Reserve space in destination inventory
        let mut reserved_items: Array<InventoryItem> = Default::default();
        reserved_items.append(InventoryItemTrait::new(deposit_data.resource, yield));
        let mass_eff = crew_details.bonus(modifier_types::INVENTORY_MASS_CAPACITY, context.now);
        let volume_eff = crew_details.bonus(modifier_types::INVENTORY_VOLUME_CAPACITY, context.now);
        inventory::reserve(ref destination_data, reserved_items.span(), mass_eff, volume_eff);
        components::set::<Inventory>(destination_path.span(), destination_data);

        // Update the deposit
        deposit_data.remaining_yield -= yield;
        deposit_data.status = deposit_statuses::USED;
        components::set::<Deposit>(deposit.path(), deposit_data);

        // Update the extractor
        let finish_time = crew_data.busy_until(context.now) + crew_to_lot + extract_time + dep_to_dest;
        extractor_data.status = extractor_statuses::RUNNING;
        extractor_data.output_product = deposit_data.resource;
        extractor_data.yield = yield;
        extractor_data.destination = destination;
        extractor_data.destination_slot = destination_slot;
        extractor_data.finish_time = finish_time;
        components::set::<Extractor>(extractor_path.span(), extractor_data);

        // Check that the crew has the necessary permissions given the processing time
        caller_crew.assert_can_until(extractor, permissions::EXTRACT_RESOURCES, finish_time);
        caller_crew.assert_can_until(destination, permissions::ADD_PRODUCTS, finish_time);

        // Update the crew & ship (there + processing time + back)
        let crew_time = extract_time.div_ceil(8);
        crew_data.add_busy(context.now, crew_to_lot + crew_time + crew_to_lot);
        crew_data.set_action(actions::EXTRACT_RESOURCE_STARTED, extractor, crew_time, context.now);
        components::set::<Crew>(caller_crew.path(), crew_data);

        let (station_ship, mut station_ship_data) = crew_details.ship();
        if caller_crew != station_ship {
            station_ship_data.extend_ready(crew_data.ready_at);
            components::set::<Ship>(station_ship.path(), station_ship_data);
        }

        self.emit(ResourceExtractionStarted {
            deposit: deposit,
            resource: deposit_data.resource,
            yield: yield,
            extractor: extractor,
            extractor_slot: extractor_slot,
            destination: destination,
            destination_slot: destination_slot,
            finish_time: finish_time,
            caller_crew: caller_crew,
            caller: context.caller
        });
    }
}
