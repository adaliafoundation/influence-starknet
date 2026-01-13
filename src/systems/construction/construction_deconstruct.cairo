use influence::components::ship::ShipTrait;
// Deconstructs a building, deactivating it and returning a portion of the goods to the site
// - Schedulable

#[starknet::contract]
mod ConstructionDeconstruct {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use starknet::contract_address::ContractAddress;
    use traits::{Into, TryInto};

    use cubit::f64::FixedTrait;

    use influence::{components, config, entities::next_id};
    use influence::common::{crew::CrewDetailsTrait, inventory, math::RoundedDivTrait, position};
    use influence::components::{Celestial, CelestialTrait, Control, ControlTrait, Crew, CrewTrait, Dock, DockTrait,
        DryDock, DryDockTrait, Exchange, ExchangeTrait, Ship, ShipTrait, Station, StationTrait, Unique, UniqueTrait,
        building::{statuses as building_statuses, Building, BuildingTrait},
        building_type::{types as building_types, BuildingTypeTrait},
        dock_type::types as dock_types,
        dry_dock_type::types as dry_dock_types,
        exchange_type::types as exchange_types,
        modifier_type::types as modifier_types,
        inventory_type::types as inventory_types,
        station_type::types as station_types,
        extractor::{types as extractor_types, Extractor, ExtractorTrait},
        inventory::{statuses as inventory_statuses, Inventory, InventoryTrait},
        processor::{types as processor_types, Processor, ProcessorTrait}};
    use influence::config::{entities, errors};
    use influence::types::{Context, Entity, EntityTrait, InventoryItem, InventoryItemTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct ConstructionDeconstructed {
        building: Entity,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        ConstructionDeconstructed: ConstructionDeconstructed
    }

    #[external(v0)]
    fn run(ref self: ContractState, building: Entity, caller_crew: Entity, context: Context) {
        // Check that crew is delegated, and ready
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_all_ready_within(context.caller, context.now);
        let mut crew_data = crew_details.component;

        // Check permissions
        caller_crew.assert_controls(building);

        // Check that building has correct status
        let mut building_data = components::get::<Building>(building.path()).expect(errors::BUILDING_NOT_FOUND);
        building_data.assert_operational();

        // Check that the crew is in the right location
        let (building_ast, building_lot) = building.to_position();
        assert(crew_details.asteroid_id() == building_ast, errors::DIFFERENT_ASTEROIDS);
        assert(crew_details.lot_id() != 0, errors::IN_ORBIT);

        // Check that building modules aren't in use
        let mut path: Array<felt252> = Default::default();
        path.append(building.into());

        if building_data.building_type == building_types::WAREHOUSE {
            path.append(2); // inventory slot
            let mut inventory = components::get::<Inventory>(path.span()).expect(errors::INVENTORY_NOT_FOUND);
            inventory.assert_ready();
            inventory.assert_empty(); // TODO: allow even if space is reserved
            inventory.disable();
            components::set::<Inventory>(path.span(), inventory);
        } else if building_data.building_type == building_types::EXTRACTOR {
            path.append(1); // extractor slot
            let mut extractor = components::get::<Extractor>(path.span()).expect(errors::EXTRACTOR_NOT_FOUND);
            extractor.assert_ready();
            components::set::<Extractor>(path.span(), extractor);
        } else if building_data.building_type == building_types::REFINERY ||
            building_data.building_type == building_types::BIOREACTOR ||
            building_data.building_type == building_types::FACTORY {
            path.append(1); // processor slot
            let mut processor = components::get::<Processor>(path.span()).expect(errors::PROCESSOR_NOT_FOUND);
            processor.assert_ready();
            components::set::<Processor>(path.span(), processor);
        } else if building_data.building_type == building_types::SHIPYARD {
            path.append(1); // dry_dock and processor slot
            let mut processor = components::get::<Processor>(path.span()).expect(errors::PROCESSOR_NOT_FOUND);
            processor.assert_ready();
            components::set::<Processor>(path.span(), processor);
            let mut dry_dock = components::get::<DryDock>(path.span()).expect(errors::DRY_DOCK_NOT_FOUND);
            dry_dock.assert_ready(context.now);
            components::set::<DryDock>(path.span(), dry_dock);
        } else if building_data.building_type == building_types::SPACEPORT {
            let mut dock = components::get::<Dock>(path.span()).expect(errors::DOCK_NOT_FOUND);
        } else if building_data.building_type == building_types::MARKETPLACE {
            let exchange = components::get::<Exchange>(path.span()).expect(errors::EXCHANGE_NOT_FOUND);
        } else if building_data.building_type == building_types::HABITAT {
            let station = components::get::<Station>(path.span()).expect(errors::STATION_NOT_FOUND);
        } else if building_data.building_type == building_types::TANK_FARM {
            path.append(2); // inventory slot
            let mut inventory = components::get::<Inventory>(path.span()).expect(errors::INVENTORY_NOT_FOUND);
            inventory.assert_ready();
            inventory.assert_empty();
            inventory.disable();
            components::set::<Inventory>(path.span(), inventory);
        }

        // Calculate the hopper transfer times
        let hopper_eff = crew_details.bonus(modifier_types::HOPPER_TRANSPORT_TIME, context.now);
        let dist_eff = crew_details.bonus(modifier_types::FREE_TRANSPORT_DISTANCE, context.now);
        let asteroid = EntityTrait::new(entities::ASTEROID, building_ast);
        let celestial_data = components::get::<Celestial>(asteroid.path()).expect(errors::CELESTIAL_NOT_FOUND);
        let crew_to_lot = position::hopper_travel_time(
            crew_details.lot_id(), building_lot, celestial_data.radius, hopper_eff, dist_eff
        );

        // Update / unlock construction site inventory and reduce returned items
        let config = BuildingTypeTrait::by_type(building_data.building_type);
        let mut site_path: Array<felt252> = Default::default();
        site_path.append(building.into());
        site_path.append(config.site_slot.into());
        let mut inv_data = components::get::<Inventory>(site_path.span()).expect(errors::INVENTORY_NOT_FOUND);
        inv_data.status = inventory_statuses::AVAILABLE;

        // Return deconstructed items (reduced from original by 10%)
        let mut iter = 0;
        let mut to_remove: Array<InventoryItem> = Default::default();
        let deconstruct_eff = crew_details.bonus(modifier_types::DECONSTRUCTION_YIELD, context.now);
        let deconstruction_pen = config::get('DECONSTRUCTION_PENALTY').try_into().unwrap();
        let output_frac = FixedTrait::new(deconstruction_pen, false) / deconstruct_eff;

        loop {
            if iter >= inv_data.contents.len() { break; }
            let mut item = *inv_data.contents.at(iter);
            let amount: u64 = (FixedTrait::new_unscaled(item.amount, false) * output_frac).ceil().try_into().unwrap();
            to_remove.append(InventoryItemTrait::new(item.product, amount));
            iter += 1;
        };

        inventory::remove(ref inv_data, to_remove.span());
        components::set::<Inventory>(site_path.span(), inv_data);

        // Update building status
        building_data.status = building_statuses::PLANNED;
        building_data.planned_at = context.now;
        building_data.finish_time = 0;
        components::set::<Building>(building.path(), building_data);

        // Update crew & ship
        crew_data.add_busy(context.now, crew_to_lot * 2);
        components::set::<Crew>(caller_crew.path(), crew_data);

        let (station_ship, mut station_ship_data) = crew_details.ship();
        if caller_crew != station_ship {
            station_ship_data.extend_ready(crew_data.ready_at);
            components::set::<Ship>(station_ship.path(), station_ship_data);
        }

        self.emit(ConstructionDeconstructed {
            building: building,
            caller_crew: caller_crew,
            caller: context.caller
        });
    }
}
