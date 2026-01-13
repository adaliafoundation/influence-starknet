use array::{ArrayTrait, SpanTrait};
use core::starknet::SyscallResultTrait;
use option::OptionTrait;
use result::ResultTrait;
use starknet::SyscallResult;
use starknet::storage_access::{Store, StorageBaseAddress, storage_base_address_const};
use traits::{Into, TryInto};

use cubit::f128::{Fixed, FixedTrait};

use influence::common::{packed, packed::{split_felt252, pack_u128, unpack_u128}};
use influence::components::{ComponentTrait, get};
use influence::config::errors;
use influence::types::entity::{Entity, EntityTrait, Felt252TryIntoEntity};

// Constants ----------------------------------------------------------------------------------------------------------

mod types {
    const ESCAPE_MODULE: u64 = 1;
    const LIGHT_TRANSPORT: u64 = 2;
    const HEAVY_TRANSPORT: u64 = 3;
    const SHUTTLE: u64 = 4;
}

// Component ----------------------------------------------------------------------------------------------------------

#[derive(Copy, Drop, Serde)]
struct ShipType {
    cargo_inventory_type: u64, // inventory type
    cargo_slot: u64,
    docking: bool,
    exhaust_velocity: Fixed, // in km/s (stored in m/s)
    hull_mass: u64, // in g
    landing: bool,
    process_type: u64, // process type used to construct ship
    propellant_emergency_divisor: u64, // sets max for emergency propellant, divide prop inv by this
    propellant_inventory_type: u64, // inventory type
    propellant_slot: u64,
    propellant_type: u64, // product type
    station_type: u64 // station type
}

impl ShipTypeComponent of ComponentTrait<ShipType> {
    fn name() -> felt252 {
        return 'ShipType';
    }

    fn is_set(data: ShipType) -> bool {
        return data.hull_mass != 0;
    }

    fn version() -> u64 {
        return 0;
    }
}

trait ShipTypeTrait {
    fn by_type(id: u64) -> ShipType;
}

impl ShipTypeImpl of ShipTypeTrait {
    fn by_type(id: u64) -> ShipType {
        let mut path: Array<felt252> = Default::default();
        path.append(id.into());
        return get(path.span()).expect(errors::SHIP_TYPE_NOT_FOUND);
    }
}

// Storage Access -----------------------------------------------------------------------------------------------------

impl StoreShipType of Store<ShipType> {
    #[inline(always)]
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<ShipType> {
        return StoreShipType::read_at_offset(address_domain, base, 0);
    }

    #[inline(always)]
    fn write(address_domain: u32, base: StorageBaseAddress, value: ShipType) -> SyscallResult<()> {
        return StoreShipType::write_at_offset(address_domain, base, 0, value);
    }

    #[inline(always)]
    fn read_at_offset(address_domain: u32, base: StorageBaseAddress, offset: u8) -> SyscallResult<ShipType> {
        let combined = Store::<felt252>::read_at_offset(address_domain, base, offset).unwrap();
        let (low, high) = split_felt252(combined);

        return Result::Ok(ShipType {
            cargo_inventory_type: unpack_u128(low, packed::EXP2_0, packed::EXP2_18).try_into().unwrap(),
            cargo_slot: unpack_u128(low, packed::EXP2_18, packed::EXP2_8).try_into().unwrap(),
            docking: unpack_u128(low, packed::EXP2_26, packed::EXP2_1) == 1,
            exhaust_velocity:
                FixedTrait::new_unscaled(unpack_u128(low, packed::EXP2_27, packed::EXP2_30), false) /
                FixedTrait::new(18446744073709551616000, false), // 1000
            hull_mass: unpack_u128(low, packed::EXP2_57, packed::EXP2_50).try_into().unwrap(),
            landing: unpack_u128(low, packed::EXP2_107, packed::EXP2_1) == 1,
            process_type: unpack_u128(low, packed::EXP2_108, packed::EXP2_18).try_into().unwrap(),
            propellant_emergency_divisor: unpack_u128(high, packed::EXP2_0, packed::EXP2_10).try_into().unwrap(),
            propellant_inventory_type: unpack_u128(high, packed::EXP2_10, packed::EXP2_18).try_into().unwrap(),
            propellant_slot: unpack_u128(high, packed::EXP2_28, packed::EXP2_8).try_into().unwrap(),
            propellant_type: unpack_u128(high, packed::EXP2_36, packed::EXP2_18).try_into().unwrap(),
            station_type: unpack_u128(high, packed::EXP2_54, packed::EXP2_18).try_into().unwrap()
        });
    }

    #[inline(always)]
    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: ShipType
    ) -> SyscallResult<()> {
        let mut low: u128 = 0;
        let mut high: u128 = 0;
        let mut landing = 0;
        let mut docking = 0;

        if value.landing {
            landing = 1;
        }

        if value.docking {
            docking = 1;
        }

        pack_u128(ref low, packed::EXP2_0, packed::EXP2_18, value.cargo_inventory_type.into());
        pack_u128(ref low, packed::EXP2_18, packed::EXP2_8, value.cargo_slot.into());
        pack_u128(ref low, packed::EXP2_26, packed::EXP2_1, docking);
        pack_u128(
            ref low,
            packed::EXP2_27,
            packed::EXP2_30,
            (value.exhaust_velocity * FixedTrait::new_unscaled(1000, false)).try_into().unwrap()
        );
        pack_u128(ref low, packed::EXP2_57, packed::EXP2_50, value.hull_mass.into());
        pack_u128(ref low, packed::EXP2_107, packed::EXP2_1, landing);
        pack_u128(ref low, packed::EXP2_108, packed::EXP2_18, value.process_type.into());
        pack_u128(ref high, packed::EXP2_0, packed::EXP2_10, value.propellant_emergency_divisor.into());
        pack_u128(ref high, packed::EXP2_10, packed::EXP2_18, value.propellant_inventory_type.into());
        pack_u128(ref high, packed::EXP2_28, packed::EXP2_8, value.propellant_slot.into());
        pack_u128(ref high, packed::EXP2_36, packed::EXP2_18, value.propellant_type.into());
        pack_u128(ref high, packed::EXP2_54, packed::EXP2_18, value.station_type.into());

        let combined = low.into() + high.into() * packed::EXP2_128;
        return Store::<felt252>::write_at_offset(address_domain, base, offset, combined);
    }

    #[inline(always)]
    fn size() -> u8 {
        return 1;
    }
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use array::{ArrayTrait, SpanTrait};
    use core::starknet::SyscallResultTrait;
    use option::OptionTrait;
    use result::ResultTrait;
    use starknet::SyscallResult;
    use starknet::storage_access::{Store, StorageBaseAddress, storage_base_address_const};
    use traits::{Into, TryInto};

    use cubit::f128::{Fixed, FixedTrait};

    use super::{ShipType, StoreShipType};

    #[test]
    #[available_gas(500000)]
    fn test_storage() {
        let base = starknet::storage_base_address_from_felt252(42);
        let mut to_store = ShipType {
            cargo_inventory_type: 262143,
            cargo_slot: 255,
            docking: true,
            exhaust_velocity: FixedTrait::new_unscaled(30, false),
            hull_mass: 1125899906842623,
            landing: true,
            process_type: 262143,
            propellant_emergency_divisor: 1023,
            propellant_inventory_type: 262143,
            propellant_slot: 255,
            propellant_type: 262143,
            station_type: 262143
        };

        StoreShipType::write(0, base, to_store);
        let mut to_read = StoreShipType::read(0, base).unwrap();
        assert(to_read.cargo_inventory_type == 262143, 'wrong cargo_inventory_type');
        assert(to_read.cargo_slot == 255, 'wrong cargo_slot');
        assert(to_read.docking, 'wrong docking');
        assert(to_read.exhaust_velocity == FixedTrait::new_unscaled(30, false), 'wrong exhaust_velocity');
        assert(to_read.hull_mass == 1125899906842623, 'wrong hull_mass');
        assert(to_read.landing, 'wrong landing');
        assert(to_read.process_type == 262143, 'wrong process_type');
        assert(to_read.propellant_emergency_divisor == 1023, 'wrong divisor');
        assert(to_read.propellant_inventory_type == 262143, 'wrong propellant_inventory_type');
        assert(to_read.propellant_slot == 255, 'wrong propellant_slot');
        assert(to_read.propellant_type == 262143, 'wrong propellant_type');
        assert(to_read.station_type == 262143, 'wrong station_type');
    }
}
