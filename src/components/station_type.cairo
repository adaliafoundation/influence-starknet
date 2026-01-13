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
    const STANDARD_QUARTERS: u64 = 1;
    const EXPANDED_QUARTERS: u64 = 2;
    const HABITAT: u64 = 3;
}

// Component ----------------------------------------------------------------------------------------------------------

#[derive(Copy, Drop, Serde)]
struct StationType {
    cap: u64,
    recruitment: bool,
    efficiency: Fixed // must be >= 1
}

impl StationTypeComponent of ComponentTrait<StationType> {
    fn name() -> felt252 {
        return 'StationType';
    }

    fn is_set(data: StationType) -> bool {
        return data.cap != 0;
    }

    fn version() -> u64 {
        return 0;
    }
}

trait StationTypeTrait {
    fn by_type(id: u64) -> StationType;
}

impl StationTypeImpl of StationTypeTrait {
    fn by_type(id: u64) -> StationType {
        let mut path: Array<felt252> = Default::default();
        path.append(id.into());
        return get(path.span()).expect(errors::STATION_TYPE_NOT_FOUND);
    }
}

// Storage Access -----------------------------------------------------------------------------------------------------

impl StoreStationType of Store<StationType> {
    #[inline(always)]
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<StationType> {
        return StoreStationType::read_at_offset(address_domain, base, 0);
    }

    #[inline(always)]
    fn write(address_domain: u32, base: StorageBaseAddress, value: StationType) -> SyscallResult<()> {
        return StoreStationType::write_at_offset(address_domain, base, 0, value);
    }

    #[inline(always)]
    fn read_at_offset(address_domain: u32, base: StorageBaseAddress, offset: u8) -> SyscallResult<StationType> {
        let low = Store::<u128>::read_at_offset(address_domain, base, offset)?;

        return Result::Ok(StationType {
            cap: unpack_u128(low, packed::EXP2_0, packed::EXP2_20).try_into().unwrap(),
            recruitment: unpack_u128(low, packed::EXP2_20, packed::EXP2_1) == 1,
            efficiency: FixedTrait::new(unpack_u128(low, packed::EXP2_21, packed::EXP2_85).try_into().unwrap(), false)
        });
    }

    #[inline(always)]
    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: StationType
    ) -> SyscallResult<()> {
        let mut low: u128 = 0;
        let mut recruitment = 0;

        if value.recruitment {
            recruitment = 1;
        }

        pack_u128(ref low, packed::EXP2_0, packed::EXP2_20, value.cap.into());
        pack_u128(ref low, packed::EXP2_20, packed::EXP2_1, recruitment);
        pack_u128(ref low, packed::EXP2_21, packed::EXP2_85, value.efficiency.mag.into());

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

    use super::{StationType, StoreStationType};

    #[test]
    #[available_gas(500000)]
    fn test_storage() {
        let base = starknet::storage_base_address_from_felt252(42);
        let mut to_store = StationType { cap: 750000, recruitment: true, efficiency: FixedTrait::ONE() };

        StoreStationType::write(0, base, to_store);
        let mut to_read = StoreStationType::read(0, base).unwrap();
        assert(to_read.cap == 750000, 'wrong cap');
        assert(to_read.recruitment, 'wrong recruitment');
        assert(to_read.efficiency == FixedTrait::ONE(), 'wrong efficiency');
    }
}
