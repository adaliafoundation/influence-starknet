use array::{ArrayTrait, Span, SpanTrait};
use core::starknet::SyscallResultTrait;
use option::OptionTrait;
use result::ResultTrait;
use starknet::SyscallResult;
use starknet::storage_access::{Store, StorageBaseAddress, storage_base_address_const};
use traits::{Into, TryInto};

use influence::common::{config::entities, packed};
use influence::components::{ComponentTrait, resolve};
use influence::types::entity::{Entity, EntityTrait};

#[derive(Copy, Drop, Serde)]
struct Location {
    location: Entity // ship -> building -> lot -> asteroid
}

impl LocationComponent of ComponentTrait<Location> {
    fn name() -> felt252 {
        return 'Location';
    }

    fn is_set(data: Location) -> bool {
        return !data.location.is_empty();
    }

    fn version() -> u64 {
        return 0;
    }
}

trait LocationTrait {
    fn new(entity: Entity) -> Location;
}

impl LocationImpl of LocationTrait {
    fn new(entity: Entity) -> Location {
        return Location { location: entity };
    }
}

// Storage Access -----------------------------------------------------------------------------------------------------

impl StoreLocation of Store<Location> {
    #[inline(always)]
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<Location> {
        return StoreLocation::read_at_offset(address_domain, base, 0);
    }

    #[inline(always)]
    fn write(address_domain: u32, base: StorageBaseAddress, value: Location) -> SyscallResult<()> {
        return StoreLocation::write_at_offset(address_domain, base, 0, value);
    }

    #[inline(always)]
    fn read_at_offset(address_domain: u32, base: StorageBaseAddress, offset: u8) -> SyscallResult<Location> {
        let res = Store::<u128>::read_at_offset(address_domain, base, offset)?;
        return Result::Ok(Location { location: res.try_into().unwrap() });
    }

    #[inline(always)]
    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: Location
    ) -> SyscallResult<()> {
        return Store::<u128>::write_at_offset(address_domain, base, offset, value.location.into());
    }

    #[inline(always)]
    fn size() -> u8 {
        return 1;
    }
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use core::starknet::SyscallResultTrait;
    use option::OptionTrait;
    use result::ResultTrait;
    use starknet::{Store, SyscallResult};

    use influence::config::entities;
    use influence::types::EntityTrait;

    use super::{Location, LocationTrait};

    #[test]
    #[available_gas(500000)]
    fn test_storage() {
        let base = starknet::storage_base_address_from_felt252(42);
        let asteroid = EntityTrait::new(entities::ASTEROID, 42);
        Store::<Location>::write(0, base, LocationTrait::new(asteroid));

        let read_location = Store::<Location>::read(0, base).unwrap_syscall();
        assert(read_location.location == asteroid, 'wrong location');
    }
}