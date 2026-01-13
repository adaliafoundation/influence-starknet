// Removes a construction site and allows a new one to be created

#[starknet::contract]
mod ConstructionAbandon {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use starknet::contract_address::ContractAddress;
    use traits::Into;

    use influence::{components, entities::next_id};
    use influence::common::crew::CrewDetailsTrait;
    use influence::components::{BuildingTypeTrait, Celestial, CelestialTrait, Control, ControlTrait, Inventory,
        InventoryTrait, Location, LocationTrait, Unique, UniqueTrait,
        building::{statuses as building_statuses, Building, BuildingTrait}};
    use influence::config::{entities, errors};
    use influence::systems::helpers::change_name;
    use influence::types::{Context, Entity, EntityTrait, String, StringTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct ConstructionAbandoned {
        building: Entity,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        ConstructionAbandoned: ConstructionAbandoned
    }

    #[external(v0)]
    fn run(ref self: ContractState, building: Entity, caller_crew: Entity, context: Context) {
        // Check that crew is delegated
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_delegated_to(context.caller);

        // Check permissions
        caller_crew.assert_controls(building);

        // Check that building is ready for deconstruction
        let mut building_data = components::get::<Building>(building.path()).expect(errors::BUILDING_NOT_FOUND);
        building_data.assert_planned();

        // Check that site inventory is empty
        let config = BuildingTypeTrait::by_type(building_data.building_type);

        let mut site_path: Array<felt252> = Default::default();
        site_path.append(building.into());
        site_path.append(config.site_slot.into());
        let inv_data = components::get::<Inventory>(site_path.span()).expect(errors::INVENTORY_NOT_FOUND);
        inv_data.assert_empty();

        // Update building
        building_data.status = building_statuses::UNPLANNED;
        components::set::<Building>(building.path(), building_data);

        // Update lot use
        let location_data = components::get::<Location>(building.path()).expect(errors::LOCATION_NOT_FOUND);
        let mut unique_path: Array<felt252> = Default::default();
        unique_path.append('LotUse');
        unique_path.append(location_data.location.into());
        components::set::<Unique>(unique_path.span(), Unique { unique: 0 });

        // Remove name / name uniqueness if necessary
        change_name(building, StringTrait::new(''));

        self.emit(ConstructionAbandoned {
            building: building,
            caller_crew: caller_crew,
            caller: context.caller
        });
    }
}
