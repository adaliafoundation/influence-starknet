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
struct DockType {
    cap: u64, // capacity of the dock
    delay: u64 // time delay in Adalian seconds for departures / arrivals
}

impl DockTypeComponent of ComponentTrait<DockType> {
    fn name() -> felt252 {
        return 'DockType';
    }

    fn is_set(data: DockType) -> bool {
        return data.cap != 0;
    }

    fn version() -> u64 {
        return 0;
    }
}

trait DockTypeTrait {
    fn by_type(id: u64) -> DockType;
}

impl DockTypeImpl of DockTypeTrait {
    fn by_type(id: u64) -> DockType {
        let mut path: Array<felt252> = Default::default();
        path.append(id.into());
        return get(path.span()).expect(errors::DOCK_TYPE_NOT_FOUND);
    }
}

// Storage Access -----------------------------------------------------------------------------------------------------

impl StoreDockType of Store<DockType> {
    #[inline(always)]
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<DockType> {
        return StoreDockType::read_at_offset(address_domain, base, 0);
    }

    #[inline(always)]
    fn write(address_domain: u32, base: StorageBaseAddress, value: DockType) -> SyscallResult<()> {
        return StoreDockType::write_at_offset(address_domain, base, 0, value);
    }

    #[inline(always)]
    fn read_at_offset(address_domain: u32, base: StorageBaseAddress, offset: u8) -> SyscallResult<DockType> {
        let low = Store::<u128>::read_at_offset(address_domain, base, offset)?;

        return Result::Ok(DockType {
            cap: unpack_u128(low, packed::EXP2_0, packed::EXP2_20).try_into().unwrap(),
            delay: unpack_u128(low, packed::EXP2_20, packed::EXP2_20).try_into().unwrap()
        });
    }

    #[inline(always)]
    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: DockType
    ) -> SyscallResult<()> {
        let mut low: u128 = 0;

        pack_u128(ref low, packed::EXP2_0, packed::EXP2_20, value.cap.into());
        pack_u128(ref low, packed::EXP2_20, packed::EXP2_20, value.delay.into());

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

    use super::{DockType, StoreDockType};

    #[test]
    #[available_gas(500000)]
    fn test_storage() {
        let base = starknet::storage_base_address_from_felt252(42);
        let mut to_store = DockType { cap: 250, delay: 10000 };

        StoreDockType::write(0, base, to_store);
        let mut to_read = StoreDockType::read(0, base).unwrap();
        assert(to_read.cap == 250, 'wrong cap');
        assert(to_read.delay == 10000, 'wrong delay');
    }
}
