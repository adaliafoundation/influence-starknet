// Starts the construction of a building after all the materials are present
// = Schedulable

#[starknet::contract]
mod ConstructionStart {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use starknet::contract_address::ContractAddress;
    use traits::{Into, TryInto};

    use cubit::f64::FixedTrait;

    use influence::{components, config, entities::next_id};
    use influence::common::{crew::CrewDetailsTrait, inventory, math::RoundedDivTrait, position};
    use influence::components::{Celestial, CelestialTrait, Control, ControlTrait, Crew, CrewTrait,
        ProcessTypeTrait, Ship, ShipTrait, Unique, UniqueTrait,
        building::{statuses as building_statuses, Building, BuildingTrait},
        building_type::{types as building_types, BuildingTypeTrait},
        inventory_type::types as inventory_types,
        modifier_type::types as modifier_types,
        inventory::{statuses as inventory_statuses, Inventory, InventoryTrait}};
    use influence::config::{entities, errors};
    use influence::systems::production;
    use influence::types::{Context, Entity, EntityTrait, InventoryContentsTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct ConstructionStarted {
        building: Entity,
        finish_time: u64,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        ConstructionStarted: ConstructionStarted
    }

    #[external(v0)]
    fn run(ref self: ContractState, building: Entity, caller_crew: Entity, context: Context) {
        // Check that crew is delegated, and ready
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_all_ready_within(context.caller, context.now);
        let mut crew_data = crew_details.component;

        // Check permissions
        caller_crew.assert_controls(building);

        // Check that building is ready
        let mut building_data = components::get::<Building>(building.path()).expect(errors::BUILDING_NOT_FOUND);
        building_data.assert_planned();

        // Check that required construction materials are present (and remove)
        let config = BuildingTypeTrait::by_type(building_data.building_type);
        let mut site_path: Array<felt252> = Default::default();
        site_path.append(building.into());
        site_path.append(config.site_slot.into());

        // Update / lock inventory
        let mut inv_data = components::get::<Inventory>(site_path.span()).expect(errors::INVENTORY_NOT_FOUND);

        // Check that enough materials are present
        let process_config = ProcessTypeTrait::by_type(config.process_type);

        let mut iter = 0;
        loop {
            if iter >= process_config.inputs.len() { break; }
            let item = *process_config.inputs.at(iter);
            assert(inv_data.contents.amount_of(item.product) >= item.amount, errors::INSUFFICIENT_AMOUNT);
            iter += 1;
        };

        // Lock inventory
        inv_data.disable();
        components::set::<Inventory>(site_path.span(), inv_data);

        // Check that crew is in the right location
        let (building_ast, building_lot) = building.to_position();
        assert(crew_details.asteroid_id() == building_ast, errors::DIFFERENT_ASTEROIDS);

        // Calculate the hopper transfer times
        let hopper_eff = crew_details.bonus(modifier_types::HOPPER_TRANSPORT_TIME, context.now);
        let dist_eff = crew_details.bonus(modifier_types::FREE_TRANSPORT_DISTANCE, context.now);
        let asteroid = EntityTrait::new(entities::ASTEROID, building_ast);
        let celestial_data = components::get::<Celestial>(asteroid.path()).expect(errors::CELESTIAL_NOT_FOUND);
        let crew_to_lot = position::hopper_travel_time(
            crew_details.lot_id(), building_lot, celestial_data.radius, hopper_eff, dist_eff
        );

        // Calculate finish time
        let construct_eff = crew_details.bonus(modifier_types::CONSTRUCTION_TIME, context.now);
        let (setup_time, variable_time) = production::helpers::time(
            process_config.setup_time,
            process_config.recipe_time,
            process_config.batched,
            FixedTrait::ONE(),
            construct_eff
        );

        let build_time = setup_time + variable_time;
        let finish_time = crew_data.busy_until(context.now) + crew_to_lot + build_time;

        // Update building
        building_data.status = building_statuses::UNDER_CONSTRUCTION;
        building_data.finish_time = finish_time;
        components::set::<Building>(building.path(), building_data);

        // Update crew & ship
        crew_data.add_busy(context.now, (crew_to_lot * 2) + build_time.div_ceil(8));
        components::set::<Crew>(caller_crew.path(), crew_data);

        let (station_ship, mut station_ship_data) = crew_details.ship();
        if caller_crew != station_ship {
            station_ship_data.extend_ready(crew_data.ready_at);
            components::set::<Ship>(station_ship.path(), station_ship_data);
        }

        self.emit(ConstructionStarted {
            building: building,
            finish_time: finish_time,
            caller_crew: caller_crew,
            caller: context.caller
        });
    }
}
