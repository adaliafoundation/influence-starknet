use array::{ArrayTrait, SpanTrait};
use core::starknet::SyscallResultTrait;
use option::OptionTrait;
use result::ResultTrait;
use starknet::SyscallResult;
use starknet::storage_access::{Store, StorageBaseAddress, storage_base_address_const};
use traits::{Into, TryInto};

use cubit::f64::{Fixed, FixedTrait};

use influence::common::{packed, packed::{pack_u128, unpack_u128}};
use influence::components::{ComponentTrait, get};
use influence::config::errors;
use influence::types::entity::{Entity, EntityTrait, Felt252TryIntoEntity};

// Constants ----------------------------------------------------------------------------------------------------------

mod types {
    const STANDARD: u64 = 1;
    const COBALT_PIONEER: u64 = 2;
    const TITANIUM_PIONEER: u64 = 3;
    const AUREATE_PIONEER: u64 = 4;
}

// Component ----------------------------------------------------------------------------------------------------------

#[derive(Copy, Drop, Serde)]
struct ShipVariantType {
    ship_type: u64, // the ship type this variant applies to
    exhaust_velocity_modifier: Fixed
}

impl ShipVariantTypeComponent of ComponentTrait<ShipVariantType> {
    fn name() -> felt252 {
        return 'ShipVariantType';
    }

    fn is_set(data: ShipVariantType) -> bool {
        return data.ship_type != 0; // ship type of 1 is "all" (does not apply to escape module)
    }

    fn version() -> u64 {
        return 0;
    }
}

trait ShipVariantTypeTrait {
    fn by_type(id: u64) -> ShipVariantType;
}

impl ShipVariantTypeImpl of ShipVariantTypeTrait {
    fn by_type(id: u64) -> ShipVariantType {
        let mut path: Array<felt252> = Default::default();
        path.append(id.into());
        return get(path.span()).expect(errors::SHIP_VARIANT_TYPE_NOT_FOUND);
    }
}

// Storage Access -----------------------------------------------------------------------------------------------------

impl StoreShipVariantType of Store<ShipVariantType> {
    #[inline(always)]
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<ShipVariantType> {
        return StoreShipVariantType::read_at_offset(address_domain, base, 0);
    }

    #[inline(always)]
    fn write(address_domain: u32, base: StorageBaseAddress, value: ShipVariantType) -> SyscallResult<()> {
        return StoreShipVariantType::write_at_offset(address_domain, base, 0, value);
    }

    #[inline(always)]
    fn read_at_offset(address_domain: u32, base: StorageBaseAddress, offset: u8) -> SyscallResult<ShipVariantType> {
        let low = Store::<u128>::read_at_offset(address_domain, base, offset)?;
        let ev_modifier =
            FixedTrait::new_unscaled(unpack_u128(low, packed::EXP2_16, packed::EXP2_16).try_into().unwrap(), false) /
            FixedTrait::new(42949672960000, false);

        return Result::Ok(ShipVariantType {
            ship_type: unpack_u128(low, packed::EXP2_0, packed::EXP2_16).try_into().unwrap(),
            exhaust_velocity_modifier: ev_modifier
        });
    }

    #[inline(always)]
    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: ShipVariantType
    ) -> SyscallResult<()> {
        let mut low: u128 = 0;

        pack_u128(ref low, packed::EXP2_0, packed::EXP2_16, value.ship_type.into());
        let ev_modifier = value.exhaust_velocity_modifier * FixedTrait::new(42949672960000, false);
        pack_u128(ref low, packed::EXP2_16, packed::EXP2_16, ev_modifier.try_into().unwrap());

        return Store::<u128>::write_at_offset(address_domain, base, offset, low);
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

    use cubit::f64::{Fixed, FixedTrait};

    use super::{ShipVariantType, StoreShipVariantType};

    use debug::PrintTrait;

    #[test]
    #[available_gas(500000)]
    fn test_storage() {
        let base = starknet::storage_base_address_from_felt252(42);
        let mut to_store = ShipVariantType { ship_type: 2, exhaust_velocity_modifier: FixedTrait::new(429496730, false) };

        StoreShipVariantType::write(0, base, to_store);
        let mut to_read = StoreShipVariantType::read(0, base).unwrap();
        assert(to_read.ship_type == 2, 'wrong ship type');
        assert(to_read.exhaust_velocity_modifier == FixedTrait::new(429496729, false), 'wrong exhaust velocity bonus');
    }
}
