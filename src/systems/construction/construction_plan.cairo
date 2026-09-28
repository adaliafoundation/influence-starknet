// Places a construction site on a lot for a building and starts an exclusivity grace period

#[starknet::contract]
mod ConstructionPlan {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use starknet::contract_address::ContractAddress;
    use traits::{Into, TryInto};

    use influence::{components, config, entities::next_id};
    use influence::common::crew::CrewDetailsTrait;
    use influence::common::lot_access::lot_access;
    use influence::components::{Building, BuildingTrait, BuildingTypeTrait, Control, ControlTrait, Crew, CrewTrait,
        Location, LocationTrait, Unique, UniqueTrait,
        building_type::types as building_types,
        inventory_type::types as inventory_types,
        modifier_type::types as modifier_types,
        inventory::{Inventory, InventoryTrait}};
    use influence::config::{entities, errors, permissions};
    use influence::systems::agreements::helpers::use_lot_path;
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
        let mut _crew_data = crew_details.component;

        // Check that crew is on surface of asteroid
        let (lot_ast, _lot_lot) = lot.to_position();
        assert(crew_details.asteroid_id() == lot_ast, errors::DIFFERENT_ASTEROIDS);
        assert(crew_details.lot_id() != 0, errors::IN_ORBIT);
        let asteroid = EntityTrait::new(entities::ASTEROID, lot_ast);

        // Check that a constructed building is not already present
        let mut lot_use_path: Array<felt252> = Default::default();
        lot_use_path.append('LotUse');
        lot_use_path.append(lot.into());
        assert(components::get::<Unique>(lot_use_path.span()).is_none(), errors::LOT_IN_USE);

        let access = lot_access(caller_crew, lot);
        assert(access.allowed, errors::INCORRECT_CONTROLLER);
        crew_details.assert_all_but_ready(context.caller, context.now);

        // Historical tenancy must not grant rights over a newly authorized crew's building.
        if access.stale_tenant {
            components::set::<Unique>(use_lot_path(lot), Unique { unique: 0 });
        }

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

#[cfg(test)]
mod tests {
    use option::OptionTrait;
    use traits::{Into, TryInto};

    use influence::components;
    use influence::components::{Control, ControlTrait, Location, LocationTrait, PrepaidAgreement,
        PrepaidAgreementTrait, Unique, building_type::types as building_types};
    use influence::config::permissions;
    use influence::systems::agreements::helpers::{agreement_path, lot_use_path, use_lot_path};
    use influence::test::{helpers, mocks};
    use influence::types::{Entity, EntityTrait};

    use super::ConstructionPlan;

    // Crew 1 controls the asteroid; crew 2 is the tenant; crew 3 is unrelated.
    fn plan_with_lease(caller_id: u64, agreement: Option<PrepaidAgreement>, now: u64) {
        helpers::init();
        mocks::constants();
        starknet::testing::set_block_timestamp(now);
        let asteroid = mocks::asteroid();
        let owner = mocks::delegated_crew(1, 'OWNER');
        let tenant = mocks::delegated_crew(2, 'TENANT');
        let stranger = mocks::delegated_crew(3, 'STRANGER');
        components::set::<Control>(asteroid.path(), ControlTrait::new(owner));
        let lot = EntityTrait::from_position(asteroid.id, 1001);
        match agreement {
            Option::Some(data) => {
                components::set::<Unique>(use_lot_path(lot), Unique { unique: tenant.into() });
                components::set::<PrepaidAgreement>(agreement_path(lot, permissions::USE_LOT, tenant.into()), data);
            },
            Option::None(_) => ()
        };
        let (caller, delegate) = if caller_id == 1 {
            (owner, 'OWNER')
        } else if caller_id == 2 {
            (tenant, 'TENANT')
        } else {
            (stranger, 'STRANGER')
        };
        components::set::<Location>(caller.path(), LocationTrait::new(lot));
        mocks::building_type(building_types::WAREHOUSE);

        let mut state = ConstructionPlan::contract_state_for_testing();
        ConstructionPlan::run(ref state, building_types::WAREHOUSE, lot, caller, mocks::context(delegate));

        let building: Entity = components::get::<Unique>(lot_use_path(lot)).expect('lot not occupied')
            .unique.try_into().unwrap();
        let control = components::get::<Control>(building.path()).expect('building control missing');
        assert(control.controller == caller, 'wrong building controller');
        if caller_id == 1 {
            assert(components::get::<Unique>(use_lot_path(lot)).is_none(), 'stale tenant retained');
        } else {
            assert(components::get::<Unique>(use_lot_path(lot)).unwrap().unique == tenant.into(), 'active tenant cleared');
        }
    }

    fn lease() -> Option<PrepaidAgreement> {
        Option::Some(PrepaidAgreementTrait::new(1, 100, 20, 1, 200))
    }

    fn cancelled_lease() -> Option<PrepaidAgreement> {
        let mut data = PrepaidAgreementTrait::new(1, 100, 20, 1, 170);
        data.notice_time = 150;
        Option::Some(data)
    }

    #[test]
    #[available_gas(30000000)]
    fn test_owner_never_leased() {
        plan_with_lease(1, Option::None(()), 201);
    }

    #[test]
    #[available_gas(30000000)]
    #[should_panic(expected: ('E2005: incorrect controller', ))]
    fn test_stranger_never_leased() {
        plan_with_lease(3, Option::None(()), 201);
    }

    #[test]
    #[available_gas(30000000)]
    fn test_owner_expired_lease() {
        plan_with_lease(1, lease(), 201);
    }

    #[test]
    #[available_gas(30000000)]
    #[should_panic(expected: ('E2005: incorrect controller', ))]
    fn test_former_tenant_expired_lease() {
        plan_with_lease(2, lease(), 201);
    }

    #[test]
    #[available_gas(30000000)]
    #[should_panic(expected: ('E2005: incorrect controller', ))]
    fn test_stranger_expired_lease() {
        plan_with_lease(3, lease(), 201);
    }

    #[test]
    #[available_gas(30000000)]
    fn test_active_tenant() {
        plan_with_lease(2, lease(), 200);
    }

    #[test]
    #[available_gas(30000000)]
    #[should_panic(expected: ('E2005: incorrect controller', ))]
    fn test_owner_active_lease() {
        plan_with_lease(1, lease(), 200);
    }

    #[test]
    #[available_gas(30000000)]
    #[should_panic(expected: ('E2005: incorrect controller', ))]
    fn test_stranger_active_lease() {
        plan_with_lease(3, lease(), 200);
    }

    #[test]
    #[available_gas(30000000)]
    fn test_owner_cancelled_lease() {
        plan_with_lease(1, cancelled_lease(), 171);
    }

    #[test]
    #[available_gas(30000000)]
    fn test_tenant_during_notice() {
        plan_with_lease(2, cancelled_lease(), 170);
    }

    #[test]
    #[available_gas(30000000)]
    #[should_panic(expected: ('E2005: incorrect controller', ))]
    fn test_owner_during_notice() {
        plan_with_lease(1, cancelled_lease(), 170);
    }

    #[test]
    #[available_gas(30000000)]
    #[should_panic(expected: ('E2005: incorrect controller', ))]
    fn test_former_tenant_cancelled_lease() {
        plan_with_lease(2, cancelled_lease(), 171);
    }

    #[test]
    #[available_gas(30000000)]
    #[should_panic(expected: ('E2005: incorrect controller', ))]
    fn test_stranger_cancelled_lease() {
        plan_with_lease(3, cancelled_lease(), 171);
    }
}
