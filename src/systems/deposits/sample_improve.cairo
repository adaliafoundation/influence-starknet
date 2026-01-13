// Further samples a deposit to improve the yield
// - Schedulable

#[starknet::contract]
mod SampleDepositImprove {
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
    use influence::config::{entities, errors, permissions};
    use influence::systems::deposits::helpers::deposit_commit_hash;
    use influence::types::{Context, Entity, EntityTrait, InventoryItem, InventoryItemTrait};

    #[storage]
    struct Storage {}

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
        SamplingDepositStartedV1: SamplingDepositStartedV1
    }

    #[external(v0)]
    fn run(
        ref self: ContractState,
        deposit: Entity,
        origin: Entity,
        origin_slot: u64,
        caller_crew: Entity,
        context: Context
    ) {
        // Check that crew is delegated, and ready
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_all_ready_within(context.caller, context.now);
        let mut crew_data = crew_details.component;

        // Find existing deposit and validate
        let mut deposit_data = components::get::<Deposit>(deposit.path()).expect(errors::DEPOSIT_NOT_FOUND);
        caller_crew.can(deposit, permissions::USE_DEPOSIT); // must have permission
        assert(deposit_data.status == deposit_statuses::SAMPLED, errors::INCORRECT_STATUS); // must not be used
        let (deposit_ast, deposit_lot) = deposit.to_position();

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
        assert(origin_ast == deposit_ast, errors::DIFFERENT_ASTEROIDS);
        assert(origin_lot != 0, errors::IN_ORBIT);

        // Start the core sample
        let sample_eff = crew_details.bonus(modifier_types::CORE_SAMPLE_TIME, context.now);
        let base_time = config::get('CORE_SAMPLING_TIME').try_into().unwrap() /
            config::get('TIME_ACCELERATION').try_into().unwrap();
        let sampling_time = (FixedTrait::new_unscaled(base_time, false) / sample_eff).mag.div_ceil(ONE);

        // Check the asteroid is resource scanned
        let celestial_data = components::get::<Celestial>(EntityTrait::new(entities::ASTEROID, deposit_ast).path())
            .expect(errors::CELESTIAL_NOT_FOUND);

        // Update the crew (must be present during sampling)
        assert(crew_details.asteroid_id() == deposit_ast, errors::DIFFERENT_ASTEROIDS);
        assert(crew_details.lot_id() != 0, errors::IN_ORBIT);
        let hopper_eff = crew_details.bonus(modifier_types::HOPPER_TRANSPORT_TIME, context.now);
        let dist_eff = crew_details.bonus(modifier_types::FREE_TRANSPORT_DISTANCE, context.now);
        let crew_to_lot = position::hopper_travel_time(
            crew_details.lot_id(), deposit_lot, celestial_data.radius, hopper_eff, dist_eff
        );

        // Remove core sample from inventory
        let origin_to_lot = position::hopper_travel_time(
            origin_lot, deposit_lot, celestial_data.radius, hopper_eff, dist_eff
        );

        let mut items: Array<InventoryItem> = Default::default();
        items.append(InventoryItemTrait::new(product_types::CORE_DRILL, 1));
        inventory::remove(ref origin_data, items.span());
        components::set::<Inventory>(origin_path.span(), origin_data);

        // Commit to future randomness round
        random::commit(deposit_commit_hash(deposit, deposit_data.initial_yield), 1);

        // Update and store deposit data
        deposit_data.status = deposit_statuses::SAMPLING;
        deposit_data.finish_time = crew_data.busy_until(context.now) + max(origin_to_lot, crew_to_lot) + sampling_time;
        deposit_data.yield_eff = crew_details.bonus(modifier_types::CORE_SAMPLE_QUALITY, context.now);
        components::set::<Deposit>(deposit.path(), deposit_data);

        // Update Crew data
        crew_data.ready_at = deposit_data.finish_time + crew_to_lot; // there and back
        components::set::<Crew>(caller_crew.path(), crew_data);

        let (station_ship, mut station_ship_data) = crew_details.ship();
        if caller_crew != station_ship {
            station_ship_data.extend_ready(crew_data.ready_at);
            components::set::<Ship>(station_ship.path(), station_ship_data);
        }

        self.emit(SamplingDepositStartedV1 {
            deposit: deposit,
            lot: EntityTrait::from_position(deposit_ast, deposit_lot),
            resource: deposit_data.resource,
            improving: true,
            origin: origin,
            origin_slot: origin_slot,
            finish_time: deposit_data.finish_time,
            caller_crew: caller_crew,
            caller: context.caller
        });
    }
}
