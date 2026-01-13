use array::{ArrayTrait, Span, SpanTrait};
use core::starknet::SyscallResultTrait;
use option::OptionTrait;
use result::ResultTrait;
use starknet::SyscallResult;
use starknet::storage_access::{Store, StorageBaseAddress, storage_base_address_const};
use traits::{Into, TryInto};

use cubit::f128::{Fixed, FixedTrait, ONE_u128, trig};

use influence::common::{astro, packed, packed::{split_felt252, pack_u128, unpack_u128}};
use influence::components::{ComponentTrait, resolve};

#[derive(Copy, Drop, Serde)]
struct Orbit {
    a: Fixed, // semi-major axis (km)
    ecc: Fixed, // eccentricity
    inc: Fixed, // inclination (rad)
    raan: Fixed, // right ascension of the ascending node (rad)
    argp: Fixed, // argument of periapsis (rad)
    m: Fixed // mean anomaly (rad)
}

impl OrbitComponent of ComponentTrait<Orbit> {
    fn name() -> felt252 {
        return 'Orbit';
    }

    fn is_set(data: Orbit) -> bool {
        return data.a.mag != 0;
    }

    fn version() -> u64 {
        return 0;
    }
}

trait OrbitTrait {
    fn period(self: Orbit) -> Fixed;
}

impl OrbitImpl of OrbitTrait {
    fn period(self: Orbit) -> Fixed {
        let two_pi = FixedTrait::new(115904311329233965478, false); // 2 * PI
        return two_pi * ((self.a * self.a / FixedTrait::new(astro::MU, false)) * self.a).sqrt();
    }
}

// Storage Access -----------------------------------------------------------------------------------------------------

const SCALE_AXIS: u128 = 0x40000000; // 2^30
const SCALE_ELEMENTS: u128 = 0x800000000; // 2^35

impl StoreOrbit of Store<Orbit> {
    #[inline(always)]
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<Orbit> {
        return StoreOrbit::read_at_offset(address_domain, base, 0);
    }

    #[inline(always)]
    fn write(address_domain: u32, base: StorageBaseAddress, value: Orbit) -> SyscallResult<()> {
        return StoreOrbit::write_at_offset(address_domain, base, 0, value);
    }

    #[inline(always)]
    fn read_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8
    ) -> SyscallResult<Orbit> {
        let combined = Store::<felt252>::read_at_offset(address_domain, base, offset)?;
        let (low, high) = split_felt252(combined);

        return Result::Ok(Orbit {
            a: FixedTrait::new(unpack_u128(low, packed::EXP2_0, packed::EXP2_64) * SCALE_AXIS.into(), false),
            ecc: FixedTrait::new(unpack_u128(low, packed::EXP2_64, packed::EXP2_32) * SCALE_ELEMENTS, false),
            inc: FixedTrait::new(unpack_u128(low, packed::EXP2_96, packed::EXP2_32) * SCALE_ELEMENTS, false),
            raan: FixedTrait::new(unpack_u128(high, packed::EXP2_0, packed::EXP2_32) * SCALE_ELEMENTS, false),
            argp: FixedTrait::new(unpack_u128(high, packed::EXP2_32, packed::EXP2_32) * SCALE_ELEMENTS, false),
            m: FixedTrait::new(unpack_u128(high, packed::EXP2_64, packed::EXP2_32) * SCALE_ELEMENTS, false)
        });
    }

    #[inline(always)]
    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: Orbit
    ) -> SyscallResult<()> {
        let mut low: u128 = 0;
        let mut high: u128 = 0;

        pack_u128(ref low, packed::EXP2_0, packed::EXP2_64, value.a.mag / SCALE_AXIS);
        pack_u128(ref low, packed::EXP2_64, packed::EXP2_32, value.ecc.mag / SCALE_ELEMENTS);
        pack_u128(ref low, packed::EXP2_96, packed::EXP2_32, value.inc.mag / SCALE_ELEMENTS);
        pack_u128(ref high, packed::EXP2_0, packed::EXP2_32, value.raan.mag / SCALE_ELEMENTS);
        pack_u128(ref high, packed::EXP2_32, packed::EXP2_32, value.argp.mag / SCALE_ELEMENTS);
        pack_u128(ref high, packed::EXP2_64, packed::EXP2_32, value.m.mag / SCALE_ELEMENTS);

        let combined = low.into() + high.into() * packed::EXP2_128;
        Store::<felt252>::write_at_offset(address_domain, base, offset, combined);
        return Result::Ok(());
    }

    #[inline(always)]
    fn size() -> u8 {
        return 1;
    }
}

// Tests --------------------------------------------------------------------------------------------------------------

// Benchmark: 5.4k steps

#[cfg(test)]
mod tests {
    use array::{ArrayTrait, Span, SpanTrait};
    use option::OptionTrait;
    use result::ResultTrait;
    use starknet::{SyscallResult, SyscallResultTrait};
    use starknet::storage_access::{Store, StorageBaseAddress, storage_base_address_const};
    use traits::{Into, TryInto};

    use influence::config::entities;
    use influence::types::entity::{Entity, EntityTrait};

    use cubit::f128::test::helpers::assert_precise;
    use cubit::f128::{Fixed, FixedTrait, ONE_u128};

    use influence::common::packed;
    use influence::components::{ComponentTrait, resolve};

    use super::{Orbit, OrbitTrait, OrbitComponent, StoreOrbit};

    #[test]
    #[available_gas(500000)]
    fn test_storage() {
        let base = starknet::storage_base_address_from_felt252(42);
        let orbit = Orbit {
            a: FixedTrait::new(6049029247426345898732421120, false),
            ecc: FixedTrait::new(5995191823955604275, false),
            inc: FixedTrait::new(45073898850257648, false),
            raan: FixedTrait::new(62919943230756085760, false),
            argp: FixedTrait::new(97469086699478581248, false),
            m: FixedTrait::new(17488672753899966464, false)
        };

        Store::<Orbit>::write(0, base, orbit);
        let read_orbit = Store::<Orbit>::read(0, base).unwrap();

        assert_precise(read_orbit.a, orbit.a.mag.into(), 'a does not match', Option::None(()));
        assert_precise(read_orbit.ecc, orbit.ecc.mag.into(), 'ecc does not match', Option::None(()));
        assert_precise(read_orbit.inc, orbit.inc.mag.into(), 'inc does not match', Option::None(()));
        assert_precise(read_orbit.raan, orbit.raan.mag.into(), 'raan does not match', Option::None(()));
        assert_precise(read_orbit.argp, orbit.argp.mag.into(), 'argp does not match', Option::None(()));
        assert_precise(read_orbit.m, orbit.m.mag.into(), 'm does not match', Option::None(()));
    }

    #[test]
    #[available_gas(500000)]
    fn test_period() {
        let orbit = Orbit {
            a: FixedTrait::new(6049029247426345898732421120, false),
            ecc: FixedTrait::new(5995191823955604275, false),
            inc: FixedTrait::new(45073898850257648, false),
            raan: FixedTrait::new(62919943230756085760, false),
            argp: FixedTrait::new(97469086699478581248, false),
            m: FixedTrait::new(17488672753899966464, false)
        };

        assert(orbit.period().mag == 0x698761c41ce02bc2a5a73af, 'period does not match'); // 1280.729 days
    }
}