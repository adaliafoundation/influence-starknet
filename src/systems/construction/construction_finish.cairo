// Completes the construction process and activates the new building

#[starknet::contract]
mod ConstructionFinish {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use starknet::contract_address::ContractAddress;
    use traits::{Into, TryInto};

    use influence::{components, entities::next_id};
    use influence::common::{crew::CrewDetailsTrait, math::RoundedDivTrait, position};
    use influence::components::{Celestial, CelestialTrait, Control, ControlTrait, Dock, DockTrait, DryDock,
        DryDockTrait, Exchange, ExchangeTrait, Station, StationTrait, Unique, UniqueTrait,
        building::{statuses as building_statuses, Building, BuildingTrait},
        building_type::types as building_types,
        dock_type::types as dock_types,
        dry_dock_type::types as dry_dock_types,
        exchange_type::types as exchange_types,
        extractor::{types as extractor_types, Extractor, ExtractorTrait},
        inventory_type::types as inventory_types,
        inventory::{statuses as inventory_statuses, Inventory, InventoryTrait},
        processor::{types as processor_types, Processor, ProcessorTrait},
        station_type::types as station_types};
    use influence::config::{entities, errors};
    use influence::types::{Context, Entity, EntityTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct ConstructionFinished {
        building: Entity,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        ConstructionFinished: ConstructionFinished
    }

    #[external(v0)]
    fn run(ref self: ContractState, building: Entity, caller_crew: Entity, context: Context) {
        // Check that crew is delegated, and ready
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_delegated_to(context.caller);

        // Check that building finish time is passed
        let mut building_data = components::get::<Building>(building.path()).expect(errors::BUILDING_NOT_FOUND);
        building_data.assert_completed(context.now);

        // Update building
        building_data.status = building_statuses::OPERATIONAL;
        components::set::<Building>(building.path(), building_data);

        // Update building specific components
        let mut path: Array<felt252> = Default::default();
        path.append(building.into());

        if building_data.building_type == building_types::WAREHOUSE {
            path.append(2); // inventory slot
            components::set::<Inventory>(path.span(), InventoryTrait::new(inventory_types::WAREHOUSE_PRIMARY));
        } else if building_data.building_type == building_types::EXTRACTOR {
            path.append(1); // extractor slot
            components::set::<Extractor>(path.span(), ExtractorTrait::new(extractor_types::BASIC));
        } else if building_data.building_type == building_types::REFINERY {
            path.append(1); // processor slot
            components::set::<Processor>(path.span(), ProcessorTrait::new(processor_types::REFINERY));
        } else if building_data.building_type == building_types::BIOREACTOR {
            path.append(1); // processor slot
            components::set::<Processor>(path.span(), ProcessorTrait::new(processor_types::BIOREACTOR));
        } else if building_data.building_type == building_types::FACTORY {
            path.append(1); // processor slot
            components::set::<Processor>(path.span(), ProcessorTrait::new(processor_types::FACTORY));
        } else if building_data.building_type == building_types::SHIPYARD {
            path.append(1); // dry dock & processor slot
            components::set::<Processor>(path.span(), ProcessorTrait::new(processor_types::SHIPYARD));
            components::set::<DryDock>(path.span(), DryDockTrait::new(dry_dock_types::BASIC));
        } else if building_data.building_type == building_types::SPACEPORT {
            components::set::<Dock>(path.span(), DockTrait::new(dock_types::BASIC));
        } else if building_data.building_type == building_types::MARKETPLACE {
            components::set::<Exchange>(path.span(), ExchangeTrait::new(exchange_types::BASIC));
        } else if building_data.building_type == building_types::HABITAT {
            components::set::<Station>(path.span(), StationTrait::new(station_types::HABITAT));
        } else if building_data.building_type == building_types::TANK_FARM {
            path.append(2); // inventory slot
            components::set::<Inventory>(path.span(), InventoryTrait::new(inventory_types::TANK_FARM_PRIMARY));
        }

        self.emit(ConstructionFinished {
            building: building,
            caller_crew: caller_crew,
            caller: context.caller
        });
    }
}
