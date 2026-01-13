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
    const WAREHOUSE: u64 = 1;
    const EXTRACTOR: u64 = 2;
    const REFINERY: u64 = 3;
    const BIOREACTOR: u64 = 4;
    const FACTORY: u64 = 5;
    const SHIPYARD: u64 = 6;
    const SPACEPORT: u64 = 7;
    const MARKETPLACE: u64 = 8;
    const HABITAT: u64 = 9;
    const TANK_FARM: u64 = 10;
}

// Component ----------------------------------------------------------------------------------------------------------

#[derive(Copy, Drop, Serde)]
struct BuildingType {
    process_type: u64, // process type
    site_slot: u64, // site slot
    site_type: u64 // inventory type
}

impl BuildingTypeComponent of ComponentTrait<BuildingType> {
    fn name() -> felt252 {
        return 'BuildingType';
    }

    fn is_set(data: BuildingType) -> bool {
        return data.process_type != 0;
    }

    fn version() -> u64 {
        return 0;
    }
}

trait BuildingTypeTrait {
    fn by_type(id: u64) -> BuildingType;
}

impl BuildingTypeImpl of BuildingTypeTrait {
    fn by_type(id: u64) -> BuildingType {
        let mut path: Array<felt252> = Default::default();
        path.append(id.into());
        return get(path.span()).expect(errors::BUILDING_TYPE_NOT_FOUND);
    }
}

// Storage Access -----------------------------------------------------------------------------------------------------

impl StoreBuildingType of Store<BuildingType> {
    #[inline(always)]
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<BuildingType> {
        return StoreBuildingType::read_at_offset(address_domain, base, 0);
    }

    #[inline(always)]
    fn write(address_domain: u32, base: StorageBaseAddress, value: BuildingType) -> SyscallResult<()> {
        return StoreBuildingType::write_at_offset(address_domain, base, 0, value);
    }

    #[inline(always)]
    fn read_at_offset(address_domain: u32, base: StorageBaseAddress, offset: u8) -> SyscallResult<BuildingType> {
        let low = Store::<u128>::read_at_offset(address_domain, base, offset)?;

        return Result::Ok(BuildingType {
            process_type: unpack_u128(low, packed::EXP2_0, packed::EXP2_18).try_into().unwrap(),
            site_slot: unpack_u128(low, packed::EXP2_18, packed::EXP2_8).try_into().unwrap(),
            site_type: unpack_u128(low, packed::EXP2_26, packed::EXP2_18).try_into().unwrap()
        });
    }

    #[inline(always)]
    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: BuildingType
    ) -> SyscallResult<()> {
        let mut low: u128 = 0;

        pack_u128(ref low, packed::EXP2_0, packed::EXP2_18, value.process_type.into());
        pack_u128(ref low, packed::EXP2_18, packed::EXP2_8, value.site_slot.into());
        pack_u128(ref low, packed::EXP2_26, packed::EXP2_18, value.site_type.into());

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

    use super::{BuildingType, StoreBuildingType};

    #[test]
    #[available_gas(500000)]
    fn test_storage() {
        let base = starknet::storage_base_address_from_felt252(42);
        let mut to_store = BuildingType { process_type: 1234, site_slot: 255, site_type: 3456 };

        StoreBuildingType::write(0, base, to_store);
        let mut to_read = StoreBuildingType::read(0, base).unwrap();
        assert(to_read.process_type == 1234, 'wrong process');
        assert(to_read.site_slot == 255, 'wrong site_slot');
        assert(to_read.site_type == 3456, 'wrong site_type');
    }
}
