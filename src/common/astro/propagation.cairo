use integer::u256_sqrt;
use traits::Into;

use cubit::f128::{Fixed, FixedTrait, ONE_u128, trig::PI_u128};

use influence::astro::angles;

// Time elapsed since periapsis for given true anomaly.
//
// @param nu True anomaly (rad)
// @param ecc Eccentricity
// @param mu Gravity parameter (km3 / sec^2)
// @param q Periapsis distance (km)
// @param delta Parameter that controls the size of the near parabolic region
fn delta_t_from_nu(nu: Fixed, ecc: Fixed, mu: Fixed, q: Fixed) -> Fixed {
    let pi = FixedTrait::new(PI_u128, false);
    let one = FixedTrait::ONE();
    let two = FixedTrait::new(36893488147419103232, false);
    let three = FixedTrait::new(55340232221128654848, false);
    let delta = FixedTrait::new(184467440737095516, false); // 0.01

    assert(nu < pi, 'nu must be < pi');
    assert(nu >= -pi, 'nu must be >= -pi');
    assert(ecc >= FixedTrait::ZERO(), 'ecc must be > 0');
    assert(one + ecc * nu.cos() >= FixedTrait::ZERO(), 'unfeasible region');

    let mut M = FixedTrait::ZERO();
    let mut n = FixedTrait::ZERO();

    if ecc < one - delta {
        // Strong elliptic
        let E = angles::nu_to_E(nu, ecc);
        M = angles::E_to_M(E, ecc);
        n = _elliptical_n(mu, ecc, q);
    } else if ecc < one {
        let E = angles::nu_to_E(nu, ecc);

        if delta <= one - ecc * E.cos() {
            // Strong elliptic
            M = angles::E_to_M(E, ecc);
            n = _elliptical_n(mu, ecc, q);
        } else {
            // Near parabolic low
            let D = angles::nu_to_D(nu);
            M = angles::D_to_M_near_parabolic(D, ecc);
            n = _parabolic_n(mu, ecc, q);
        }
    } else if ecc == one {
        // Parabolic
        let D = angles::nu_to_D(nu);
        M = angles::D_to_M(D);
        n = (mu / (two * q.pow(three))).sqrt();
    } else if ecc <= one + delta {
        let F = angles::nu_to_F(nu, ecc);

        if delta <= ecc * F.cosh() - one {
            // Strong hyperbolic
            M = angles::F_to_M(F, ecc);
            n = _hyperbolic_n(mu, ecc, q);
        } else {
            // Near parabolic high
            let D = angles::nu_to_D(nu);
            M = angles::D_to_M_near_parabolic(D, ecc);
            n = _parabolic_n(mu, ecc, q);
        }
    } else {
        // Strong hyperbolic
        let F = angles::nu_to_F(nu, ecc);
        M = angles::F_to_M(F, ecc);
        n = _hyperbolic_n(mu, ecc, q);
    }

    let sec_hour = FixedTrait::new(66408278665354385817600, false); // 3600
    return M * sec_hour / n;
}

// Propogates mean anomaly forward by delta_t
fn M_from_delta_t(delta_t: u64, M_at_epoch: Fixed, period: Fixed) -> Fixed {
    let two_pi = FixedTrait::new(115904311329233965478, false); // 2 * PI
    let revs = (M_at_epoch / two_pi) + FixedTrait::new_unscaled(delta_t.into(), false) / period;
    return (revs - revs.floor()) * two_pi;
}

fn _elliptical_n(mu: Fixed, ecc: Fixed, q: Fixed) -> Fixed {
    let one = FixedTrait::ONE();
    let one_ecc_q = (one - ecc) / q;
    let sec_hour_2 = FixedTrait::new(239069803195275788943360000, false); // 3600^2
    return (mu * sec_hour_2 * one_ecc_q * one_ecc_q * one_ecc_q).sqrt();
}

fn _parabolic_n(mu: Fixed, ecc: Fixed, q: Fixed) -> Fixed {
    let sec_hour_2 = FixedTrait::new(239069803195275788943360000, false); // 3600^2
    let two = FixedTrait::new(36893488147419103232, false);
    return (mu * sec_hour_2 / two / q / q / q).sqrt();
}

fn _hyperbolic_n(mu: Fixed, ecc: Fixed, q: Fixed) -> Fixed {
    let one = FixedTrait::ONE();
    let one_ecc_q = (ecc - one) / q;
    let sec_hour_2 = FixedTrait::new(239069803195275788943360000, false); // 3600^2
    return (mu * sec_hour_2 * one_ecc_q * one_ecc_q * one_ecc_q).sqrt();
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use option::OptionTrait;
    use traits::Into;

    use cubit::f128::test::helpers::{assert_precise, assert_relative};
    use cubit::f128::FixedTrait;

    #[test]
    #[available_gas(7000000)]
    fn test_delta_t_from_nu_elliptical() {
        let nu = FixedTrait::new(17488672759741688000, false);
        let ecc = FixedTrait::new(5995191823955604275, false);
        let mu = FixedTrait::new(2097177683003028457316679680000, false);
        let q = FixedTrait::new(5410100577969855036380938240, false) / (FixedTrait::ONE() + ecc);
        let t = super::delta_t_from_nu(nu, ecc, mu, q);
        assert_relative(t, 159889915484693139365560320, 'invalid time', Option::Some((18446744073709))); // 8667657 sec
    }

    #[test]
    #[available_gas(7000000)]
    fn test_delta_t_from_nu_hyperbolic() {
        let nu = FixedTrait::new(2350410669365469696, false);
        let ecc = FixedTrait::new(31933158665998606336, false);
        let mu = FixedTrait::new(7352880304348019749289984, false);
        let q = FixedTrait::new(901096946328627742507008, false) / (FixedTrait::ONE() + ecc);
        let t = super::delta_t_from_nu(nu, ecc, mu, q);
        assert_relative(t, 5407171959967992250368, 'invalid time', Option::Some((18446744073709))); // 293.1233793 sec
    }

    #[test]
    #[available_gas(12000000)]
    fn test_delta_t_from_nu_parabolic_low() {
        let nu = FixedTrait::new(9223372036854775808, false);
        let ecc = FixedTrait::new(18354510353341003776, false);
        let mu = FixedTrait::new(7352880304348019749289984, false);
        let q = FixedTrait::new(4899602799929846585622528, false) / (FixedTrait::ONE() + ecc);
        let t = super::delta_t_from_nu(nu, ecc, mu, q);
        assert_relative(t, 524285997049854455447552, 'invalid time', Option::Some((18446744073709))); // 28421.60085 sec
    }

    #[test]
    #[available_gas(12000000)]
    fn test_delta_t_from_nu_parabolic_high() {
        let nu = FixedTrait::new(18446744073709551616, false);
        let ecc = FixedTrait::new(18538977794078097408, false);
        let mu = FixedTrait::new(7352880304348019749289984, false);
        let q = FixedTrait::new(4899602799929846585622528, false) / (FixedTrait::ONE() + ecc);
        let t = super::delta_t_from_nu(nu, ecc, mu, q);
        assert_relative(t, 1195821455086349690339328, 'invalid time', Option::Some((18446744073709))); // 64825.610975 sec
    }

    #[test]
    #[available_gas(500000)]
    fn test_M_from_delta_t() {
        let delta_t = 250000000;
        let M_at_epoch = FixedTrait::new(17488672753899966464, false);
        let period = FixedTrait::new(0x698761c41ce02bc2a5a73af, false); // 1280.729 days (in seconds)
        let M = super::M_from_delta_t(delta_t, M_at_epoch, period);
        assert(M.mag == 47539674310867853949, 'invalid mean anomaly');
    }
}