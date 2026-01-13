mod construction_abandon;
mod construction_finish;
mod construction_plan;
mod construction_start;
mod construction_deconstruct;

use construction_abandon::ConstructionAbandon;
use construction_finish::ConstructionFinish;
use construction_plan::ConstructionPlan;
use construction_start::ConstructionStart;
use construction_deconstruct::ConstructionDeconstruct;

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use traits::{Into, TryInto};

    use influence::{config, components};
    use influence::common::inventory;
    use influence::components::crew::CrewTrait;
    use influence::components::{Control, ControlTrait, Crew, Location, LocationTrait, Unique,
        building::{statuses as building_statuses, Building},
        building_type::types as building_types,
        inventory_type::types as inventory_types,
        modifier_type::types as modifier_types,
        process_type::types as process_types,
        product_type::types as product_types,
        inventory::{statuses as inventory_statuses, Inventory, InventoryTrait}};
    use influence::config::entities;
    use influence::types::{EntityTrait, InventoryItem, InventoryItemTrait, InventoryContentsTrait};
    use influence::test::{helpers, mocks};

    use super::{ConstructionPlan, ConstructionStart, ConstructionFinish, ConstructionDeconstruct, ConstructionAbandon};

    #[test]
    #[should_panic(expected: ('E2005: incorrect controller', ))]
    #[available_gas(55000000)]
    fn test_no_squatting() {
        helpers::init();
        mocks::constants();
        starknet::testing::set_block_timestamp(100);

        let asteroid = mocks::asteroid();
        let crew = mocks::delegated_crew(1, 'PLAYER');

        // Add configs
        mocks::process_type(process_types::WAREHOUSE_CONSTRUCTION);
        mocks::building_type(building_types::WAREHOUSE);
        mocks::inventory_type(inventory_types::WAREHOUSE_PRIMARY);
        mocks::inventory_type(inventory_types::WAREHOUSE_SITE);
        mocks::product_type(product_types::CEMENT);
        mocks::product_type(product_types::STEEL_BEAM);
        mocks::product_type(product_types::STEEL_SHEET);
        mocks::modifier_type(modifier_types::HOPPER_TRANSPORT_TIME);
        mocks::modifier_type(modifier_types::FREE_TRANSPORT_DISTANCE);
        mocks::modifier_type(modifier_types::CONSTRUCTION_TIME);
        mocks::modifier_type(modifier_types::DECONSTRUCTION_YIELD);

        // Setup station
        let station = mocks::public_habitat(crew, 10001);
        components::set::<Location>(station.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1)));
        components::set::<Location>(crew.path(), LocationTrait::new(station));

        // Plan construction
        let lot = EntityTrait::from_position(asteroid.id, 1001);
        let mut plan_state = ConstructionPlan::contract_state_for_testing();
        ConstructionPlan::run(
            ref plan_state,
            building_type: building_types::WAREHOUSE,
            lot: lot,
            caller_crew: crew,
            context: mocks::context('PLAYER')
        );
    }

    #[test]
    #[available_gas(55000000)]
    fn test_build_loop() {
        helpers::init();
        mocks::constants();
        starknet::testing::set_block_timestamp(100);

        let asteroid = mocks::asteroid();
        let crew = mocks::delegated_crew(1, 'PLAYER');
        components::set::<Control>(asteroid.path(), ControlTrait::new(crew));

        // Add configs
        mocks::process_type(process_types::WAREHOUSE_CONSTRUCTION);
        mocks::building_type(building_types::WAREHOUSE);
        mocks::inventory_type(inventory_types::WAREHOUSE_PRIMARY);
        mocks::inventory_type(inventory_types::WAREHOUSE_SITE);
        mocks::product_type(product_types::CEMENT);
        mocks::product_type(product_types::STEEL_BEAM);
        mocks::product_type(product_types::STEEL_SHEET);
        mocks::modifier_type(modifier_types::HOPPER_TRANSPORT_TIME);
        mocks::modifier_type(modifier_types::FREE_TRANSPORT_DISTANCE);
        mocks::modifier_type(modifier_types::CONSTRUCTION_TIME);
        mocks::modifier_type(modifier_types::DECONSTRUCTION_YIELD);

        // Setup station
        let station = mocks::public_habitat(crew, 10001);
        components::set::<Location>(station.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1)));
        components::set::<Location>(crew.path(), LocationTrait::new(station));

        // Plan construction
        let lot = EntityTrait::from_position(asteroid.id, 1001);
        let mut plan_state = ConstructionPlan::contract_state_for_testing();
        ConstructionPlan::run(
            ref plan_state,
            building_type: building_types::WAREHOUSE,
            lot: lot,
            caller_crew: crew,
            context: mocks::context('PLAYER')
        );

        let building = EntityTrait::new(entities::BUILDING, 1);
        let mut building_data = components::get::<Building>(building.path()).unwrap();
        assert(building_data.building_type == building_types::WAREHOUSE, 'wrong type');

        let controller = components::get::<Control>(building.path()).unwrap().controller;
        assert(controller == crew, 'controller should be set');

        // Setup warehouse
        let inventory_path = array![building.into(), 1].span();
        let mut inventory_data = components::get::<Inventory>(inventory_path).unwrap();
        let supplies = array![
            InventoryItemTrait::new(product_types::CEMENT, 400000),
            InventoryItemTrait::new(product_types::STEEL_BEAM, 350000),
            InventoryItemTrait::new(product_types::STEEL_SHEET, 200000)
        ].span();

        inventory::add_unchecked(ref inventory_data, supplies);
        components::set::<Inventory>(inventory_path, inventory_data);

        // Start construction
        starknet::testing::set_block_timestamp(10000);
        let mut start_state = ConstructionStart::contract_state_for_testing();
        ConstructionStart::run(
            ref start_state,
            building: building,
            caller_crew: crew,
            context: mocks::context('PLAYER')
        );

        building_data = components::get::<Building>(building.path()).unwrap();
        assert(building_data.status == building_statuses::UNDER_CONSTRUCTION, 'wrong status');

        // Finish construction
        starknet::testing::set_block_timestamp(200000);
        let mut finish_state = ConstructionFinish::contract_state_for_testing();
        ConstructionFinish::run(
            ref finish_state,
            building: building,
            caller_crew: crew,
            context: mocks::context('PLAYER')
        );

        assert(
            components::get::<Building>(building.path()).unwrap().status == building_statuses::OPERATIONAL,
            'wrong status'
        );

        // Deconstruct building
        let mut deconstruct_state = ConstructionDeconstruct::contract_state_for_testing();
        ConstructionDeconstruct::run(
            ref deconstruct_state,
            building: building,
            caller_crew: crew,
            context: mocks::context('PLAYER')
        );

        assert(
            components::get::<Building>(building.path()).unwrap().status == building_statuses::PLANNED,
            'wrong status'
        );

        inventory_data = components::get::<Inventory>(inventory_path).unwrap();
        assert(inventory_data.contents.amount_of(product_types::CEMENT) == 366666, 'wrong amount');
        assert(inventory_data.contents.amount_of(product_types::STEEL_BEAM) == 320833, 'wrong amount');
        assert(inventory_data.contents.amount_of(product_types::STEEL_SHEET) == 183333, 'wrong amount');

        // Clear out inventory
        inventory_data = InventoryTrait::new(inventory_types::WAREHOUSE_PRIMARY);
        components::set::<Inventory>(inventory_path, inventory_data);

        // Abandon building
        let mut abandon_state = ConstructionAbandon::contract_state_for_testing();
        ConstructionAbandon::run(
            ref abandon_state,
            building: building,
            caller_crew: crew,
            context: mocks::context('PLAYER')
        );

        assert(
            components::get::<Building>(building.path()).unwrap().status == building_statuses::UNPLANNED,
            'wrong status'
        );

        assert(components::get::<Unique>(array!['LotUse', lot.into()].span()).is_none(), 'lot should be free');
    }
}
