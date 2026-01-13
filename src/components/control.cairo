use array::{ArrayTrait, Span, SpanTrait};
use core::starknet::SyscallResultTrait;
use option::OptionTrait;
use result::ResultTrait;
use starknet::SyscallResult;
use starknet::storage_access::{Store, StorageBaseAddress, storage_base_address_const};
use traits::{Into, TryInto};

use influence::common::{config::entities, packed};
use influence::components::{ComponentTrait, resolve};
use influence::types::entity::{Entity, EntityTrait, EntityIntoFelt252, Felt252TryIntoEntity};

#[derive(Copy, Drop, Serde)]
struct Control {
    controller: Entity
}

impl ControlComponent of ComponentTrait<Control> {
    fn name() -> felt252 {
        return 'Control';
    }

    fn is_set(data: Control) -> bool {
        return !data.controller.is_empty();
    }

    fn version() -> u64 {
        return 0;
    }
}

trait ControlTrait {
    fn new(entity: Entity) -> Control;
}

impl ControlImpl of ControlTrait {
    fn new(entity: Entity) -> Control {
        return Control { controller: entity };
    }
}

// Storage Access -----------------------------------------------------------------------------------------------------

impl StoreControl of Store<Control> {
    #[inline(always)]
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<Control> {
        return StoreControl::read_at_offset(address_domain, base, 0);
    }

    #[inline(always)]
    fn write(address_domain: u32, base: StorageBaseAddress, value: Control) -> SyscallResult<()> {
        return StoreControl::write_at_offset(address_domain, base, 0, value);
    }

    #[inline(always)]
    fn read_at_offset(address_domain: u32, base: StorageBaseAddress, offset: u8) -> SyscallResult<Control> {
        let res = Store::<u128>::read_at_offset(address_domain, base, offset)?;
        return Result::Ok(Control { controller: res.try_into().unwrap() });
    }

    #[inline(always)]
    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: Control
    ) -> SyscallResult<()> {
        return Store::<u128>::write_at_offset(address_domain, base, offset, value.controller.into());
    }

    #[inline(always)]
    fn size() -> u8 {
        return 1;
    }
}

// Tests --------------------------------------------------------------------------------------------------------------
#[cfg(test)]
mod tests {
    use array::{ArrayTrait, Span, SpanTrait};
    use core::starknet::SyscallResultTrait;
    use option::OptionTrait;
    use result::ResultTrait;
    use starknet::SyscallResult;
    use starknet::storage_access::{Store, StorageBaseAddress, storage_base_address_const};
    use traits::{Into, TryInto};

    use influence::common::{config::entities, packed};
    use influence::components::{ComponentTrait, resolve};
    use influence::types::entity::{Entity, EntityTrait, EntityIntoFelt252, Felt252TryIntoEntity};

    use super::{ControlTrait, ControlImpl, ControlComponent, Control, StoreControl};

    #[test]
    #[available_gas(1000000)]
    fn test_storage() {
        let crew = EntityTrait::new(entities::CREW, 42);
        let control = ControlTrait::new(crew);
        let base = starknet::storage_base_address_from_felt252(42);

        // Should now be controlled
        Store::<Control>::write(0, base, control);
        let mut read_control = Store::<Control>::read(0, base).unwrap_syscall();
        assert(read_control.controller == crew, 'should be controlled');

        // Clear control and check
        let empty_entity: Entity = Default::default();
        let empty_control = ControlTrait::new(empty_entity);
        Store::<Control>::write(0, base, empty_control);
        read_control = Store::<Control>::read(0, base).unwrap_syscall();
        assert(read_control.controller.id == 0, 'should not be controlled');
    }
}
