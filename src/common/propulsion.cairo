use array::{ArrayTrait, SpanTrait};
use option::OptionTrait;
use traits::{Into, TryInto};

use cubit::f128::{Fixed, FixedTrait, ONE_u128};

use influence::common::astro::G_1000;
use influence::components;
use influence::components::product_type::{types as product_types, ProductTypeTrait};
use influence::config::errors;

// Calculates the escape velicty for a ship from a specific asteroid
// @param mass - mass of the asteroid in tonnes
// @param radius - radius of the asteroid in km
// @return escape velocity in km/s
#[inline(always)]
fn escape_velocity(mass: Fixed, radius: Fixed) -> Fixed {
    let two_over_thousand = FixedTrait::new(36893488147419103, false);
    let thousand = FixedTrait::new(18446744073709551616000, false);
    let GM_R = (FixedTrait::new(G_1000, false) * mass) / radius;
    return (two_over_thousand * GM_R).sqrt() / thousand;
}

// Calculates the propellant required to achieve escape velocity
// @param wet_mass - mass of the ship in grams
// @param exhaust_v - exhaust velocity of the ship in km/s
// @param delta_v - required delta_v in km/s
// @return propellant required in units
#[inline(always)]
fn propellant_required(_wet_mass: u64, exhaust_v: Fixed, delta_v: Fixed, efficiency: Fixed) -> u64 {
    let wet_mass = FixedTrait::new_unscaled(_wet_mass.into(), false);
    let prop = wet_mass - wet_mass / (delta_v / (exhaust_v * efficiency)).exp();
    let product_config = ProductTypeTrait::by_type(product_types::HYDROGEN_PROPELLANT);

    let prop_units = prop / FixedTrait::new_unscaled(product_config.mass.into(), false);
    return (prop_units.ceil().mag / ONE_u128).try_into().unwrap();
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use traits::{Into, TryInto};

    use cubit::f128::{Fixed, FixedTrait, FixedPrint, ONE_u128};
    use cubit::f128::test::helpers::assert_relative;

    use influence::common::astro::G_1000;
    use influence::components;
    use influence::components::product_type::{types as product_types, ProductType};
    use influence::test::mocks;

    #[test]
    #[available_gas(300000)]
    fn test_escape_velocity() {
        let mass = FixedTrait::new_unscaled(925571064959299, false);
        let radius = FixedTrait::new(762122134569922559065, false); // 41.315 km
        assert_relative(super::escape_velocity(mass, radius), 1008765081026723577, 'ev wrong', Option::None(()));
    }

    #[test]
    #[available_gas(1000000)]
    fn test_escape_propellant() {
        mocks::product_type(product_types::HYDROGEN_PROPELLANT);

        let mass = FixedTrait::new_unscaled(925571064959299, false);
        let radius = FixedTrait::new(762122134569922559065, false); // 41.315 km
        let escape_velocity = super::escape_velocity(mass, radius);
        let exhaust_velocity = FixedTrait::new_unscaled(30, false);
        let wet_mass = 181000000;
        let propellant = super::propellant_required(
            wet_mass, exhaust_velocity, escape_velocity, FixedTrait::new_unscaled(1, false)
        );

        assert(propellant == 330, 'propellant wrong');
    }
}
