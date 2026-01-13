mod assemble_ship_start;
mod assemble_ship_finish;
mod extract_resource_start;
mod extract_resource_finish;
mod process_products_start;
mod process_products_finish;

use assemble_ship_start::AssembleShipStart;
use assemble_ship_finish::AssembleShipFinish;
use extract_resource_start::ExtractResourceStart;
use extract_resource_finish::ExtractResourceFinish;
use process_products_start::ProcessProductsStart;
use process_products_finish::ProcessProductsFinish;

mod helpers {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use traits::{Into, TryInto};

    use cubit::f64::{Fixed, FixedTrait, ONE, comp};

    use influence::config;
    use influence::common::math::RoundedDivTrait;
    use influence::components::crew::CrewTrait;
    use influence::types::{ArrayHashTrait, Entity, EntityTrait, InventoryItem, InventoryItemTrait};

    // Returns the inputs required for the given process and # of recipes
    // @param process_inputs: the inputs of the process
    // @param recipes: the # of recipes to process (in Fixed mag)
    fn inputs(process_inputs: Span<InventoryItem>, recipes: Fixed) -> Span<InventoryItem> {
        let mut inputs: Array<InventoryItem> = Default::default();
        let mut iter = 0;

        loop {
            if iter >= process_inputs.len() { break; }
            let process_input = *process_inputs.at(iter);
            inputs.append(InventoryItem {
                product: process_input.product,
                amount: (recipes.mag * process_input.amount.into()).div_ceil(ONE)
            });

            iter += 1;
        };

        return inputs.span();
    }

    // Returns the outputs required for the given process, output target, and # of recipes
    // @param process_outputs: the outputs of the process
    // @param target: the product to focus on
    // @param recipes: the # of recipes to process (in Fixed mag)
    // @param secondary_mod: the modifier to apply to secondary products
    fn outputs(
        process_outputs: Span<InventoryItem>,
        target: u64,
        recipes: Fixed,
        secondary_mod: Fixed
    ) -> Span<InventoryItem> {
        let mut outputs: Array<InventoryItem> = Default::default();
        let mut iter = 0;
        let mut output_found = false;
        let secondary_adjust = comp::max(
            FixedTrait::ONE() - (FixedTrait::new(1610612736, false) / secondary_mod),
            FixedTrait::ZERO()
        );

        loop {
            if iter >= process_outputs.len() { break; }
            let process_output = *process_outputs.at(iter);
            let mut amount = 0;

            if process_output.product == target {
                amount = (recipes.mag * process_output.amount.into()).div_floor(ONE);
                output_found = true;
            } else {
                amount = ((recipes * secondary_adjust).mag * process_output.amount.into()).div_floor(ONE);
            }

            outputs.append(InventoryItem { product: process_output.product, amount: amount });
            iter += 1;
        };

        assert(output_found, 'invalid output');
        return outputs.span();
    }

    // Calculates the total IRL time required for a process
    // @param setup_time: in-game milliseconds required to set up the process
    // @param recipe_time: in-game milliseconds required to process a single recipe
    // @param batched: whether the process is batched
    // @param process_eff: the efficiency of the crew
    fn time(setup_time: u64, recipe_time: u64, batched: bool, mut recipes: Fixed, process_eff: Fixed) -> (u64,  u64) {
        if batched { recipes = recipes.ceil(); }

        let div: u64 = config::get('TIME_ACCELERATION').try_into().unwrap() * process_eff.mag.into();
        let setup_irl = FixedTrait::new_unscaled(setup_time.into(), false) / FixedTrait::new(div, false);
        let var_num: u128 = recipes.mag.into() * recipe_time.into();
        let variable_irl: u64 = var_num.div_ceil(div.into() * 1000).try_into().unwrap();

        return (setup_irl.ceil().try_into().unwrap(), variable_irl);
    }
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use traits::{Into, TryInto};

    use cubit::f64::FixedTrait;

    use influence::components;
    use influence::common::{config, inventory};
    use influence::components::{Crew, CrewTrait, Inventory, InventoryTrait, Location, LocationTrait, Station,
        dry_dock_type::types as dry_dock_types,
        modifier_type::types as modifier_types,
        process_type::types as process_types,
        product_type::types as product_types,
        deposit::{statuses as deposit_statuses, Deposit, DepositTrait},
        dry_dock::{statuses as dry_dock_statuses, DryDock, DryDockTrait},
        extractor::{statuses as extractor_statuses, Extractor, ExtractorTrait},
        processor::{statuses as processor_statuses, types as processor_types, Processor, ProcessorTrait},
        ship::{statuses as ship_statuses, Ship, ShipTrait},
        ship_type::types as ship_types
    };
    use influence::config::entities;
    use influence::contracts::ship::{IShipDispatcher, IShipDispatcherTrait};
    use influence::types::{Entity, EntityTrait, InventoryItem, InventoryItemTrait, InventoryContentsTrait};
    use influence::test::{helpers, mocks};

    use super::{
        AssembleShipStart,
        AssembleShipFinish,
        ExtractResourceStart,
        ExtractResourceFinish,
        ProcessProductsStart,
        ProcessProductsFinish,
        helpers::{inputs, outputs, time}
    };

    #[test]
    #[available_gas(500000)]
    fn test_input() {
        let inputs = array![
            InventoryItem { product: 1, amount: 3 },
            InventoryItem { product: 2, amount: 4 },
            InventoryItem { product: 3, amount: 3 }
        ].span();
        let actual = inputs(inputs, FixedTrait::new(45097156608, false)); // 10.5

        assert(*actual.at(0).amount == 32, 'incorrect amount');
        assert(*actual.at(1).amount == 42, 'incorrect amount');
        assert(*actual.at(2).amount == 32, 'incorrect amount');
    }

    #[test]
    #[available_gas(500000)]
    fn test_outputs() {
        let outputs = array![
            InventoryItem { product: 1, amount: 3 },
            InventoryItem { product: 2, amount: 4 },
            InventoryItem { product: 3, amount: 3 }
        ].span();

        let secondary_mod = FixedTrait::new(6442450944, false); // 1.5
        let actual = outputs(outputs, 2, FixedTrait::new(45097156608, false), secondary_mod); // 10.5

        assert(*actual.at(0).amount == 23, 'incorrect amount');
        assert(*actual.at(1).amount == 42, 'incorrect amount');
        assert(*actual.at(2).amount == 23, 'incorrect amount');
    }

    #[test]
    #[available_gas(500000)]
    #[should_panic(expected: ('invalid output', ))]
    fn test_invalid_output() {
        let outputs = array![
            InventoryItem { product: 1, amount: 3 },
            InventoryItem { product: 2, amount: 4 },
            InventoryItem { product: 3, amount: 3 }
        ].span();

        let secondary_mod = FixedTrait::new(6442450944, false); // 1.5
        let actual = outputs(outputs, 4, FixedTrait::new(45097156608, false), secondary_mod); // 10.5
    }

    #[test]
    #[available_gas(750000)]
    fn test_time() {
        helpers::init();
        config::set('TIME_ACCELERATION', 24);

        let (mut setup_time, mut var_time) = time(
            24000, 24000000, false, FixedTrait::new_unscaled(2, false), FixedTrait::new_unscaled(1, false)
        );
        assert(setup_time + var_time == 3000, 'incorrect time');

        let (mut setup_time, mut var_time) = time(
            24000, 24000000, false, FixedTrait::new(10737418240, false), FixedTrait::new_unscaled(1, false)
        ); // 2.5
        assert(setup_time + var_time == 3500, 'incorrect time');

        let (mut setup_time, mut var_time) = time(
            24000, 24000000, true, FixedTrait::new(10737418240, false), FixedTrait::new_unscaled(1, false)
        ); // 2.5
        assert(setup_time + var_time == 4000, 'incorrect time');

        let (mut setup_time, mut var_time) = time(
            24000, 24000000, false, FixedTrait::new(10737418240, false), FixedTrait::new(6442450944, false)
        ); // 2.5 & 1.5
        assert(setup_time + var_time == 2334, 'incorrect time');
    }

    // Benchmark: 42k steps for start + finish (210 gas)

    #[test]
    #[available_gas(36000000)]
    fn test_extraction() {
        helpers::init();
        mocks::constants();

        let asteroid = influence::test::mocks::asteroid();
        let crew = influence::test::mocks::delegated_crew(1, 'PLAYER');

        // Setup modifiers
        mocks::modifier_type(modifier_types::EXTRACTION_TIME);
        mocks::modifier_type(modifier_types::HOPPER_TRANSPORT_TIME);
        mocks::modifier_type(modifier_types::FREE_TRANSPORT_DISTANCE);
        mocks::modifier_type(modifier_types::INVENTORY_MASS_CAPACITY);
        mocks::modifier_type(modifier_types::INVENTORY_VOLUME_CAPACITY);

        // Setup product configs
        mocks::product_type(product_types::WATER);

        // Setup station
        let station = influence::test::mocks::public_habitat(crew, 1);
        components::set::<Location>(station.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1)));
        components::set::<Location>(crew.path(), LocationTrait::new(station));

        // Setup warehouse
        let warehouse = influence::test::mocks::public_warehouse(crew, 3);
        components::set::<Location>(warehouse.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1000)));

        // Create extractor
        let extractor = influence::test::mocks::public_extractor(crew, 4);
        components::set::<Location>(extractor.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 500)));

        // Create deposit
        let deposit = influence::test::mocks::controlled_deposit(crew, 1, product_types::WATER);
        components::set::<Location>(deposit.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 500)));

        let mut start_state = ExtractResourceStart::contract_state_for_testing();
        ExtractResourceStart::run(
            ref start_state,
            deposit: deposit,
            yield: 500000,
            extractor: extractor,
            extractor_slot: 1,
            destination: warehouse,
            destination_slot: 2,
            caller_crew: crew,
            context: mocks::context('PLAYER')
        ); // 31k

        // Check that the extractor and deposit are updated
        let extractor_path = array![extractor.into(), 1].span();
        let mut extractor_data = components::get::<Extractor>(extractor_path).unwrap();
        assert(extractor_data.status == extractor_statuses::RUNNING, 'extractor status');
        assert(extractor_data.output_product == product_types::WATER, 'extractor output product');
        assert(extractor_data.yield == 500000, 'extractor yield');
        assert(extractor_data.finish_time > 0, 'extractor finish time');

        let mut deposit_data = components::get::<Deposit>(deposit.path()).unwrap();
        assert(deposit_data.status == deposit_statuses::USED, 'deposit status');
        assert(deposit_data.remaining_yield == 500000, 'deposit remaining yield');

        // Update timings
        starknet::testing::set_block_timestamp(250000);

        // Finish the extraction
        let mut finish_state = ExtractResourceFinish::contract_state_for_testing();
        ExtractResourceFinish::run(
            ref finish_state,
            extractor: extractor,
            extractor_slot: 1,
            caller_crew: crew,
            context: mocks::context('PLAYER')
        ); // 11k

        // Check that the extractor is reset
        extractor_data = components::get::<Extractor>(extractor_path).unwrap();
        assert(extractor_data.status == extractor_statuses::IDLE, 'extractor status');
        assert(extractor_data.output_product == 0, 'extractor output product');
        assert(extractor_data.yield == 0, 'extractor yield');

        // Check destination inventory
        let mut destination_path = array![warehouse.into(), 2].span();
        let mut destination_data = components::get::<Inventory>(destination_path).unwrap();
        assert(destination_data.contents.amount_of(product_types::WATER) == 500000, 'destination product');
    }

    // Benchmark: 56k steps for start + finish (280 gas)

    #[test]
    #[available_gas(46000000)]
    fn test_process_products() {
        helpers::init();
        mocks::constants();

        let asteroid = influence::test::mocks::asteroid();
        let crew = influence::test::mocks::delegated_crew(1, 'PLAYER');

        // Setup modifiers
        mocks::modifier_type(modifier_types::SECONDARY_REFINING_YIELD);
        mocks::modifier_type(modifier_types::INVENTORY_MASS_CAPACITY);
        mocks::modifier_type(modifier_types::INVENTORY_VOLUME_CAPACITY);
        mocks::modifier_type(modifier_types::HOPPER_TRANSPORT_TIME);
        mocks::modifier_type(modifier_types::FREE_TRANSPORT_DISTANCE);
        mocks::modifier_type(modifier_types::REFINING_TIME);
        mocks::modifier_type(modifier_types::MANUFACTURING_TIME);

        // Setup product configs
        mocks::product_type(product_types::HYDROGEN);
        mocks::product_type(product_types::AMMONIA);
        mocks::product_type(product_types::PURE_NITROGEN);

        // Setup station
        let station = influence::test::mocks::public_habitat(crew, 1);
        components::set::<Location>(station.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1)));
        components::set::<Location>(crew.path(), LocationTrait::new(station));

        // Setup refinery
        let refinery = influence::test::mocks::public_refinery(crew, 2);
        components::set::<Location>(refinery.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 500)));

        // Setup warehouse
        let warehouse = influence::test::mocks::public_warehouse(crew, 3);
        components::set::<Location>(warehouse.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1000)));
        let inventory_path = array![warehouse.into(), 2].span();
        let mut inventory_data = components::get::<Inventory>(inventory_path).unwrap();
        let supplies = array![InventoryItemTrait::new(product_types::AMMONIA, 50000)].span();

        inventory::add_unchecked(ref inventory_data, supplies);
        components::set::<Inventory>(inventory_path, inventory_data);
        mocks::process_type(process_types::AMMONIA_CATALYTIC_CRACKING);

        let mut state = ProcessProductsStart::contract_state_for_testing();
        ProcessProductsStart::run(
            ref state,
            processor: refinery,
            processor_slot: 1,
            process: process_types::AMMONIA_CATALYTIC_CRACKING,
            target_output: product_types::HYDROGEN,
            recipes: FixedTrait::new_unscaled(1000, false),
            origin: warehouse,
            origin_slot: 2,
            destination: warehouse,
            destination_slot: 2,
            caller_crew: crew,
            context: mocks::context('PLAYER')
        ); // 67.6k steps

        // Check inventory
        inventory_data = components::get::<Inventory>(inventory_path).unwrap();
        assert((*inventory_data.contents.at(0)).product == product_types::AMMONIA, 'incorrect product');
        assert((*inventory_data.contents.at(0)).amount == 10000, 'incorrect amount');

        // Check processor
        let processor_path = array![refinery.into(), 1].span();
        let mut processor_data = components::get::<Processor>(processor_path).unwrap();
        assert(processor_data.status == processor_statuses::RUNNING, 'incorrect status');
        assert(processor_data.running_process == process_types::AMMONIA_CATALYTIC_CRACKING, 'incorrect process');
        assert(processor_data.output_product == product_types::HYDROGEN, 'incorrect output');
        let finish_time = starknet::get_block_timestamp() + processor_data.finish_time + 1;

        // Finish processing
        starknet::testing::set_block_timestamp(finish_time);
        let mut state = ProcessProductsFinish::contract_state_for_testing();
        ProcessProductsFinish::run(
            ref state,
            processor: refinery,
            processor_slot: 1,
            caller_crew: crew,
            context: mocks::context('PLAYER')
        ); // 28.7k steps

        // Check inventory
        inventory_data = components::get::<Inventory>(inventory_path).unwrap();
        assert(inventory_data.amount_of(product_types::HYDROGEN) == 6000, 'incorrect amount');
        assert(inventory_data.amount_of(product_types::PURE_NITROGEN) == 8500, 'incorrect amount');
        assert(inventory_data.reserved_mass == 0, 'incorrect amount');
        assert(inventory_data.reserved_volume == 0, 'incorrect amount');

        processor_data = components::get::<Processor>(processor_path).unwrap();
        assert(processor_data.status == processor_statuses::IDLE, 'incorrect status');
    }

    #[test]
    #[available_gas(50000000)]
    fn test_ship_assembly() {
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        helpers::init();
        mocks::constants();
        let ship_address = helpers::deploy_ship();

        starknet::testing::set_contract_address(starknet::contract_address_const::<'ADMIN'>());
        IShipDispatcher { contract_address: ship_address }
            .add_grant(starknet::contract_address_const::<'DISPATCHER'>(), 2);

        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        let asteroid = influence::test::mocks::asteroid();
        let crew = influence::test::mocks::delegated_crew(1, 'PLAYER');

        // Setup modifiers
        mocks::modifier_type(modifier_types::HOPPER_TRANSPORT_TIME);
        mocks::modifier_type(modifier_types::FREE_TRANSPORT_DISTANCE);
        mocks::modifier_type(modifier_types::SHIP_INTEGRATION_TIME);

        // Setup station
        let station = influence::test::mocks::public_habitat(crew, 1);
        components::set::<Location>(station.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1)));
        components::set::<Location>(crew.path(), LocationTrait::new(station));

        // Setup shipyard
        let shipyard = influence::test::mocks::public_shipyard(crew, 2);
        components::set::<Location>(shipyard.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 500)));

        // Store products
        mocks::product_type(product_types::SHUTTLE_HULL);
        mocks::product_type(product_types::AVIONICS_MODULE);
        mocks::product_type(product_types::ESCAPE_MODULE);
        mocks::product_type(product_types::ATTITUDE_CONTROL_MODULE);
        mocks::product_type(product_types::POWER_MODULE);
        mocks::product_type(product_types::THERMAL_MODULE);
        mocks::product_type(product_types::PROPULSION_MODULE);
        mocks::product_type(product_types::HYDROGEN_PROPELLANT);

        // Setup warehouse
        let warehouse = influence::test::mocks::public_warehouse(crew, 3);
        components::set::<Location>(warehouse.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1000)));
        let inventory_path = array![warehouse.into(), 2].span();
        let mut inventory_data = components::get::<Inventory>(inventory_path).unwrap();
        let supplies = array![
            InventoryItemTrait::new(product_types::SHUTTLE_HULL, 1),
            InventoryItemTrait::new(product_types::AVIONICS_MODULE, 1),
            InventoryItemTrait::new(product_types::ESCAPE_MODULE, 3),
            InventoryItemTrait::new(product_types::ATTITUDE_CONTROL_MODULE, 1),
            InventoryItemTrait::new(product_types::POWER_MODULE, 2),
            InventoryItemTrait::new(product_types::THERMAL_MODULE, 1),
            InventoryItemTrait::new(product_types::PROPULSION_MODULE, 1)
        ].span();
        inventory::add_unchecked(ref inventory_data, supplies);
        components::set::<Inventory>(inventory_path, inventory_data);
        mocks::process_type(process_types::SHUTTLE_INTEGRATION);
        mocks::ship_type(ship_types::SHUTTLE);

        let mut start_state = AssembleShipStart::contract_state_for_testing();
        AssembleShipStart::run(
            ref start_state,
            dry_dock: shipyard,
            dry_dock_slot: 1,
            ship_type: ship_types::SHUTTLE,
            origin: warehouse,
            origin_slot: 2,
            caller_crew: crew,
            context: mocks::context('PLAYER')
        );

        // Check inventory
        inventory_data = components::get::<Inventory>(inventory_path).unwrap();
        assert(inventory_data.mass == 0, 'incorrect amount');

        // Check dry dock and ship
        let dry_dock_path = array![shipyard.into(), 1].span();
        let mut dry_dock_data = components::get::<DryDock>(dry_dock_path).unwrap();
        assert(dry_dock_data.status == dry_dock_statuses::RUNNING, 'incorrect status');

        let ship = dry_dock_data.output_ship;
        let mut ship_data = components::get::<Ship>(ship.path()).unwrap();
        assert(ship_data.ship_type == ship_types::SHUTTLE, 'incorrect ship');

        let finish_time = starknet::get_block_timestamp() + dry_dock_data.finish_time + 1;

        // Finish processing
        starknet::testing::set_block_timestamp(finish_time);
        let spaceport = mocks::public_spaceport(crew, 4);
        components::set::<Location>(spaceport.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 750)));
        let mut finish_state = AssembleShipFinish::contract_state_for_testing();
        AssembleShipFinish::run(
            ref finish_state,
            dry_dock: shipyard,
            dry_dock_slot: 1,
            destination: spaceport,
            caller_crew: crew,
            context: mocks::context('PLAYER')
        );

        // Check dry dock and ship
        dry_dock_data = components::get::<DryDock>(dry_dock_path).unwrap();
        assert(dry_dock_data.status == dry_dock_statuses::IDLE, 'incorrect status');

        ship_data = components::get::<Ship>(ship.path()).unwrap();
        assert(ship_data.status == ship_statuses::AVAILABLE, 'incorrect status');
        assert(components::get::<Location>(ship.path()).unwrap().location == spaceport, 'incorrect location');
    }
}
