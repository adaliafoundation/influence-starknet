#[starknet::contract]
mod TransitBetweenStart {
    use array::{ArrayTrait, SpanTrait};
    use cmp::max;
    use option::OptionTrait;
    use starknet::contract_address::ContractAddress;
    use traits::{Into, TryInto};

    use cubit::f64;
    use cubit::f128::{Fixed, FixedTrait, Vec3, Vec3Trait};

    use influence::{components, config};
    use influence::common::{crew::CrewDetailsTrait, inventory, math::RoundedDivTrait, position, propulsion,
        astro::{angles, elements, propagation, MU}};
    use influence::components::{Celestial, CelestialTrait, Crew, CrewTrait, Inventory, InventoryTrait, Location,
        LocationTrait, Orbit, OrbitTrait, ShipTypeTrait, ShipVariantTypeTrait,
        modifier_type::types as modifier_types,
        product_type::types as product_types,
        ship::{statuses as ship_statuses, Ship, ShipTrait}
    };
    use influence::config::{actions, entities, errors, permissions, EPOCH};
    use influence::types::{Context, Entity, EntityTrait, InventoryItem, InventoryItemTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct TransitStarted {
        ship: Entity, // ship
        origin: Entity, // origin asteroid
        destination: Entity, // destination asteroid
        departure: u64, // in-game time since EPOCH
        arrival: u64, // in-game time since EPOCH
        finish_time: u64, // timestamp
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        TransitStarted: TransitStarted
    }

    #[external(v0)]
    fn run(
        ref self: ContractState,
        origin: Entity, // origin asteroid
        destination: Entity, // destination asteroid
        departure_time: u64, // seconds since orbital EPOCH
        arrival_time: u64, // seconds since orbital EPOCH
        transit_p: Fixed, // transit solution Semi latus rectum in km
        transit_ecc: Fixed, // transit solution eccentricity
        transit_inc: Fixed, // transit solution inclination
        transit_raan: Fixed, // transit solution right ascension of ascending node
        transit_argp: Fixed, // transit solution argument of periapsis
        transit_nu_start: Fixed, // transit solution true anomaly (at departure time)
        transit_nu_end: Fixed, // transit solution true anomaly (at arrival time)
        caller_crew: Entity,
        context: Context
    ) {
        // Check that crew is delegated, and ready
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_delegated_to(context.caller);
        crew_details.assert_manned();
        crew_details.assert_ready(context.now);
        let mut crew_data = crew_details.component;

        // Check if crew is on ship it controls
        let (ship, mut ship_data) = crew_details.ship();
        caller_crew.assert_controls(ship);

        // Get ship data and ensure it is ready
        ship_data.assert_ready(context.now);
        let ship_config = ShipTypeTrait::by_type(ship_data.ship_type);

        // Check if ship is in orbit around origin asteroid
        let (ship_ast, ship_lot) = ship.to_position();
        assert(ship_ast == origin.id, errors::INCORRECT_ASTEROID);
        assert(ship_lot == 0, errors::NOT_IN_ORBIT);

        // Check that destination asteroid has been long-range scanned
        components::get::<Celestial>(destination.path()).expect(errors::CELESTIAL_NOT_FOUND).assert_surface_scanned();

        // Check that the ship has no inventory reservations (in case they were evicted from spaceport)
        let mut prop_path: Array<felt252> = Default::default();
        prop_path.append(ship.into());
        prop_path.append(ship_config.propellant_slot.into());
        let mut prop_inventory = components::get::<Inventory>(prop_path.span()).expect(errors::INVENTORY_NOT_FOUND);
        assert(prop_inventory.reserved_mass + prop_inventory.reserved_volume == 0, errors::DELIVERY_IN_PROGRESS);

        let mut cargo_path: Array<felt252> = Default::default();
        cargo_path.append(ship.into());
        cargo_path.append(ship_config.cargo_slot.into());
        match components::get::<Inventory>(cargo_path.span()) {
            Option::Some(cargo_data) => {
                assert(cargo_data.reserved_mass + cargo_data.reserved_volume == 0, errors::DELIVERY_IN_PROGRESS);
            },
            Option::None(_) => ()
        };

        // Check that times are valid
        let time_accel: u64 = config::get('TIME_ACCELERATION').try_into().unwrap();
        let irl_departure = EPOCH + departure_time.div_ceil(time_accel);
        let irl_arrival = EPOCH + arrival_time.div_ceil(time_accel);
        assert(irl_departure >= crew_data.busy_until(context.now), errors::DEPARTURE_TIME_IN_PAST);
        assert(irl_arrival > irl_departure, errors::ARRIVAL_TIME_TOO_EARLY);

        // Make sure the crew has enough food / check emergency mode
        let global_max: u64 = 47304000 / time_accel; // 1.5 years
        assert(irl_arrival - irl_departure <= global_max, errors::TRANSIT_OUT_OF_RANGE);

        // During regular flight, ensure crew isn't starving during flight
        if ship_data.emergency_at == 0 {
            let last_fed = max(crew_data.last_fed, config::get('LAUNCH_TIME').try_into().unwrap());
            assert(irl_arrival <= last_fed + global_max, errors::TRANSIT_OUT_OF_RANGE);
        }

        // Get orbit data and calculate origin position at departure time
        let one = FixedTrait::ONE();
        let thousand = FixedTrait::new(1000, false);
        let mu = FixedTrait::new(MU, false);

        let origin_orbit = components::get::<Orbit>(origin.path()).expect(errors::ORBIT_NOT_FOUND);
        let M_origin = propagation::M_from_delta_t(departure_time, origin_orbit.m, origin_orbit.period());

        // Remove once compiler is fixed
        internal::revoke_ap_tracking();

        let e_origin = angles::M_to_E(M_origin, origin_orbit.ecc);
        let nu_origin = angles::E_to_nu(e_origin, origin_orbit.ecc);
        let p_origin = origin_orbit.a * (one - origin_orbit.ecc * origin_orbit.ecc);
        let (r_origin, v_origin) = elements::coe2rv(
            mu: mu,
            p: p_origin,
            ecc: origin_orbit.ecc,
            inc: origin_orbit.inc,
            raan: origin_orbit.raan,
            argp: origin_orbit.argp,
            nu: nu_origin
        );

        // Get orbit data and calculate destination position at arrival time
        let dest_orbit = components::get::<Orbit>(destination.path()).expect(errors::ORBIT_NOT_FOUND);
        let M_dest = propagation::M_from_delta_t(arrival_time, dest_orbit.m, dest_orbit.period());

        // Remove once compiler is fixed
        internal::revoke_ap_tracking();

        let e_dest = angles::M_to_E(M_dest, dest_orbit.ecc);
        let nu_dest = angles::E_to_nu(e_dest, dest_orbit.ecc);
        let p_dest = dest_orbit.a * (one - dest_orbit.ecc * dest_orbit.ecc);
        let (r_dest, v_dest) = elements::coe2rv(
            mu: mu,
            p: p_dest,
            ecc: dest_orbit.ecc,
            inc: dest_orbit.inc,
            raan: dest_orbit.raan,
            argp: dest_orbit.argp,
            nu: nu_dest
        );

        // Determine departure position and velocity based on transit solution
        let transit_q = transit_p / (one + transit_ecc);
        let (r_start, v_start) = elements::coe2rv(
            mu: mu,
            p: transit_p,
            ecc: transit_ecc,
            inc: transit_inc,
            raan: transit_raan,
            argp: transit_argp,
            nu: transit_nu_start
        );

        // Determine arrival position and velocity based on transit solution
        let (r_end, v_end) = elements::coe2rv(
            mu: mu,
            p: transit_p,
            ecc: transit_ecc,
            inc: transit_inc,
            raan: transit_raan,
            argp: transit_argp,
            nu: transit_nu_end
        );

        // NOTE: ensure that trip time validation is unecessary

        // Validate start and end positions are close enough to origin and destination
        assert_positions_equal(r_origin, r_start);
        assert_positions_equal(r_dest, r_end);

        // Calculate total required delta-V
        let delta_v = (v_origin - v_start).norm() + (v_dest - v_end).norm();

        // Calculate ship wet mass
        let mut prop_path: Array<felt252> = Default::default();
        prop_path.append(ship.into());
        prop_path.append(ship_config.propellant_slot.into());
        let mut prop_inventory = components::get::<Inventory>(prop_path.span()).expect(errors::INVENTORY_NOT_FOUND);

        let mut cargo_path: Array<felt252> = Default::default();
        cargo_path.append(ship.into());
        cargo_path.append(ship_config.cargo_slot.into());

        // Ships aren't guaranteed to have a cargo slot, so check
        let (cargo_mass, cargo_reserved_mass) = match components::get::<Inventory>(cargo_path.span()) {
            Option::Some(cargo_inventory) => (cargo_inventory.mass, cargo_inventory.reserved_mass),
            Option::None => (0, 0)
        };

        let wet_mass = ship_config.hull_mass + prop_inventory.mass + cargo_mass;

        // Validate no reservations / deliveries to ship cargo
        assert(prop_inventory.reserved_mass == 0 && cargo_reserved_mass == 0, errors::DELIVERY_IN_PROGRESS);

        // Calculate total required propellant taking into account crew bonuses
        let ship_bonus = ShipVariantTypeTrait::by_type(ship_data.variant).exhaust_velocity_modifier + f64::FixedTrait::ONE();
        let exhaust_eff = crew_details.bonus(modifier_types::PROPELLANT_EXHAUST_VELOCITY, context.now) * ship_bonus;
        let prop_required = propulsion::propellant_required(
            wet_mass, ship_config.exhaust_velocity, delta_v, exhaust_eff.into()
        );

        // Validate ship has enough propellant and reduce inventory
        assert(prop_required <= prop_inventory.amount_of(product_types::HYDROGEN_PROPELLANT), errors::INSUFFICIENT_AMOUNT);
        let mut to_remove: Array<InventoryItem> = Default::default();
        to_remove.append(InventoryItemTrait::new(product_types::HYDROGEN_PROPELLANT, prop_required));
        inventory::remove(ref prop_inventory, to_remove.span());
        components::set::<Inventory>(prop_path.span(), prop_inventory);

        // Update crew, ship and location components
        crew_data.ready_at = irl_arrival;
        crew_data.set_action(actions::TRANSIT_BETWEEN_STARTED, ship, irl_arrival - irl_departure, context.now);
        components::set::<Crew>(caller_crew.path(), crew_data);

        ship_data.ready_at = irl_arrival;
        ship_data.transit_origin = origin;
        ship_data.transit_departure = departure_time;
        ship_data.transit_destination = destination;
        ship_data.transit_arrival = arrival_time;
        components::set::<Ship>(ship.path(), ship_data);

        components::set::<Location>(ship.path(), LocationTrait::new(EntityTrait::new(entities::SPACE, 1)));

        self.emit(TransitStarted {
            ship: ship,
            origin: origin,
            destination: destination,
            departure: departure_time,
            arrival: arrival_time,
            finish_time: irl_arrival,
            caller_crew: caller_crew,
            caller: context.caller
        });
    }

    // Checks that two positions are within at most 1000km of each other
    fn assert_positions_equal(pos1: Vec3, pos2: Vec3) {
        let error = FixedTrait::new(10662218074604120834048, false); // 578 km
        assert((pos1.x - pos2.x).abs() < error, errors::TRANSIT_POSITION_INVALID);
        assert((pos1.y - pos2.y).abs() < error, errors::TRANSIT_POSITION_INVALID);
        assert((pos1.z - pos2.z).abs() < error, errors::TRANSIT_POSITION_INVALID);
    }
}
