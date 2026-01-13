#[starknet::contract]
mod ScanSurfaceStart {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use starknet::ContractAddress;
    use traits::{Into, TryInto};

    use influence::{components, config};
    use influence::common::{crew::CrewDetailsTrait, random};
    use influence::components::{celestial::{types, statuses, Celestial}};
    use influence::config::errors;
    use influence::systems::scanning::surface_commit_hash;
    use influence::types::{Context, Entity, EntityTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct SurfaceScanStarted {
        asteroid: Entity,
        finish_time: u64,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        SurfaceScanStarted: SurfaceScanStarted
    }

    #[external(v0)]
    fn run(ref self: ContractState, asteroid: Entity, caller_crew: Entity, context: Context) {
        // Check that crew is delegated, and ready
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_delegated_to(context.caller);
        crew_details.assert_manned();
        crew_details.assert_ready(context.now);
        crew_details.assert_not_in_emergency();
        crew_details.assert_building_operational();

        caller_crew.assert_controls(asteroid);

        // Check that asteroid is not yet scanned
        let mut celestial = components::get::<Celestial>(asteroid.path()).expect(errors::CELESTIAL_NOT_FOUND);
        assert(celestial.scan_status == statuses::UNSCANNED, errors::SCAN_ALREADY_STARTED);

        // Commit to hash and future time
        random::commit(surface_commit_hash(asteroid), 1);
        let scan_time = config::get('SCANNING_TIME').try_into().unwrap() /
            config::get('TIME_ACCELERATION').try_into().unwrap();
        let finish_time = starknet::get_block_timestamp() + scan_time;
        celestial.scan_status = statuses::SURFACE_SCANNING;
        celestial.scan_finish_time = finish_time;

        // Store data and emit
        components::set::<Celestial>(asteroid.path(), celestial);
        self.emit(SurfaceScanStarted {
            asteroid: asteroid,
            finish_time: finish_time,
            caller_crew: caller_crew,
            caller: context.caller
        });
    }
}