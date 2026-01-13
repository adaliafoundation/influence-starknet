use array::{ArrayTrait, SpanTrait};
use core::starknet::SyscallResultTrait;
use option::OptionTrait;
use result::ResultTrait;
use starknet::SyscallResult;
use starknet::storage_access::{Store, StorageBaseAddress, storage_base_address_const};
use traits::{Into, TryInto};

use influence::common::{packed, packed::{pack_u128, unpack_u128}};
use influence::components::{ComponentTrait, get};
use influence::config::errors;
use influence::types::entity::{Entity, EntityTrait, Felt252TryIntoEntity};

// Constants ----------------------------------------------------------------------------------------------------------

mod types {
    const BASIC: u64 = 1;
}

// Component ----------------------------------------------------------------------------------------------------------

#[derive(Copy, Drop, Serde)]
struct DryDockType {
    max_mass: u64,
    max_volume: u64
}

impl DryDockTypeComponent of ComponentTrait<DryDockType> {
    fn name() -> felt252 {
        return 'DryDockType';
    }

    fn is_set(data: DryDockType) -> bool {
        return data.max_mass != 0;
    }

    fn version() -> u64 {
        return 0;
    }
}

trait DryDockTypeTrait {
    fn by_type(id: u64) -> DryDockType;
}

impl DryDockTypeImpl of DryDockTypeTrait {
    fn by_type(id: u64) -> DryDockType {
        let mut path: Array<felt252> = Default::default();
        path.append(id.into());
        return get(path.span()).expect(errors::DRY_DOCK_TYPE_NOT_FOUND);
    }
}

// Storage Access -----------------------------------------------------------------------------------------------------

impl StoreDryDockType of Store<DryDockType> {
    #[inline(always)]
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<DryDockType> {
        return StoreDryDockType::read_at_offset(address_domain, base, 0);
    }

    #[inline(always)]
    fn write(address_domain: u32, base: StorageBaseAddress, value: DryDockType) -> SyscallResult<()> {
        return StoreDryDockType::write_at_offset(address_domain, base, 0, value);
    }

    #[inline(always)]
    fn read_at_offset(address_domain: u32, base: StorageBaseAddress, offset: u8) -> SyscallResult<DryDockType> {
        let low = Store::<u128>::read_at_offset(address_domain, base, offset)?;

        return Result::Ok(DryDockType {
            max_mass: unpack_u128(low, packed::EXP2_0, packed::EXP2_50).try_into().unwrap(),
            max_volume: unpack_u128(low, packed::EXP2_50, packed::EXP2_50).try_into().unwrap()
        });
    }

    #[inline(always)]
    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: DryDockType
    ) -> SyscallResult<()> {
        let mut low: u128 = 0;

        pack_u128(ref low, packed::EXP2_0, packed::EXP2_50, value.max_mass.into());
        pack_u128(ref low, packed::EXP2_50, packed::EXP2_50, value.max_volume.into());

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

    use super::{DryDockType, StoreDryDockType};

    #[test]
    #[available_gas(500000)]
    fn test_storage() {
        let base = starknet::storage_base_address_from_felt252(42);
        let mut to_store = DryDockType { max_mass: 1125899906842623, max_volume: 1125899906842622 };

        StoreDryDockType::write(0, base, to_store);
        let mut to_read = StoreDryDockType::read(0, base).unwrap();
        assert(to_read.max_mass == 1125899906842623, 'wrong max_mass');
        assert(to_read.max_volume == 1125899906842622, 'wrong max_volume');
    }
}
