use array::{ArrayTrait, Span, SpanTrait};
use core::starknet::SyscallResultTrait;
use option::OptionTrait;
use result::ResultTrait;
use starknet::SyscallResult;
use starknet::storage_access::{Store, StorageBaseAddress, storage_base_address_const};
use traits::{Into, TryInto};

use influence::components::{ComponentTrait, resolve};
use influence::config::entities;
use influence::types::string::{String, StringTrait};

// Constants ----------------------------------------------------------------------------------------------------------

#[derive(Copy, Drop, Serde)]
struct Config {
    min: u8,
    max: u8,
    alpha: bool,
    num: bool,
    sym: bool,
    rewrite: bool
}

fn config(t: u64) -> Config {
    if t == entities::ASTEROID { return Config { min: 4, max: 28, alpha: true, num: true, sym: true, rewrite: true }; }
    if t == entities::BUILDING { return Config { min: 4, max: 28, alpha: true, num: true, sym: true, rewrite: true }; }
    if t == entities::CREW { return Config { min: 4, max: 28, alpha: true, num: false, sym: true, rewrite: true }; }
    if t == entities::CREWMATE { return Config { min: 4, max: 28, alpha: true, num: false, sym: true, rewrite: false }; }
    if t == entities::SHIP { return Config { min: 4, max: 28, alpha: true, num: true, sym: true, rewrite: true }; }

    assert(false, 'invalid name type');
    return Config { min: 0, max: 0, alpha: false, num: false, sym: false, rewrite: false };
}

// Component ----------------------------------------------------------------------------------------------------------

#[derive(Copy, Drop, Serde)]
struct Name {
    name: String
}

impl NameComponent of ComponentTrait<Name> {
    fn name() -> felt252 {
        return 'Name';
    }

    fn is_set(data: Name) -> bool {
        return !data.name.is_empty();
    }

    fn version() -> u64 {
        return 0;
    }
}

trait NameTrait {
    fn new(name: String) -> Name;
    fn config(entity: u64) -> Config;
}

impl NameImpl of NameTrait {
    fn new(name: String) -> Name {
        return Name { name: name };
    }

    fn config(entity: u64) -> Config {
        return config(entity);
    }
}

// Storage Access -----------------------------------------------------------------------------------------------------

impl StoreName of Store<Name> {
    #[inline(always)]
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<Name> {
        return StoreName::read_at_offset(address_domain, base, 0);
    }

    #[inline(always)]
    fn write(address_domain: u32, base: StorageBaseAddress, value: Name) -> SyscallResult<()> {
        return StoreName::write_at_offset(address_domain, base, 0, value);
    }

    #[inline(always)]
    fn read_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8
    ) -> SyscallResult<Name> {
        return Result::Ok(Name {
            name: StringTrait::new(
                Store::<felt252>::read_at_offset(address_domain, base, offset
            )?),
        });
    }

    #[inline(always)]
    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: Name
    ) -> SyscallResult<()> {
        return Store::<felt252>::write_at_offset(
            address_domain, base, offset, value.name.value.try_into().unwrap()
        );
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
    use influence::types::{EntityTrait, StringTrait};

    use super::Name;

    #[test]
    #[available_gas(500000)]
    fn test_storage() {
        let base = starknet::storage_base_address_from_felt252(42);
        let asteroid = EntityTrait::new(entities::ASTEROID, 42);
        Store::<Name>::write(0, base, Name { name: StringTrait::new('Adalia Prime') });

        let read_name = Store::<Name>::read(0, base).unwrap_syscall();
        assert(read_name.name == StringTrait::new('Adalia Prime'), 'wrong name');
    }
}
