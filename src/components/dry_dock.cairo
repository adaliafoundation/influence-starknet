use array::{ArrayTrait, SpanTrait};
use core::starknet::SyscallResultTrait;
use option::OptionTrait;
use result::ResultTrait;
use starknet::SyscallResult;
use starknet::storage_access::{Store, StorageBaseAddress, storage_base_address_const};
use traits::{Into, TryInto};

use influence::common::{packed, packed::{pack_u128, split_felt252, unpack_u128}};
use influence::components::{ComponentTrait, resolve};
use influence::config::errors;
use influence::types::entity::{Entity, EntityTrait, Felt252TryIntoEntity};

// Constants ----------------------------------------------------------------------------------------------------------

mod statuses {
    const IDLE: u64 = 0;
    const RUNNING: u64 = 1;
}

// Component ----------------------------------------------------------------------------------------------------------

#[derive(Copy, Drop, Serde)]
struct DryDock {
    dry_dock_type: u64,
    status: u64,
    output_ship: Entity,
    finish_time: u64
}

impl DryDockComponent of ComponentTrait<DryDock> {
    fn name() -> felt252 {
        return 'DryDock';
    }

    fn is_set(data: DryDock) -> bool {
        return data.dry_dock_type != 0;
    }

    fn version() -> u64 {
        return 0;
    }
}

trait DryDockTrait {
    fn new(dry_dock_type: u64) -> DryDock;
    fn assert_ready(self: DryDock, now: u64);
}

impl DryDockImpl of DryDockTrait {
    fn new(dry_dock_type: u64) -> DryDock {
        return DryDock {
            dry_dock_type: dry_dock_type,
            status: statuses::IDLE,
            output_ship: EntityTrait::new(0, 0),
            finish_time: 0
        };
    }

    fn assert_ready(self: DryDock, now: u64) {
        assert(self.status == statuses::IDLE && self.finish_time <= now, errors::INCORRECT_STATUS);
    }
}

// Storage Access -----------------------------------------------------------------------------------------------------

impl StoreDryDock of Store<DryDock> {
    #[inline(always)]
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<DryDock> {
        return StoreDryDock::read_at_offset(address_domain, base, 0);
    }

    #[inline(always)]
    fn write(address_domain: u32, base: StorageBaseAddress, value: DryDock) -> SyscallResult<()> {
        return StoreDryDock::write_at_offset(address_domain, base, 0, value);
    }

    #[inline(always)]
    fn read_at_offset(address_domain: u32, base: StorageBaseAddress, offset: u8) -> SyscallResult<DryDock> {
        let combined = Store::<felt252>::read_at_offset(address_domain, base, offset)?;
        let (low, high) = split_felt252(combined);

        return Result::Ok(DryDock {
            dry_dock_type: unpack_u128(low, packed::EXP2_0, packed::EXP2_16).try_into().unwrap(),
            status: unpack_u128(low, packed::EXP2_16, packed::EXP2_4).try_into().unwrap(),
            output_ship: unpack_u128(low, packed::EXP2_20, packed::EXP2_80).try_into().unwrap(),
            finish_time: unpack_u128(high, packed::EXP2_0, packed::EXP2_36).try_into().unwrap()
        });
    }

    #[inline(always)]
    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: DryDock
    ) -> SyscallResult<()> {
        let mut low: u128 = 0;
        let mut high: u128 = 0;

        pack_u128(ref low, packed::EXP2_0, packed::EXP2_16, value.dry_dock_type.into());
        pack_u128(ref low, packed::EXP2_16, packed::EXP2_4, value.status.into());
        pack_u128(ref low, packed::EXP2_20, packed::EXP2_80, value.output_ship.into());
        pack_u128(ref high, packed::EXP2_0, packed::EXP2_36, value.finish_time.into());

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
    use option::OptionTrait;
    use result::ResultTrait;
    use starknet::{SyscallResult, SyscallResultTrait, Store, StorageBaseAddress, storage_base_address_const};
    use traits::{Into, TryInto};

    use influence::components::dry_dock_type::types;
    use influence::config::entities;
    use influence::types::EntityTrait;

    use super::{DryDock, DryDockTrait, StoreDryDock, statuses};

    #[test]
    #[available_gas(500000)]
    fn test_storage() {
        let base = starknet::storage_base_address_from_felt252(42);
        let mut dry_dock = DryDock {
            dry_dock_type: types::BASIC,
            status: statuses::IDLE,
            output_ship: EntityTrait::new(entities::SHIP, 25),
            finish_time: 0
        };

        StoreDryDock::write(0, base, dry_dock);
        let mut read_dry_dock = StoreDryDock::read(0, base).unwrap();
        assert(read_dry_dock.dry_dock_type == types::BASIC, 'wrong type');
        assert(read_dry_dock.status == statuses::IDLE, 'wrong status');
        assert(read_dry_dock.output_ship == EntityTrait::new(entities::SHIP, 25), 'wrong output ship');
    }
}