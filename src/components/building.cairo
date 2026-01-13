use array::{ArrayTrait, SpanTrait};
use core::starknet::SyscallResultTrait;
use option::OptionTrait;
use result::ResultTrait;
use starknet::SyscallResult;
use starknet::storage_access::{Store, StorageBaseAddress, storage_base_address_const};
use traits::{Into, TryInto};

use influence::common::{packed, packed::{pack_u128, unpack_u128}};
use influence::config::{entities, errors, get};
use influence::components::ComponentTrait;
use influence::types::entity::{Entity, EntityTrait, Felt252TryIntoEntity};

// Constants ----------------------------------------------------------------------------------------------------------

mod statuses {
    const UNPLANNED: u64 = 0;
    const PLANNED: u64 = 1;
    const UNDER_CONSTRUCTION: u64 = 2;
    const OPERATIONAL: u64 = 3;
}

// Component ----------------------------------------------------------------------------------------------------------

#[derive(Copy, Drop, Serde)]
struct Building {
    status: u64,
    building_type: u64,
    planned_at: u64, // time construction started
    finish_time: u64 // time construction will finish
}

impl BuildingComponent of ComponentTrait<Building> {
    fn name() -> felt252 {
        return 'Building';
    }

    fn is_set(data: Building) -> bool {
        return data.building_type != 0;
    }

    fn version() -> u64 {
        return 0;
    }
}

trait BuildingTrait {
    fn new(building_type: u64, planned_at: u64) -> Building;
    fn assert_planned(self: Building);
    fn assert_completed(self: Building, now: u64);
    fn assert_operational(self: Building);
}

impl BuildingImpl of BuildingTrait {
    fn new(building_type: u64, planned_at: u64) -> Building {
        return Building {
            status: statuses::PLANNED,
            building_type: building_type,
            planned_at: planned_at,
            finish_time: 0
        };
    }

    fn assert_planned(self: Building) {
        assert(self.status == statuses::PLANNED, errors::INCORRECT_STATUS);
    }

    fn assert_completed(self: Building, now: u64) {
        assert(self.status == statuses::UNDER_CONSTRUCTION, errors::INCORRECT_STATUS);
        assert(self.finish_time <= now, errors::FINISH_TIME_NOT_REACHED);
    }

    fn assert_operational(self: Building) {
        assert(self.status == statuses::OPERATIONAL, errors::INCORRECT_STATUS);
    }
}

// Storage Access -----------------------------------------------------------------------------------------------------

impl StoreBuilding of Store<Building> {
    #[inline(always)]
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<Building> {
        return StoreBuilding::read_at_offset(address_domain, base, 0);
    }

    #[inline(always)]
    fn write(address_domain: u32, base: StorageBaseAddress, value: Building) -> SyscallResult<()> {
        return StoreBuilding::write_at_offset(
            address_domain, base, 0, value
        );
    }

    #[inline(always)]
    fn read_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8
    ) -> SyscallResult<Building> {
        let low = Store::<u128>::read_at_offset(address_domain, base, offset)?;

        return Result::Ok(Building {
            status: unpack_u128(low, packed::EXP2_0, packed::EXP2_4).try_into().unwrap(),
            building_type: unpack_u128(low, packed::EXP2_4, packed::EXP2_16).try_into().unwrap(),
            planned_at: unpack_u128(low, packed::EXP2_20, packed::EXP2_36).try_into().unwrap(),
            finish_time: unpack_u128(low, packed::EXP2_56, packed::EXP2_36).try_into().unwrap()
        });
    }

    #[inline(always)]
    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: Building
    ) -> SyscallResult<()> {
        let mut low: u128 = 0;
        pack_u128(ref low, packed::EXP2_0, packed::EXP2_4, value.status.into());
        pack_u128(ref low, packed::EXP2_4, packed::EXP2_16, value.building_type.into());
        pack_u128(ref low, packed::EXP2_20, packed::EXP2_36, value.planned_at.into());
        pack_u128(ref low, packed::EXP2_56, packed::EXP2_36, value.finish_time.into());
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

    use influence::common::packed;
    use influence::config::{entities, errors};
    use influence::components::{ComponentTrait, building_type::types as building_types};
    use influence::types::entity::{Entity, EntityTrait, Felt252TryIntoEntity};

    use super::{Building, BuildingTrait, statuses};

    #[test]
    #[available_gas(500000)]
    fn test_storage() {
        let base = starknet::storage_base_address_from_felt252(42);
        let entity = EntityTrait::new(entities::BUILDING, 1);
        let mut building = BuildingTrait::new(building_types::EXTRACTOR, 1234);

        Store::<Building>::write(0, base, building);
        let mut read_building = Store::<Building>::read(0, base).unwrap_syscall();
        assert(read_building.status == statuses::PLANNED, 'wrong status');
        assert(read_building.building_type == building_types::EXTRACTOR, 'wrong building_type');
        assert(read_building.planned_at == 1234, 'wrong planned_at');
        assert(read_building.finish_time == 0, 'wrong finish_time');
    }
}