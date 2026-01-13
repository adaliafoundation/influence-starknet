use array::{ArrayTrait, Span, SpanTrait};
use core::starknet::SyscallResultTrait;
use integer::{u128_safe_divmod, u128_as_non_zero};
use option::OptionTrait;
use result::ResultTrait;
use starknet::SyscallResult;
use starknet::storage_access::{Store, StorageBaseAddress, storage_base_address_const};
use traits::{Into, TryInto};

use cubit::{f64, f128};

use influence::common::{math, packed, packed::{split_felt252, pack_u128, unpack_u128}};
use influence::components::{ComponentTrait, resolve, product_type::types as products};

// Constants ----------------------------------------------------------------------------------------------------------

mod statuses {
    const UNSCANNED: u64 = 0;
    const SURFACE_SCANNING: u64 = 1;
    const SURFACE_SCANNED: u64 = 2;
    const RESOURCE_SCANNING: u64 = 3;
    const RESOURCE_SCANNED: u64 = 4;
}

mod types {
    const C_TYPE_ASTEROID: u64 = 1;
    const CM_TYPE_ASTEROID: u64 = 2;
    const CI_TYPE_ASTEROID: u64 = 3;
    const CS_TYPE_ASTEROID: u64 = 4;
    const CMS_TYPE_ASTEROID: u64 = 5;
    const CIS_TYPE_ASTEROID: u64 = 6;
    const S_TYPE_ASTEROID: u64 = 7;
    const SM_TYPE_ASTEROID: u64 = 8;
    const SI_TYPE_ASTEROID: u64 = 9;
    const M_TYPE_ASTEROID: u64 = 10;
    const I_TYPE_ASTEROID: u64 = 11;
}

mod bonuses {
    const YIELD_1: u64 = 1;
    const YIELD_2: u64 = 2;
    const YIELD_3: u64 = 3;
    const VOLATILE_1: u64 = 4;
    const VOLATILE_2: u64 = 5;
    const VOLATILE_3: u64 = 6;
    const METAL_1: u64 = 7;
    const METAL_2: u64 = 8;
    const METAL_3: u64 = 9;
    const ORGANIC_1: u64 = 10;
    const ORGANIC_2: u64 = 11;
    const ORGANIC_3: u64 = 12;
    const RARE_EARTH: u64 = 13;
    const FISSILE: u64 = 14;
}

// Component ----------------------------------------------------------------------------------------------------------

#[derive(Copy, Drop, Serde)]
struct Celestial {
    celestial_type: u64,
    mass: f128::Fixed, // mass in tonnes
    radius: f64::Fixed, // radius in km
    purchase_order: u64,
    scan_status: u64,
    scan_finish_time: u64,
    bonuses: u64, // in bonus order either true or false (1st bit is empty, used to indicate scan status)
    abundances: felt252 // abundances in resource type order in thousandths
}

impl CelestialComponent of ComponentTrait<Celestial> {
    fn name() -> felt252 {
        return 'Celestial';
    }

    fn is_set(data: Celestial) -> bool {
        return data.celestial_type != 0;
    }

    fn version() -> u64 {
        return 0;
    }
}

trait CelestialTrait {
    fn new(celestial_type: u64, mass: f128::Fixed, radius: f64::Fixed) -> Celestial;
    fn abundance(self: Celestial, resource_type: u64) -> f64::Fixed;
    fn bonus_by_resource(self: Celestial, resource_type: u64) -> f64::Fixed;
    fn assert_resource_scanned(self: Celestial);
    fn assert_surface_scanned(self: Celestial);
}

impl CelestialImpl of CelestialTrait {
    fn new(celestial_type: u64, mass: f128::Fixed, radius: f64::Fixed) -> Celestial {
        return Celestial {
            celestial_type: celestial_type,
            mass: mass,
            radius: radius,
            purchase_order: 0,
            scan_status: 0,
            scan_finish_time: 0,
            bonuses: 0,
            abundances: 0
        };
    }

    fn bonus_by_resource(self: Celestial, resource_type: u64) -> f64::Fixed {
        let mut total_bonus = f64::FixedTrait::ONE();
        let bonuses: u128 = self.bonuses.into();
        let yield = unpack_u128(bonuses, packed::EXP2_1, packed::EXP2_3);

        // Overall yield
        if yield == 1 {
            total_bonus *= f64::FixedTrait::new(4423816315, false); // 3%
        } else if yield == 2 {
            total_bonus *= f64::FixedTrait::new(4552665334, false); // 6%
        } else if yield == 4 {
            total_bonus *= f64::FixedTrait::new(4939212390, false); // 15%
        }

        if resource_type > 0 && resource_type <= 8 {
            // Volatiles
            let volatile = unpack_u128(bonuses, packed::EXP2_4, packed::EXP2_3);

            if volatile == 1 {
                total_bonus *= f64::FixedTrait::new(4724464026, false); // 10%
            } else if volatile == 2 {
                total_bonus *= f64::FixedTrait::new(5153960755, false); // 20%
            } else if volatile == 4 {
                total_bonus *= f64::FixedTrait::new(6442450944, false); // 50%
            }
        } else if resource_type <= 11 {
            // Organics
            let organic = unpack_u128(bonuses, packed::EXP2_10, packed::EXP2_3);

            if organic == 1 {
                total_bonus *= f64::FixedTrait::new(4724464026, false); // 10%
            } else if organic == 2 {
                total_bonus *= f64::FixedTrait::new(5153960755, false); // 20%
            } else if organic == 4 {
                total_bonus *= f64::FixedTrait::new(6442450944, false); // 50%
            }
        } else if resource_type == 15 || resource_type == 22 {
            // Fissiles
            if unpack_u128(bonuses, packed::EXP2_14, packed::EXP2_1) == 1 {
                total_bonus *= f64::FixedTrait::new(5583457485, false); // 30%
            }
        } else if resource_type == 16 || resource_type == 17 {
            // Rare Earths
            if unpack_u128(bonuses, packed::EXP2_13, packed::EXP2_1) == 1 {
                total_bonus *= f64::FixedTrait::new(5583457485, false); // 30%
            }
        } else if resource_type <= 21 {
            // Metals
            let metal = unpack_u128(bonuses, packed::EXP2_7, packed::EXP2_3);

            if metal == 1 {
                total_bonus *= f64::FixedTrait::new(4724464026, false); // 10%
            } else if metal == 2 {
                total_bonus *= f64::FixedTrait::new(5153960755, false); // 20%
            } else if metal == 4 {
                total_bonus *= f64::FixedTrait::new(6442450944, false); // 50%
            }
        }

        return total_bonus;
    }

    // Packed in 11 * 10 bits in low and high 128 bit words
    fn abundance(self: Celestial, resource_type: u64) -> f64::Fixed {
        let (low, high) = split_felt252(self.abundances);
        let mut res: u128 = 0;

        if resource_type <= 11 {
            res = unpack_u128(low, math::exp2((resource_type - 1) * 10).try_into().unwrap(), packed::EXP2_10);
        } else {
            res = unpack_u128(high, math::exp2((resource_type - 12) * 10).try_into().unwrap(), packed::EXP2_10);
        }

        return f64::FixedTrait::new(res.try_into().unwrap() * 4294967, false); // 1/1000 (f64)
    }

    // Assert that at least the long range scan has happened
    fn assert_surface_scanned(self: Celestial) {
        assert(self.scan_status >= statuses::SURFACE_SCANNED, 'surface not scanned');
    }

    fn assert_resource_scanned(self: Celestial) {
        assert(self.scan_status == statuses::RESOURCE_SCANNED, 'resource not scanned');
    }
}

// Storage Access -----------------------------------------------------------------------------------------------------

const RADIUS_SCALE: u64 = 50000; // Store more precision. Scale chosen to allow for a Jupiter size planet

impl StoreCelestial of Store<Celestial> {
    #[inline(always)]
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<Celestial> {
        return StoreCelestial::read_at_offset(address_domain, base, 0);
    }

    #[inline(always)]
    fn write(address_domain: u32, base: StorageBaseAddress, value: Celestial) -> SyscallResult<()> {
        return StoreCelestial::write_at_offset(address_domain, base, 0, value);
    }

    #[inline(always)]
    fn read_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8
    ) -> SyscallResult<Celestial> {
        let combined = Store::<felt252>::read_at_offset(address_domain, base, offset)?;
        let abundances = Store::<felt252>::read_at_offset(address_domain, base, offset + 1)?;
        let (low, high) = split_felt252(combined);

        let unpacked_radius = unpack_u128(low, packed::EXP2_80, packed::EXP2_48).try_into().unwrap();
        let radius = f64::FixedTrait::new_unscaled(unpacked_radius, false) /
            f64::FixedTrait::new_unscaled(RADIUS_SCALE, false);

        return Result::Ok(Celestial {
            celestial_type: unpack_u128(low, packed::EXP2_0, packed::EXP2_16).try_into().unwrap(),
            mass: f128::FixedTrait::new_unscaled(unpack_u128(low, packed::EXP2_16, packed::EXP2_64), false),
            radius: radius,
            purchase_order: unpack_u128(high, packed::EXP2_0, packed::EXP2_20).try_into().unwrap(),
            scan_status: unpack_u128(high, packed::EXP2_20, packed::EXP2_4).try_into().unwrap(),
            scan_finish_time: unpack_u128(high, packed::EXP2_24, packed::EXP2_36).try_into().unwrap(),
            bonuses: unpack_u128(high, packed::EXP2_60, packed::EXP2_32).try_into().unwrap(),
            abundances: abundances
        });
    }

    #[inline(always)]
    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: Celestial
    ) -> SyscallResult<()> {
        let mut low: u128 = 0;
        let mut high: u128 = 0;

        pack_u128(ref low, packed::EXP2_0, packed::EXP2_16, value.celestial_type.into());
        pack_u128(ref low, packed::EXP2_16, packed::EXP2_64, (value.mass.mag / f128::ONE_u128).into());
        pack_u128(ref low, packed::EXP2_80, packed::EXP2_48, (value.radius.mag * RADIUS_SCALE / f64::ONE).into());

        pack_u128(ref high, packed::EXP2_0, packed::EXP2_20, value.purchase_order.into());
        pack_u128(ref high, packed::EXP2_20, packed::EXP2_4, value.scan_status.into());
        pack_u128(ref high, packed::EXP2_24, packed::EXP2_36, value.scan_finish_time.into());
        pack_u128(ref high, packed::EXP2_60, packed::EXP2_32, value.bonuses.into());

        let combined = low.into() + high.into() * packed::EXP2_128;
        Store::<felt252>::write_at_offset(address_domain, base, offset, combined);
        Store::<felt252>::write_at_offset(address_domain, base, offset + 1, value.abundances);
        return Result::Ok(());
    }

    #[inline(always)]
    fn size() -> u8 {
        return 2;
    }
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use array::{ArrayTrait, Span, SpanTrait};
    use integer::{u128_safe_divmod, u128_as_non_zero};
    use option::OptionTrait;
    use result::ResultTrait;
    use starknet::{SyscallResult, SyscallResultTrait, Store, StorageBaseAddress, storage_base_address_const};
    use traits::{Into, TryInto};

    use influence::config::entities;
    use influence::components::product_type::types as product_types;
    use influence::types::entity::{Entity, EntityTrait};

    use cubit::{f64, f128};
    use cubit::f64::test::helpers::assert_relative;

    use super::{Celestial, CelestialTrait, StoreCelestial, types, statuses};

    #[test]
    #[available_gas(500000)]
    fn test_storage() {
        let base = starknet::storage_base_address_from_felt252(42);
        let entity = EntityTrait::new(entities::ASTEROID, 1);
        let orbit = Celestial {
            celestial_type: types::CM_TYPE_ASTEROID,
            mass: f128::FixedTrait::new_unscaled(234500000, false),
            radius: f64::FixedTrait::new_unscaled(120, false),
            purchase_order: 5345,
            scan_status: statuses::SURFACE_SCANNING,
            scan_finish_time: 1234,
            bonuses: 45,
            abundances: 123435
        };

        Store::<Celestial>::write(0, base, orbit);
        let read_orbit = Store::<Celestial>::read(0, base).unwrap();

        assert(read_orbit.celestial_type == orbit.celestial_type, 'celestial_type does not match');
        assert(read_orbit.mass == orbit.mass, 'mass does not match');
        assert(read_orbit.radius == orbit.radius, 'area does not match');
        assert(read_orbit.purchase_order == orbit.purchase_order, 'purchase_order does not match');
        assert(read_orbit.scan_status == orbit.scan_status, 'scan_status does not match');
        assert(read_orbit.scan_finish_time == orbit.scan_finish_time, 'scan_finish_time does not match');
        assert(read_orbit.bonuses == orbit.bonuses, 'bonuses does not match');
        assert(read_orbit.abundances == orbit.abundances, 'abundances does not match');
    }

    #[test]
    #[available_gas(300000)]
    fn test_abundance() {
        let mut celestial = CelestialTrait::new(1, f128::FixedTrait::ONE(), f64::FixedTrait::ONE());
        celestial.abundances = 156802114677168443963923019104558791839170560;
        assert(celestial.abundance(2) == f64::FixedTrait::new(1030792080, false), 'no abundance match'); // 0.24
        assert(celestial.abundance(13) == f64::FixedTrait::new(1932735150, false), 'no abundance match'); // 0.45
    }

    #[test]
    #[available_gas(300000)]
    fn test_bonus_by_resource() {
        let bonuses = 0b110010010010010;
        let mut celestial = CelestialTrait::new(1, f128::FixedTrait::ONE(), f64::FixedTrait::ONE());
        celestial.bonuses = bonuses;

        assert_relative(celestial.bonus_by_resource(product_types::WATER), 4866197946, 'wrong', Option::None(())); // 13%
        assert_relative(celestial.bonus_by_resource(product_types::COFFINITE), 5750961209, 'wrong', Option::None(())); // 33%
        assert_relative(celestial.bonus_by_resource(product_types::OLIVINE), 4866197946, 'wrong', Option::None(())); // 13%
    }
}
