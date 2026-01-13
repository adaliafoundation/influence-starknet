// Allows a crew which controls a lot to gain control of the building on the lot

#[starknet::contract]
mod RepossessBuilding {
    use array::{Array, ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use starknet::{contract_address_const, ContractAddress};
    use traits::{Into, TryInto};

    use influence::{components, config};
    use influence::common::crew::CrewDetailsTrait;
    use influence::components::{Control, ControlTrait, Location, LocationTrait, Unique,
        building::{statuses as building_statuses, Building, BuildingTrait}};
    use influence::config::{entities, errors, permissions};
    use influence::types::{Context, Entity, EntityTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct BuildingRepossessed {
        building: Entity,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        BuildingRepossessed: BuildingRepossessed
    }

    #[external(v0)]
    fn run(ref self: ContractState, building: Entity, caller_crew: Entity, context: Context) {
        // Check that crew is delegated, and ready
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_all_ready(context.caller, context.now);

        // Check crew location
        let (crew_ast, _) = caller_crew.to_position();
        let (building_ast, building_lot) = building.to_position();
        assert(crew_ast == building_ast, errors::DIFFERENT_ASTEROIDS);

        let mut building_data = components::get::<Building>(building.path()).expect(errors::BUILDING_NOT_FOUND);

        // Get current lot user
        let asteroid = EntityTrait::new(entities::ASTEROID, building_ast);
        let lot = EntityTrait::from_position(building_ast, building_lot);
        let mut unique_path: Array<felt252> = Default::default();
        unique_path.append('UseLot');
        unique_path.append(lot.into());
        let mut blocked_by_tenant = false;
        let mut is_current_tenant = false;

        match components::get::<Unique>(unique_path.span()) {
            Option::Some(unique_data) => {
                let tenant = unique_data.unique.try_into().unwrap();
                blocked_by_tenant = tenant.can(lot, permissions::USE_LOT) && tenant != caller_crew;
                is_current_tenant = tenant == caller_crew;
            },
            Option::None(_) => ()
        };

        if caller_crew.controls(asteroid) || is_current_tenant {
            // For the current controller, check if caller is not blocked by lot user
            assert(!blocked_by_tenant, 'blocked by lot user');
        } else {
            // If not the controller, check if caller is the current tenant
            assert(building_data.status == building_statuses::PLANNED, 'not planned status');
            let grace_period = config::get('CONSTRUCTION_GRACE_PERIOD').try_into().unwrap();
            assert(context.now >= building_data.planned_at + grace_period, 'in grace period');
        }

        if building_data.status == building_statuses::PLANNED {
            building_data.planned_at = context.now;
            components::set::<Building>(building.path(), building_data);
        }

        components::set::<Control>(building.path(), ControlTrait::new(caller_crew));
        self.emit(BuildingRepossessed {
            building: building,
            caller_crew: caller_crew,
            caller: context.caller
        });
    }
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use array::{Array, ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use traits::{Into, TryInto};
    use starknet::testing;

    use influence::components;
    use influence::components::{Control, ControlTrait, Location, LocationTrait, Unique, WhitelistAgreement,
        WhitelistAgreementTrait};
    use influence::config::{entities, permissions};
    use influence::systems::agreements::helpers::agreement_path;
    use influence::types::entity::EntityTrait;
    use influence::test::{helpers, mocks};

    use super::RepossessBuilding;

    #[test]
    #[available_gas(15000000)]
    fn test_repossess_building() {
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        helpers::init();
        let asteroid = mocks::adalia_prime();

        let crew1 = influence::test::mocks::delegated_crew(1, 'PLAYER');
        let refinery = mocks::public_refinery(crew1, 1);
        let lot = EntityTrait::from_position(1, 1);
        components::set::<Location>(refinery.path(), LocationTrait::new(lot));

        let caller_crew = influence::test::mocks::delegated_crew(2, 'PLAYER');
        components::set::<Control>(asteroid.path(), ControlTrait::new(caller_crew));
        components::set::<Location>(caller_crew.path(), LocationTrait::new(lot));

        let mut state = RepossessBuilding::contract_state_for_testing();
        RepossessBuilding::run(ref state, refinery, caller_crew, mocks::context('PLAYER'));

        let control_data = components::get::<Control>(refinery.path()).expect('control not set');
        assert(control_data.controller == caller_crew, 'control not transferred');
    }

    #[test]
    #[available_gas(16000000)]
    fn test_repossess_building_as_tenant() {
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        helpers::init();
        let asteroid = mocks::adalia_prime();
        let asteroid_controller = influence::test::mocks::delegated_crew(42, 'OTHER_PLAYER');
        components::set::<Control>(asteroid.path(), ControlTrait::new(asteroid_controller));

        let crew1 = influence::test::mocks::delegated_crew(1, 'PLAYER');
        let refinery = mocks::public_refinery(crew1, 1);
        let lot = EntityTrait::from_position(1, 1);
        components::set::<Location>(refinery.path(), LocationTrait::new(lot));

        let caller_crew = influence::test::mocks::delegated_crew(2, 'PLAYER');
        let path = agreement_path(lot, permissions::USE_LOT, caller_crew.into());
        components::set::<WhitelistAgreement>(path, WhitelistAgreementTrait::new(true));
        let mut unique_path: Array<felt252> = Default::default();
        unique_path.append('UseLot');
        unique_path.append(lot.into());
        components::set::<Unique>(unique_path.span(), Unique { unique: caller_crew.into() });
        components::set::<Location>(caller_crew.path(), LocationTrait::new(lot));

        let mut state = RepossessBuilding::contract_state_for_testing();
        RepossessBuilding::run(ref state, refinery, caller_crew, mocks::context('PLAYER'));

        let control_data = components::get::<Control>(refinery.path()).expect('control not set');
        assert(control_data.controller == caller_crew, 'control not transferred');
    }

    #[test]
    #[available_gas(15000000)]
    #[should_panic(expected: ('not planned status', ))]
    fn test_repossess_building_fail() {
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        helpers::init();
        mocks::adalia_prime();

        let crew1 = influence::test::mocks::delegated_crew(1, 'PLAYER');
        let refinery = mocks::public_refinery(crew1, 1);
        let lot = EntityTrait::from_position(1, 1768484);
        components::set::<Control>(lot.path(), ControlTrait::new(crew1));
        components::set::<Location>(refinery.path(), LocationTrait::new(lot));

        let caller_crew = influence::test::mocks::delegated_crew(2, 'PLAYER');
        components::set::<Location>(caller_crew.path(), LocationTrait::new(lot));

        let mut state = RepossessBuilding::contract_state_for_testing();
        RepossessBuilding::run(ref state, refinery, caller_crew, mocks::context('PLAYER'));
    }
}
