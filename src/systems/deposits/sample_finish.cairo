// Finishes sampling a deposit generating the initial yield (in kg)
#[starknet::contract]
mod SampleDepositFinish {
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
    fn run(ref self: ContractState, deposit: Entity, caller_crew: Entity, context: Context) {
        // Check that crew is delegated
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_delegated_to(context.caller);

        // Check the deposit status
        let mut deposit_data = components::get::<Deposit>(deposit.path()).expect(errors::DEPOSIT_NOT_FOUND);
        assert(deposit_data.status == deposit_statuses::SAMPLING, errors::INCORRECT_STATUS);

        // Get abundance info from asteroid
        let (ast, lot) = deposit.to_position();
        let celestial_data = components::get::<Celestial>(EntityTrait::new(entities::ASTEROID, ast).path())
            .expect(errors::CELESTIAL_NOT_FOUND);

        // Get the position of the lot and scale it
        let area = position::surface_area(celestial_data.radius);
        let pos = position::surface_position_norm(lot, area.floor()).mul(scale(celestial_data.radius));

        // Use asteroid, resource and packed abundances as seed
        let mut seed_path: Array<felt252> = Default::default();
        seed_path.append(ast.into());
        seed_path.append(deposit_data.resource.into());
        seed_path.append(celestial_data.abundances);
        let shifted_pos = shifted_point(pos, seed_path.hash());

        // Get simplex noise using shifted point and normalize
        let octaves = octaves(ast);
        let mut noise = simplex3::noise_octaves(
            shifted_pos, octaves, FixedTrait::new(RESOURCE_PERSISTENCE, false)
        );

        noise = (noise + FixedTrait::ONE()) / FixedTrait::new(TWO, false); // normalize to [0, 1]
        let percentile = percentile(noise, octaves);

        // Scale to [0,1] and clamp to ensure no overflows
        let abundance = celestial_data.abundance(deposit_data.resource); // Fixed
        let abundance_floor = FixedTrait::new(abundance.mag / 2, false);
        let mut lot_abundance = abundance_floor;

        if percentile.mag + abundance.mag >= ONE {
            let mut varying = FixedTrait::new((percentile.mag + abundance.mag) - ONE, false) / abundance;
            varying = comp::min(varying, FixedTrait::ONE()) * (FixedTrait::ONE() - abundance_floor);
            lot_abundance += varying;
        }

        // Use lot abundance and rand reveal to calculate yield
        let mut upper_bound = lot_abundance;
        let mut lower_bound = FixedTrait::new(deposit_data.initial_yield.into() * ONE / MAX_YIELD, false);
        let range = upper_bound - lower_bound;

        if deposit_data.yield_eff.mag < ONE {
            upper_bound = lower_bound + range * deposit_data.yield_eff;
        } else {
            lower_bound = upper_bound - range / deposit_data.yield_eff;
        }

        let sample_seed = random::reveal(deposit_commit_hash(deposit, deposit_data.initial_yield));
        let mut raw_yield = FixedTrait::ZERO();

        if upper_bound > lower_bound {
            raw_yield = rand::fixed_normal_between(sample_seed, lower_bound, upper_bound);
        }

        let initial_yield = raw_yield.mag * MAX_YIELD / ONE;

        // Update and save deposit
        deposit_data.status = deposit_statuses::SAMPLED;
        deposit_data.initial_yield = initial_yield;
        deposit_data.remaining_yield = deposit_data.initial_yield;
        components::set::<Deposit>(deposit.path(), deposit_data);

        self.emit(SamplingDepositFinished {
            deposit: deposit,
            initial_yield: deposit_data.initial_yield,
            caller_crew: caller_crew,
            caller: context.caller
        });

        self.emit(Debug_DepositBounds {
            lot_abundance: lot_abundance,
            initial_yield: initial_yield,
            lower_bound: lower_bound,
            upper_bound: upper_bound
        });
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

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use influence::config::MAX_ASTEROID_RADIUS;

    use cubit::f64::FixedTrait;
    use cubit::f64::test::helpers::assert_relative;

    use super::SampleDepositFinish::{scale};

    #[test]
    fn test_scale() {
        let mut result = scale(FixedTrait::new(MAX_ASTEROID_RADIUS, false));
        assert_relative(result, 4831838208, 'wrong scale max', Option::None(()));

        result = scale(FixedTrait::new(MAX_ASTEROID_RADIUS / 2, false));
        assert_relative(result, 3221225472, 'wrong scale half', Option::None(()));

        result = scale(FixedTrait::new(MAX_ASTEROID_RADIUS / 4, false));
        assert_relative(result, 2415919104, 'wrong scale quarter', Option::None(()));
    }
}
