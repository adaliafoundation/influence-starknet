use array::{ArrayTrait, Span, SpanTrait};
use core::starknet::SyscallResultTrait;
use option::OptionTrait;
use result::ResultTrait;
use starknet::{ContractAddress, Felt252TryIntoContractAddress, SyscallResult};
use starknet::storage_access::{Store, StorageBaseAddress, storage_base_address_const};
use traits::{Into, TryInto};

use influence::components::{ComponentTrait, resolve};

#[derive(Copy, Drop, Serde)]
struct Unique {
    unique: felt252
}

impl UniqueComponent of ComponentTrait<Unique> {
    fn name() -> felt252 {
        return 'Unique';
    }

    fn is_set(data: Unique) -> bool {
        return data.unique != 0;
    }

    fn version() -> u64 {
        return 0;
    }
}

trait UniqueTrait {
    fn new() -> Unique;
}

impl UniqueImpl of UniqueTrait {
    fn new() -> Unique {
        return Unique { unique: 1 };
    }
}

// Storage Access -----------------------------------------------------------------------------------------------------

impl StoreUnique of Store<Unique> {
    #[inline(always)]
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<Unique> {
        return StoreUnique::read_at_offset(address_domain, base, 0);
    }

    #[inline(always)]
    fn write(address_domain: u32, base: StorageBaseAddress, value: Unique) -> SyscallResult<()> {
        return StoreUnique::write_at_offset(address_domain, base, 0, value);
    }

    #[inline(always)]
    fn read_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8
    ) -> SyscallResult<Unique> {
        let res = Store::<felt252>::read_at_offset(address_domain, base, offset)?;
        return Result::Ok(Unique { unique: res });
    }

    #[inline(always)]
    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: Unique
    ) -> SyscallResult<()> {
        return Store::<felt252>::write_at_offset(address_domain, base, offset, value.unique);
    }

    #[inline(always)]
    fn size() -> u8 {
        return 1;
    }
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use option::OptionTrait;
    use result::ResultTrait;
    use starknet::Store;

    use influence::config::entities;
    use influence::types::entity::EntityTrait;

    use super::Unique;

    #[test]
    #[available_gas(1000000)]
    fn test_storage() {
        let base = starknet::storage_base_address_from_felt252(42);
        let unique = Unique { unique: 1 };

        Store::<Unique>::write(0, base, unique);
        let read_unique = Store::<Unique>::read(0, base).unwrap();
        assert(read_unique.unique == 1, 'wrong unique value');
    }
}
