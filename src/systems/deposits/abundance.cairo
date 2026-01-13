#[starknet::contract]
mod Abundance {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use starknet::ContractAddress;
    use traits::{Into, TryInto};

    use cubit::f64::procgen::{rand, simplex3};
    use cubit::f64::{Fixed, FixedTrait, Vec3, Vec3Trait, comp, ONE, TWO};

    use influence::common::{position, random, crew::CrewDetailsTrait};
    use influence::components;
    use influence::components::{Celestial, CelestialTrait,
        product_type::types as products,
        deposit::{MAX_YIELD, statuses as deposit_statuses, Deposit, DepositTrait}};
    use influence::config::{entities, errors, noise::percentile, MAX_ASTEROID_RADIUS};
    use influence::systems::deposits::helpers::deposit_commit_hash;
    use influence::types::{ArrayHashTrait, Context, Entity, EntityTrait};

    const RESOURCE_SIZE_VARYING: u64 = 3221225472; // 0.75 / MAX_RADIUS
    const RESOURCE_SIZE_BASE: u64 = 1610612736; // 0.375
    const RESOURCE_PERSISTENCE: u64 = 2147483648; // 0.5

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct SamplingDepositFinished {
        deposit: Entity,
        initial_yield: u64,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[derive(Copy, Drop, starknet::Event)]
    struct Debug_DepositBounds {
        lot_abundance: Fixed,
        initial_yield: u64,
        lower_bound: Fixed,
        upper_bound: Fixed
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        SamplingDepositFinished: SamplingDepositFinished,
        Debug_DepositBounds: Debug_DepositBounds
    }

    #[external(v0)]
    fn run(self: @ContractState, ast: u64, lot: u64, resource: u64, context: Context) -> (Fixed, Fixed, Fixed) {
        let celestial_data = components::get::<Celestial>(EntityTrait::new(entities::ASTEROID, ast).path())
            .expect(errors::CELESTIAL_NOT_FOUND);

        // Get the position of the lot and scale it
        let area = position::surface_area(celestial_data.radius);
        let pos = position::surface_position_norm(lot, area.floor()).mul(scale(celestial_data.radius));

        // Use asteroid, resource and packed abundances as seed
        let mut seed_path: Array<felt252> = Default::default();
        seed_path.append(ast.into());
        seed_path.append(resource.into());
        seed_path.append(celestial_data.abundances);
        let shifted_pos = shifted_point(pos, seed_path.hash());

        // Get simplex noise using shifted point and normalize
        let octaves = octaves(ast);
        let mut noise = simplex3::noise_octaves(
            shifted_pos, octaves, FixedTrait::new(RESOURCE_PERSISTENCE, false)
        );

        noise = (noise + FixedTrait::ONE()) / FixedTrait::new(TWO, false); // normalize to [0, 1]
        let percentile = percentile(noise, octaves);

        // NOTE: cache noise value for the resource / lot the first time

        // Scale to [0,1] and clamp to ensure no overflows
        let abundance = celestial_data.abundance(resource); // Fixed
        let abundance_floor = FixedTrait::new(abundance.mag / 2, false);
        let mut lot_abundance = abundance_floor;

        if percentile.mag + abundance.mag >= ONE {
            let mut varying = FixedTrait::new((percentile.mag + abundance.mag) - ONE, false) / abundance;
            varying = comp::min(varying, FixedTrait::ONE()) * (FixedTrait::ONE() - abundance_floor);
            lot_abundance += varying;
        }

        return (lot_abundance, noise, percentile);
    }

    // LUT based on: 2 + 4 * (radius / MAX_RADIUS ^ 1/3)
    fn octaves(id: u64) -> u64 {
        if id == 1 { return 6; }
        if id <= 6 { return 5; }
        if id <= 74 { return 4; }
        if id <= 6345 { return 3; }
        return 2;
    }

    // Simplex scale based on: base + varying * (radius / MAX_RADIUS)
    fn scale(radius: Fixed) -> Fixed {
        return FixedTrait::new(RESOURCE_SIZE_BASE, false) + FixedTrait::new(RESOURCE_SIZE_VARYING, false) *
            (radius / FixedTrait::new(MAX_ASTEROID_RADIUS, false));
    }

    // Shifts a point by between
    fn shifted_point(pos: Vec3, seed: felt252) -> Vec3 {
        let lowShift = FixedTrait::new(21474836480, true); // -5 (f64)
        let highShift = FixedTrait::new(21474836480, false); // 5 (f64)

        return Vec3 {
            x: pos.x + rand::fixed_between(rand::derive(seed, 1), lowShift, highShift),
            y: pos.y + rand::fixed_between(rand::derive(seed, 2), lowShift, highShift),
            z: pos.z + rand::fixed_between(rand::derive(seed, 3), lowShift, highShift)
        };
    }
}
