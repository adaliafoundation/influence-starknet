#[starknet::contract]
mod InitializeAsteroid {
    use array::{ArrayTrait, SpanTrait};
    use hash::LegacyHash;
    use option::OptionTrait;
    use traits::Into;

    use cubit::{f64, f128};

    use influence::{contracts, components, config};
    use influence::common::position;
    use influence::components::{Celestial, CelestialTrait, Orbit};
    use influence::config::entities;
    use influence::types::{Context, Entity, EntityTrait, MerkleTree, MerkleTreeTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct AsteroidInitialized {
        asteroid: Entity
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        AsteroidInitialized: AsteroidInitialized
    }

    // Seed asteroids based on merkleized L1 data
    // @param asteroid_id The ID of the asteroid to seed
    // @param celestial_type The spectral type of the asteroid (see Celestial component)
    // @param mass The mass of the asteroid in tonnes
    // @param radius The radius of the asteroid in km
    // @param scan_status The scan status of the asteroid (see Celestial component)
    // @param bonuses The packed bonuses of the asteroid (matches L1 format with scanned bit ignored, 0 if none)
    // @param purchase_order The purchase order of the asteroid (0 if none)
    // @param a The semi-major axis of the asteroid's orbit
    // @param ecc The eccentricity of the asteroid's orbit
    // @param inc The inclination of the asteroid's orbit
    // @param raan The right ascension of the ascending node of the asteroid's orbit
    // @param argp The argument of periapsis of the asteroid's orbit
    // @param m The mean anomaly of the asteroid's orbit
    // @param name The name of the asteroid (optional, 0 if none)
    #[external(v0)]
    fn run(
        ref self: ContractState,
        asteroid: Entity,
        celestial_type: u64,
        mass: u128, // mass in tonnes
        radius: u64, // radius in km
        a: u128, // semi-major axis
        ecc: u128, // eccentricity
        inc: u128, // inclination
        raan: u128, // right ascension of the ascending node
        argp: u128, // argument of periapsis
        m: u128, // mean anomaly
        purchase_order: u64,
        scan_status: u64,
        bonuses: u64,
        merkle_proof: Span<felt252>,
        context: Context
    ) {
        // Check that the asteroid hasn't already been seeded
        assert(components::get::<Celestial>(asteroid.path()).is_none(), 'asteroid already exists');

        // Compute the merkle leaf
        let mut leaf: felt252 = LegacyHash::<felt252>::hash(asteroid.id.into(), celestial_type.into());
        leaf = LegacyHash::<felt252>::hash(leaf, mass.into());
        leaf = LegacyHash::<felt252>::hash(leaf, radius.into());
        leaf = LegacyHash::<felt252>::hash(leaf, a.into());
        leaf = LegacyHash::<felt252>::hash(leaf, ecc.into());
        leaf = LegacyHash::<felt252>::hash(leaf, inc.into());
        leaf = LegacyHash::<felt252>::hash(leaf, raan.into());
        leaf = LegacyHash::<felt252>::hash(leaf, argp.into());
        leaf = LegacyHash::<felt252>::hash(leaf, m.into());
        leaf = LegacyHash::<felt252>::hash(leaf, purchase_order.into());
        leaf = LegacyHash::<felt252>::hash(leaf, scan_status.into());
        leaf = LegacyHash::<felt252>::hash(leaf, bonuses.into());

        // Verify the merkle proof
        let mut merkle_tree = MerkleTreeTrait::new();
        let root = config::get('ASTEROID_MERKLE_ROOT');
        let expected_root = merkle_tree.compute_root(leaf, merkle_proof);
        assert(expected_root == root, 'invalid merkle proof');

        // Store the Celestial data
        components::set::<Celestial>(asteroid.path(), Celestial {
            celestial_type: celestial_type,
            mass: f128::FixedTrait::new(mass, false),
            radius: f64::FixedTrait::new(radius, false),
            purchase_order: purchase_order,
            scan_status: scan_status,
            scan_finish_time: 0,
            bonuses: bonuses,
            abundances: 0
        });

        // Store the Orbit data
        components::set::<Orbit>(asteroid.path(), Orbit {
            a: f128::FixedTrait::new(a, false),
            ecc: f128::FixedTrait::new(ecc, false),
            inc: f128::FixedTrait::new(inc, false),
            raan: f128::FixedTrait::new(raan, false),
            argp: f128::FixedTrait::new(argp, false),
            m: f128::FixedTrait::new(m, false)
        });

        self.emit(AsteroidInitialized {
            asteroid: asteroid
        });
    }
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;

    use cubit::{f64, f128};
    use cubit::f64::test::helpers::assert_relative as assert_relative_f64;
    use cubit::f128::test::helpers::assert_relative as assert_relative_f128;

    use influence::{components, config};
    use influence::components::{celestial::{types, statuses, Celestial, CelestialTrait}, Name};
    use influence::config::entities;
    use influence::contracts::dispatcher::Dispatcher;
    use influence::types::EntityTrait;
    use influence::test::{helpers, mocks};

    use super::InitializeAsteroid;

    #[test]
    #[available_gas(3000000)]
    fn test_seed() {
        helpers::init();
        starknet::testing::set_caller_address(starknet::contract_address_const::<1>());

        let asteroid_address = helpers::deploy_asteroid();
        let merkle_proof = array![
            0x2222c4ac5ef85837696d786a5b0b84c437d7f037e46e4fecfb8b54433b4b5e7,
            0x3e1287bea05910563d20c29161393c5955fc9c7ac9144c3446b1a8653cc55ff
        ];

        config::set('ASTEROID_MERKLE_ROOT', 0xa65ef7e3c2dbc66c20303a10be7b47cb8467cef25f1c74a97c67d2afb94e33);
        let asteroid = EntityTrait::new(entities::ASTEROID, 1);

        let mut state = InitializeAsteroid::contract_state_for_testing();
        InitializeAsteroid::run(
            ref state,
            asteroid,
            types::C_TYPE_ASTEROID,
            5711148277301932455541959738129383424,
            1611222621356,
            6049029247426345756235714160,
            5995191823955604275,
            45073898850257648,
            62919943230756093952,
            97469086699478581248,
            17488672753899970560,
            0,
            statuses::SURFACE_SCANNED,
            0,
            merkle_proof.span(),
            mocks::context('PLAYER')
        );

        let celestial_data = components::get::<Celestial>(asteroid.path()).unwrap();
        assert(celestial_data.celestial_type == types::C_TYPE_ASTEROID, 'celestial type');
        assert_relative_f128(celestial_data.mass, 5711148277301932455541959738129383424, 'mass', Option::None(()));
        assert_relative_f64(celestial_data.radius, 1611222621356, 'radius', Option::None(()));
        assert(celestial_data.scan_status == statuses::SURFACE_SCANNED, 'scan status');
        assert(celestial_data.scan_finish_time == 0, 'scan finish time');
        assert(celestial_data.bonuses == 0, 'bonuses');
        assert(celestial_data.abundances == 0, 'abundances');
    }

    #[test]
    #[available_gas(5000000)]
    #[should_panic(expected: ('asteroid already exists', ))]
    fn test_already_exists() {
        helpers::init();
        starknet::testing::set_caller_address(starknet::contract_address_const::<1>());

        let asteroid_address = helpers::deploy_asteroid();
        let merkle_proof = array![
            0x2222c4ac5ef85837696d786a5b0b84c437d7f037e46e4fecfb8b54433b4b5e7,
            0x3e1287bea05910563d20c29161393c5955fc9c7ac9144c3446b1a8653cc55ff
        ];

        config::set('ASTEROID_MERKLE_ROOT', 0xa65ef7e3c2dbc66c20303a10be7b47cb8467cef25f1c74a97c67d2afb94e33);
        let asteroid = EntityTrait::new(entities::ASTEROID, 1);

        let mut state = InitializeAsteroid::contract_state_for_testing();
        InitializeAsteroid::run(
            ref state,
            asteroid,
            types::C_TYPE_ASTEROID,
            5711148277301932455541959738129383424,
            1611222621356,
            6049029247426345756235714160,
            5995191823955604275,
            45073898850257648,
            62919943230756093952,
            97469086699478581248,
            17488672753899970560,
            0,
            statuses::SURFACE_SCANNED,
            0,
            merkle_proof.span(),
            mocks::context('PLAYER')
        );

        InitializeAsteroid::run(
            ref state,
            asteroid,
            types::C_TYPE_ASTEROID,
            5711148277301932455541959738129383424,
            1611222621356,
            6049029247426345756235714160,
            5995191823955604275,
            45073898850257648,
            62919943230756093952,
            97469086699478581248,
            17488672753899970560,
            0,
            statuses::SURFACE_SCANNED,
            0,
            merkle_proof.span(),
            mocks::context('PLAYER')
        );
    }
}