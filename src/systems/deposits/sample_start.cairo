// Starts a new deposit targeting a specific resource and lot
// - Schedulable

#[starknet::contract]
mod SampleDepositStart {
    use array::{ArrayTrait, SpanTrait};
    use cmp::max;
    use option::OptionTrait;
    use starknet::ContractAddress;
    use traits::{Into, TryInto};

    use cubit::f64::{Fixed, FixedTrait, ONE};

    use influence::{components, config};
    use influence::common::{inventory, math::RoundedDivTrait, position, random, crew::CrewDetailsTrait};
    use influence::components::{Building, BuildingTrait, Celestial, CelestialTrait, Control, ControlTrait, Crew,
        CrewTrait, Inventory, InventoryTrait, Location, LocationTrait, Ship, ShipTrait,
        modifier_type::types as modifier_types,
        product_type::types as product_types,
        deposit::{statuses as deposit_statuses, Deposit, DepositTrait}};
    use influence::config::{actions, entities, errors, permissions};
    use influence::entities::next_id;
    use influence::systems::deposits::helpers::deposit_commit_hash;
    use influence::types::{Context, Entity, EntityTrait, InventoryItem, InventoryItemTrait};

    #[storage]
    struct Storage {}

    // Deprecated (remains to be included in ABI)
    #[derive(Copy, Drop, starknet::Event)]
    struct SamplingDepositStarted {
        deposit: Entity,
        lot: Entity,
        resource: u64,
        finish_time: u64,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[derive(Copy, Drop, starknet::Event)]
    struct SamplingDepositStartedV1 {
        deposit: Entity,
        lot: Entity,
        resource: u64,
        improving: bool,
        origin: Entity,
        origin_slot: u64,
        finish_time: u64,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        SamplingDepositStarted: SamplingDepositStarted,
        SamplingDepositStartedV1: SamplingDepositStartedV1
    }

    #[external(v0)]
    fn run(
        ref self: ContractState,
        lot: Entity,
        resource: u64,
        origin: Entity,
        origin_slot: u64,
        caller_crew: Entity,
        context: Context
    ) {
        // Check that crew is delegated, and ready
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_all_ready_within(context.caller, context.now);
        let mut crew_data = crew_details.component;

        // Check for permissions on origin inventory
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
        let mut origin_path:Array<felt252> = Default::default();
        origin_path.append(origin.into());
        origin_path.append(origin_slot.into());
        let mut origin_data = components::get::<Inventory>(origin_path.span()).expect(errors::INVENTORY_NOT_FOUND);

        // Check that all buildings are present on the same asteroid
        let (origin_ast, origin_lot) = origin.to_position();
        let (lot_ast, lot_lot) = lot.to_position();
        assert(origin_ast == lot_ast, errors::DIFFERENT_ASTEROIDS);
        assert((origin_lot != 0) && (lot_lot != 0), errors::IN_ORBIT);

        // Check the asteroid is resource scanned
        let ast = components::get::<Celestial>(EntityTrait::new(entities::ASTEROID, origin_ast).path())
            .expect(errors::CELESTIAL_NOT_FOUND);
        ast.assert_resource_scanned();

        // Calculate the hopper transfer times
        let hopper_eff = crew_details.bonus(modifier_types::HOPPER_TRANSPORT_TIME, context.now);
        let dist_eff = crew_details.bonus(modifier_types::FREE_TRANSPORT_DISTANCE, context.now);
        let origin_to_lot = position::hopper_travel_time(origin_lot, lot_lot, ast.radius, hopper_eff, dist_eff);

        // Remove core sample from inventory
        let mut items: Array<InventoryItem> = Default::default();
        items.append(InventoryItemTrait::new(product_types::CORE_DRILL, 1));
        inventory::remove(ref origin_data, items.span());
        components::set::<Inventory>(origin_path.span(), origin_data);

        // Find existing deposit (for improvement) or create a new one
        let deposit = EntityTrait::new(entities::DEPOSIT, next_id(entities::DEPOSIT.into()));
        components::set::<Control>(deposit.path(), ControlTrait::new(caller_crew));
        components::set::<Location>(deposit.path(), LocationTrait::new(lot));
        let mut deposit_data = DepositTrait::new(resource);

        // Start the core sample
        let sample_eff = crew_details.bonus(modifier_types::CORE_SAMPLE_TIME, context.now);
        let base_time = config::get('CORE_SAMPLING_TIME').try_into().unwrap() /
            config::get('TIME_ACCELERATION').try_into().unwrap();
        let sampling_time = (FixedTrait::new_unscaled(base_time, false) / sample_eff).mag.div_ceil(ONE);

        // Update the crew (must be present during sampling)
        assert(crew_details.asteroid_id() == origin_ast, errors::DIFFERENT_ASTEROIDS);
        assert(crew_details.lot_id() != 0, errors::IN_ORBIT);
        let crew_to_lot = position::hopper_travel_time(
            crew_details.lot_id(), lot_lot, ast.radius, hopper_eff, dist_eff
        );

        // Commit to future randomness round
        random::commit(deposit_commit_hash(deposit, deposit_data.initial_yield), 1);

        // Update and store deposit data
        deposit_data.status = deposit_statuses::SAMPLING;
        deposit_data.finish_time = crew_data.busy_until(context.now) + max(origin_to_lot, crew_to_lot) + sampling_time;
        // NOTE: consider eliminating since crew is busy the entire time (yield eff can't change)
        deposit_data.yield_eff = crew_details.bonus(modifier_types::CORE_SAMPLE_QUALITY, context.now);
        components::set::<Deposit>(deposit.path(), deposit_data);

        // Update Crew data
        crew_data.ready_at = deposit_data.finish_time + crew_to_lot; // there and back
        crew_data.set_action(actions::SAMPLE_DEPOSIT_STARTED, deposit, sampling_time, context.now);
        components::set::<Crew>(caller_crew.path(), crew_data);

        let (station_ship, mut station_ship_data) = crew_details.ship();
        if caller_crew != station_ship {
            station_ship_data.extend_ready(crew_data.ready_at);
            components::set::<Ship>(station_ship.path(), station_ship_data);
        }

        self.emit(SamplingDepositStartedV1 {
            deposit: deposit,
            lot: lot,
            resource: resource,
            improving: false,
            origin: origin,
            origin_slot: origin_slot,
            finish_time: deposit_data.finish_time,
            caller_crew: caller_crew,
            caller: context.caller
        });
    }
}
