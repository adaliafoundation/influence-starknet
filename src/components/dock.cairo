use array::{ArrayTrait, SpanTrait};
use core::starknet::SyscallResultTrait;
use option::OptionTrait;
use result::ResultTrait;
use starknet::SyscallResult;
use starknet::storage_access::{Store, StorageBaseAddress, storage_base_address_const};
use traits::{Into, TryInto};

use influence::common::{packed, packed::{pack_u128, unpack_u128}};
use influence::components::{ComponentTrait, resolve};
use influence::types::entity::{Entity, EntityTrait, Felt252TryIntoEntity};

// Component ----------------------------------------------------------------------------------------------------------

#[derive(Copy, Drop, Serde)]
struct Dock {
    dock_type: u64,
    docked_ships: u64, // current # of docked ships
    ready_at: u64 // when the next ship can arrive or depart
}

impl DockComponent of ComponentTrait<Dock> {
    fn name() -> felt252 {
        return 'Dock';
    }

    fn is_set(data: Dock) -> bool {
        return data.dock_type != 0;
    }

    fn version() -> u64 {
        return 0;
    }
}

trait DockTrait {
    fn new(dock_type: u64) -> Dock;
    fn assert_empty(self: Dock);
}

impl DockImpl of DockTrait {
    fn new(dock_type: u64) -> Dock {
        return Dock { dock_type: dock_type, docked_ships: 0, ready_at: 0 };
    }

    fn assert_empty(self: Dock) {
        assert(self.docked_ships == 0, 'dock is not empty');
    }
}

// Storage Access -----------------------------------------------------------------------------------------------------

impl StoreDock of Store<Dock> {
    #[inline(always)]
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<Dock> {
        return StoreDock::read_at_offset(address_domain, base, 0);
    }

    #[inline(always)]
    fn write(address_domain: u32, base: StorageBaseAddress, value: Dock) -> SyscallResult<()> {
        return StoreDock::write_at_offset(address_domain, base, 0, value);
    }

    #[inline(always)]
    fn read_at_offset(address_domain: u32, base: StorageBaseAddress, offset: u8) -> SyscallResult<Dock> {
        let low = Store::<u128>::read_at_offset(address_domain, base, offset)?;

        return Result::Ok(Dock {
            dock_type: unpack_u128(low, packed::EXP2_0, packed::EXP2_16).try_into().unwrap(),
            docked_ships: unpack_u128(low, packed::EXP2_16, packed::EXP2_16).try_into().unwrap(),
            ready_at: unpack_u128(low, packed::EXP2_32, packed::EXP2_36).try_into().unwrap()
        });
    }

    #[inline(always)]
    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: Dock
    ) -> SyscallResult<()> {
        let mut low: u128 = 0;

        pack_u128(ref low, packed::EXP2_0, packed::EXP2_16, value.dock_type.into());
        pack_u128(ref low, packed::EXP2_16, packed::EXP2_16, value.docked_ships.into());
        pack_u128(ref low, packed::EXP2_32, packed::EXP2_36, value.ready_at.into());

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

    use super::{Dock, DockTrait, StoreDock};

    #[test]
    #[available_gas(500000)]
    fn test_storage() {
        let base = starknet::storage_base_address_from_felt252(42);
        let mut dock = DockTrait::new(1);

        StoreDock::write(0, base, dock);
        let mut read_dock = StoreDock::read(0, base).unwrap();
        assert(read_dock.docked_ships == 0, 'wrong docked ships');

        dock.docked_ships = 50;
        dock.ready_at = 68719476735;
        StoreDock::write(0, base, dock);
        read_dock = StoreDock::read(0, base).unwrap();
        assert(read_dock.docked_ships == 50, 'wrong num ships');
        assert(read_dock.ready_at == 68719476735, 'wrong ready at');
    }
}