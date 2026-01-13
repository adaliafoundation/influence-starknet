// Places a construction site on a lot for a building and starts an exclusivity grace period

#[starknet::contract]
mod ConstructionPlan {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use starknet::contract_address::ContractAddress;
    use traits::{Into, TryInto};

    use influence::{components, config, entities::next_id};
    use influence::common::crew::CrewDetailsTrait;
    use influence::components::{Building, BuildingTrait, BuildingTypeTrait, Control, ControlTrait, Crew, CrewTrait,
        Location, LocationTrait, Unique, UniqueTrait,
        building_type::types as building_types,
        inventory_type::types as inventory_types,
        modifier_type::types as modifier_types,
        inventory::{Inventory, InventoryTrait}};
    use influence::config::{entities, errors, permissions};
    use influence::types::{Context, Entity, EntityTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct ConstructionPlanned {
        building: Entity,
        building_type: u64,
        asteroid: Entity,
        lot: Entity,
        grace_period_end: u64,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        ConstructionPlanned: ConstructionPlanned
    }

    #[external(v0)]
    fn run(ref self: ContractState, building_type: u64, lot: Entity, caller_crew: Entity, context: Context) {
        // Check that crew is delegated, and ready
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        let mut crew_data = crew_details.component;

        // Check that crew is on surface of asteroid
        let (lot_ast, lot_lot) = lot.to_position();
        assert(crew_details.asteroid_id() == lot_ast, errors::DIFFERENT_ASTEROIDS);
        assert(crew_details.lot_id() != 0, errors::IN_ORBIT);
        let asteroid = EntityTrait::new(entities::ASTEROID, lot_ast);

        // Check that a constructed building is not already present
        let mut lot_use_path: Array<felt252> = Default::default();
        lot_use_path.append('LotUse');
        lot_use_path.append(lot.into());
        assert(components::get::<Unique>(lot_use_path.span()).is_none(), errors::LOT_IN_USE);

        // Find if the caller is the lot user (or implied lot user as asteroid owner with no tenant present)
        let mut is_lot_user = false;
        let mut user_path: Array<felt252> = Default::default();
        user_path.append('UseLot');
        user_path.append(lot.into());

        match components::get::<Unique>(user_path.span()) {
            Option::Some(unique_data) => {
                is_lot_user = unique_data.unique.try_into().unwrap().can(lot, permissions::USE_LOT);
            },
            Option::None(_) => {
                is_lot_user = caller_crew.controls(asteroid);
            }
        };

        // Must control the lot (no more squatting allowed)
        assert(is_lot_user, errors::INCORRECT_CONTROLLER);
        crew_details.assert_all_but_ready(context.caller, context.now);

        // Update building
        let building = EntityTrait::new(entities::BUILDING, next_id(entities::BUILDING.into()));
        let building_data = BuildingTrait::new(building_type, context.now);
        components::set::<Building>(building.path(), building_data);
        components::set::<Unique>(lot_use_path.span(), Unique { unique: building.into() });

        // Update building location and controller
        components::set::<Location>(building.path(), LocationTrait::new(lot));
        components::set::<Control>(building.path(), ControlTrait::new(caller_crew));

        // Get the slot for the site inventory and create
        let config = BuildingTypeTrait::by_type(building_type);
        let mut site_path: Array<felt252> = Default::default();
        site_path.append(building.into());
        site_path.append(config.site_slot.into());
        components::set::<Inventory>(site_path.span(), InventoryTrait::new(config.site_type));

        self.emit(ConstructionPlanned {
            building: building,
            building_type: building_type,
            asteroid: asteroid,
            lot: lot,
            grace_period_end: context.now + config::get('CONSTRUCTION_GRACE_PERIOD').try_into().unwrap(),
            caller_crew: caller_crew,
            caller: context.caller
        });
    }
}
