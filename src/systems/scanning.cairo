mod scan_resources_start;
mod scan_resources_finish;
mod scan_surface_start;
mod scan_surface_finish;

use array::ArrayTrait;
use traits::Into;

use influence::types::{ArrayHashTrait, Entity, EntityTrait};

use scan_resources_start::ScanResourcesStart;
use scan_resources_finish::ScanResourcesFinish;
use scan_surface_start::ScanSurfaceStart;
use scan_surface_finish::ScanSurfaceFinish;

fn resource_commit_hash(asteroid: Entity) -> felt252 {
    return array!['ResourceScan', asteroid.label.into(), asteroid.id.into()].hash();
}

fn surface_commit_hash(asteroid: Entity) -> felt252 {
    return array!['SurfaceScan', asteroid.label.into(), asteroid.id.into()].hash();
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use array::ArrayTrait;
    use traits::Into;
    use option::OptionTrait;

    use influence::common::random;
    use influence::components;
    use influence::components::{Control, ControlTrait, Location, LocationTrait,
        celestial::{statuses, types, Celestial, CelestialTrait}, product_type::types as products
    };
    use influence::types::{ArrayHashTrait, Entity, EntityTrait};
    use influence::test::{helpers, mocks};

    use super::{ScanResourcesStart, ScanResourcesFinish, ScanSurfaceStart, ScanSurfaceFinish};

    // Benchmark 1: 51k steps for start + finish
    // Benchmark 2: 13k steps for start + finish

    #[test]
    #[available_gas(7000000)]
    fn test_scan_surface_start() {
        mocks::constants();
        let asteroid = mocks::asteroid();
        let crew = mocks::delegated_crew(1, 'PLAYER');
        components::set::<Location>(crew.path(), LocationTrait::new(asteroid));
        components::set::<Control>(asteroid.path(), ControlTrait::new(crew));

        let mut state = ScanSurfaceStart::contract_state_for_testing();
        ScanSurfaceStart::run(ref state, asteroid, crew, mocks::context('PLAYER'));
        let celestial_data = components::get::<Celestial>(asteroid.path()).unwrap();
        assert(celestial_data.scan_status == statuses::SURFACE_SCANNING, 'scan not started');
    }

    #[test]
    #[available_gas(10000000)]
    #[should_panic(expected: ('E6008: scan already started', ))]
    fn test_already_started() {
        mocks::constants();
        let asteroid = mocks::asteroid();
        let crew = mocks::delegated_crew(1, 'PLAYER');
        components::set::<Location>(crew.path(), LocationTrait::new(asteroid));
        components::set::<Control>(asteroid.path(), ControlTrait::new(crew));

        let mut state = ScanSurfaceStart::contract_state_for_testing();
        ScanSurfaceStart::run(ref state, asteroid, crew, mocks::context('PLAYER'));
        ScanSurfaceStart::run(ref state, asteroid, crew, mocks::context('PLAYER'));
    }

    #[test]
    #[available_gas(10000000)]
    fn test_scan_surface_finish() {
        mocks::constants();
        let asteroid = mocks::asteroid();
        let crew = mocks::delegated_crew(1, 'PLAYER');
        components::set::<Location>(crew.path(), LocationTrait::new(asteroid));
        components::set::<Control>(asteroid.path(), ControlTrait::new(crew));

        let mut context = mocks::context('PLAYER');
        let mut state = ScanSurfaceStart::contract_state_for_testing();
        ScanSurfaceStart::run(ref state, asteroid, crew, context);

        starknet::testing::set_block_timestamp(3601);
        context.now = 3601;

        random::entropy::generate();
        let mut state = ScanSurfaceFinish::contract_state_for_testing();
        ScanSurfaceFinish::run(ref state, asteroid, crew, context);
        let celestial_data = components::get::<Celestial>(asteroid.path()).unwrap();
        assert(celestial_data.scan_status == statuses::SURFACE_SCANNED, 'scan not finished');
        assert(celestial_data.bonuses > 1, 'bonuses not generated');
    }

    #[test]
    #[available_gas(10000000)]
    #[should_panic(expected: ('scan not started', ))]
    fn test_not_started() {
        mocks::constants();
        let asteroid = mocks::asteroid();
        let crew = mocks::delegated_crew(1, 'PLAYER');
        components::set::<Location>(crew.path(), LocationTrait::new(asteroid));
        components::set::<Control>(asteroid.path(), ControlTrait::new(crew));

        let mut context = mocks::context('PLAYER');
        starknet::testing::set_block_timestamp(3601);
        context.now = 3601;

        random::entropy::generate();
        let mut state = ScanSurfaceFinish::contract_state_for_testing();
        ScanSurfaceFinish::run(ref state, asteroid, crew, context);
    }

    #[test]
    #[available_gas(10000000)]
    #[should_panic(expected: ('scan not finished', ))]
    fn test_not_ready() {
        mocks::constants();
        let asteroid = mocks::asteroid();
        let crew = mocks::delegated_crew(1, 'PLAYER');
        components::set::<Location>(crew.path(), LocationTrait::new(asteroid));
        components::set::<Control>(asteroid.path(), ControlTrait::new(crew));

        let mut context = mocks::context('PLAYER');
        let mut state = ScanSurfaceStart::contract_state_for_testing();
        ScanSurfaceStart::run(ref state, asteroid, crew, context);

        starknet::testing::set_block_timestamp(3500);
        context.now = 3500;

        random::entropy::generate();
        let mut state = ScanSurfaceFinish::contract_state_for_testing();
        ScanSurfaceFinish::run(ref state, asteroid, crew, context);
    }

    // Benchmark 1: 162k steps for start + finish
    // Benchmark 2: 105k steps for start + finish

    #[test]
    #[available_gas(14000000)]
    fn test_scan_resources_start() {
        mocks::constants();
        let asteroid = mocks::asteroid();
        let crew = mocks::delegated_crew(1, 'PLAYER');
        components::set::<Control>(asteroid.path(), ControlTrait::new(crew));
        components::set::<Location>(crew.path(), LocationTrait::new(asteroid)); // cheat a bit on position without a ship

        let mut context = mocks::context('PLAYER');
        let mut state = ScanSurfaceStart::contract_state_for_testing();
        ScanSurfaceStart::run(ref state, asteroid, crew, context);

        starknet::testing::set_block_timestamp(3601);
        context.now = 3601;
        random::entropy::generate();

        let mut state = ScanSurfaceFinish::contract_state_for_testing();
        ScanSurfaceFinish::run(ref state, asteroid, crew, context);
        let mut state = ScanResourcesStart::contract_state_for_testing();
        ScanResourcesStart::run(ref state, asteroid, crew, context);

        let celestial_data = components::get::<Celestial>(asteroid.path()).unwrap();
        assert(celestial_data.scan_status == statuses::RESOURCE_SCANNING, 'scan not running');
    }

    #[test]
    #[available_gas(25000000)]
    fn test_scan_resources_finish() {
        mocks::constants();
        let asteroid = mocks::asteroid();
        let crew = mocks::delegated_crew(1, 'PLAYER');
        components::set::<Control>(asteroid.path(), ControlTrait::new(crew));
        components::set::<Location>(crew.path(), LocationTrait::new(asteroid)); // cheat a bit on position without a ship

        let mut context = mocks::context('PLAYER');
        let mut state = ScanSurfaceStart::contract_state_for_testing();
        ScanSurfaceStart::run(ref state, asteroid, crew, context);

        starknet::testing::set_block_timestamp(3601);
        context.now = 3601;
        random::entropy::generate();

        let mut state = ScanSurfaceFinish::contract_state_for_testing();
        ScanSurfaceFinish::run(ref state, asteroid, crew, context);
        let mut state = ScanResourcesStart::contract_state_for_testing();
        ScanResourcesStart::run(ref state, asteroid, crew, context);

        starknet::testing::set_block_timestamp(7500);
        context.now = 7500;
        random::entropy::generate();

        let mut state = ScanResourcesFinish::contract_state_for_testing();
        ScanResourcesFinish::run(ref state, asteroid, crew, context);

        let celestial_data = components::get::<Celestial>(asteroid.path()).unwrap();
        assert(celestial_data.scan_status == statuses::RESOURCE_SCANNED, 'scan not complete');
        assert(celestial_data.abundances != 0, 'no resources found');
    }
}
