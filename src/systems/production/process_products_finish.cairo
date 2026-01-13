#[starknet::contract]
mod ProcessProductsFinish {
    use array::{Array, ArrayTrait};
    use option::OptionTrait;
    use starknet::contract_address::ContractAddress;
    use traits::Into;

    use cubit::f64::FixedTrait;

    use influence::components;
    use influence::common::{inventory, crew::CrewDetailsTrait};
    use influence::components::{BuildingTypeTrait, Celestial, Inventory, InventoryTrait, Location, LocationTrait,
        ProcessTypeTrait, Processor, ProcessorTrait, Ship, ShipTrait,
        building::{statuses as building_statuses, Building, BuildingTrait},
        product_type::{types as products}};
    use influence::config::{entities, errors};
    use influence::systems::production;
    use influence::types::{Context, Entity, EntityTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct MaterialProcessingFinished {
        processor: Entity,
        processor_slot: u64,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        MaterialProcessingFinished: MaterialProcessingFinished
    }

    #[external(v0)]
    fn run(ref self: ContractState, processor: Entity, processor_slot: u64, caller_crew: Entity, context: Context) {
        // Check that crew is delegated, and ready
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_delegated_to(context.caller);

        // Check that the processing slot is ready
        components::get::<Building>(processor.path()).expect(errors::BUILDING_NOT_FOUND).assert_operational();
        let mut processor_path: Array<felt252> = Default::default();
        processor_path.append(processor.into());
        processor_path.append(processor_slot.into());
        let mut processor_data = components::get::<Processor>(processor_path.span()).expect(errors::PROCESSOR_NOT_FOUND);
        processor_data.assert_finished(context.now);

        // Calculate outputs based on yield / config
        let process_config = ProcessTypeTrait::by_type(processor_data.running_process);
        let outputs = production::helpers::outputs(
            process_config.outputs, processor_data.output_product, processor_data.recipes, processor_data.secondary_eff
        );

        // Remove reservation on destination inventory and update contents
        let destination = processor_data.destination;

        if destination.label == entities::BUILDING {
            let building_data = components::get::<Building>(destination.path()).expect(errors::BUILDING_NOT_FOUND);
            let config = BuildingTypeTrait::by_type(building_data.building_type);
            let planning = building_data.status == building_statuses::PLANNED &&
                config.site_slot == processor_data.destination_slot;

            assert(planning || building_data.status == building_statuses::OPERATIONAL, 'inventory inaccessible');
        } else if destination.label == entities::SHIP {
            components::get::<Ship>(destination.path()).expect(errors::SHIP_NOT_FOUND).assert_stationary();
            let location = components::get::<Location>(destination.path()).expect(errors::LOCATION_NOT_FOUND);

            match components::get::<Building>(location.location.path()) {
                Option::Some(building_data) => building_data.assert_operational(),
                Option::None(_) => ()
            };
        }

        let mut inventory_path: Array<felt252> = Default::default();
        inventory_path.append(processor_data.destination.into());
        inventory_path.append(processor_data.destination_slot.into());
        let mut inventory_data = components::get::<Inventory>(inventory_path.span())
            .expect(errors::INVENTORY_NOT_FOUND);

        inventory::unreserve(ref inventory_data, outputs);
        inventory::add_unchecked(ref inventory_data, outputs);
        components::set::<Inventory>(inventory_path.span(), inventory_data);

        // Update processor slot
        processor_data.reset();
        components::set::<Processor>(processor_path.span(), processor_data);

        self.emit(MaterialProcessingFinished {
            processor: processor,
            processor_slot: processor_slot,
            caller_crew: caller_crew,
            caller: context.caller,
        });
    }
}
