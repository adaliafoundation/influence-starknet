#[starknet::contract]
mod ExtractResourceFinish {
    use array::{Array, ArrayTrait};
    use option::OptionTrait;
    use starknet::ContractAddress;
    use traits::{Into, TryInto};

    use influence::components;
    use influence::common::{inventory, math::RoundedDivTrait, position, random, crew::CrewDetailsTrait};
    use influence::components::{Building, BuildingTrait, Celestial, Inventory, InventoryTrait, Location, Ship,
        ShipTrait,
        extractor, extractor::{statuses as extractor_statuses, Extractor, ExtractorTrait}};
    use influence::config::{entities, errors, permissions};
    use influence::types::{Context, Entity, EntityTrait, InventoryItem, InventoryItemTrait, String, StringTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct ResourceExtractionFinished {
        extractor: Entity,
        extractor_slot: u64,
        resource: u64,
        yield: u64,
        destination: Entity,
        destination_slot: u64,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        ResourceExtractionFinished: ResourceExtractionFinished
    }

    #[external(v0)]
    fn run(ref self: ContractState, extractor: Entity, extractor_slot: u64, caller_crew: Entity, context: Context) {
        // Check that crew is delegated
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_delegated_to(context.caller);

        // Check that the extraction slot is finished
        components::get::<Building>(extractor.path()).expect(errors::BUILDING_NOT_FOUND).assert_operational();
        let mut extractor_path: Array<felt252> = Default::default();
        extractor_path.append(extractor.into());
        extractor_path.append(extractor_slot.into());
        let mut extractor_data = components::get::<Extractor>(extractor_path.span())
            .expect(errors::EXTRACTOR_NOT_FOUND);

        extractor_data.assert_finished(context.now);
        let resource = extractor_data.output_product;
        let yield = extractor_data.yield;

        // Check that the destination inventory exists and is ready to receive
        let destination = extractor_data.destination;

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

        // Get the actual inventory data
        let destination_slot = extractor_data.destination_slot;
        let mut destination_path: Array<felt252> = Default::default();
        destination_path.append(destination.into());
        destination_path.append(destination_slot.into());
        let mut destination_data = components::get::<Inventory>(destination_path.span())
            .expect(errors::INVENTORY_NOT_FOUND);

        // Remove reservation and add items to the inventory
        let mut items: Array<InventoryItem> = Default::default();
        items.append(InventoryItemTrait::new(resource, yield));
        inventory::unreserve(ref destination_data, items.span());
        inventory::add_unchecked(ref destination_data, items.span());
        components::set::<Inventory>(destination_path.span(), destination_data);

        // Update the extractor
        extractor_data.reset();
        components::set::<Extractor>(extractor_path.span(), extractor_data);

        self.emit(ResourceExtractionFinished {
            extractor: extractor,
            extractor_slot: extractor_slot,
            resource: resource,
            yield: yield,
            destination: destination,
            destination_slot: destination_slot,
            caller_crew: caller_crew,
            caller: context.caller
        });
    }
}
