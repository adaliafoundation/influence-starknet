#[starknet::contract]
mod ScanResourcesStart {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use starknet::ContractAddress;
    use traits::TryInto;

    use influence::{components, config};
    use influence::common::{crew::CrewDetailsTrait, random};
    use influence::components::{Crew, CrewTrait, Location, LocationTrait, Ship, ShipTrait,
        celestial, celestial::{statuses, Celestial, CelestialTrait}};
    use influence::systems::scanning::resource_commit_hash;
    use influence::types::{Context, Entity, EntityTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct ResourceScanStarted {
        asteroid: Entity,
        finish_time: u64,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        ResourceScanStarted: ResourceScanStarted
    }

    #[external(v0)]
    fn run(ref self: ContractState, asteroid: Entity, caller_crew: Entity, context: Context) {
        // Check that crew is delegated, and ready
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_all_ready(context.caller, context.now);
        let mut crew_data = crew_details.component;

        // Check if crew is present at asteroid and ready
        caller_crew.assert_controls(asteroid);
        let (crew_ast, _) = caller_crew.to_position();
        assert(crew_ast == asteroid.id, 'not at the same asteroid');

        // Check the asteroid is ready to scan / hasn't been already
        let mut celestial_data = components::get::<Celestial>(asteroid.path()).unwrap();
        assert(celestial_data.scan_status == statuses::SURFACE_SCANNED, 'invalid scan status');

        // Commit to future random round
        random::commit(resource_commit_hash(asteroid), 1);

        // Update crew ready at time
        let scan_time = config::get('SCANNING_TIME').try_into().unwrap() /
            config::get('TIME_ACCELERATION').try_into().unwrap();
        let finish_time = crew_data.busy_until(context.now) + scan_time;
        crew_data.ready_at = finish_time;
        components::set::<Crew>(caller_crew.path(), crew_data);

        let (station_ship, mut station_ship_data) = crew_details.ship();
        if caller_crew != station_ship {
            station_ship_data.extend_ready(crew_data.ready_at);
            components::set::<Ship>(station_ship.path(), station_ship_data);
        }

        // Record completion time in scans component
        celestial_data.scan_status = statuses::RESOURCE_SCANNING;
        celestial_data.scan_finish_time = finish_time;
        components::set::<Celestial>(asteroid.path(), celestial_data);
        self.emit(ResourceScanStarted {
            asteroid: asteroid,
            finish_time: finish_time,
            caller_crew: caller_crew,
            caller: context.caller
        });
    }
}
