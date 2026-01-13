use array::{ArrayTrait, Span, SpanTrait};
use core::starknet::SyscallResultTrait;
use option::OptionTrait;
use result::ResultTrait;
use starknet::{ContractAddress, SyscallResult};
use starknet::storage_access::{Store, StorageBaseAddress, storage_base_address_const};
use traits::{Into, TryInto};

use influence::common::{config::entities, packed};
use influence::components::{ComponentTrait, resolve};
use influence::types::entity::{Entity, EntityTrait, EntityIntoFelt252, Felt252TryIntoEntity};

#[derive(Copy, Drop, Serde)]
struct PublicPolicy {
    public: bool
}

impl PublicPolicyComponent of ComponentTrait<PublicPolicy> {
    fn name() -> felt252 {
        return 'PublicPolicy';
    }

    fn is_set(data: PublicPolicy) -> bool {
        return data.public;
    }

    fn version() -> u64 {
        return 0;
    }
}

trait PublicPolicyTrait {
    fn new(public: bool) -> PublicPolicy;
}

impl PublicPolicyImpl of PublicPolicyTrait {
    fn new(public: bool) -> PublicPolicy {
        return PublicPolicy { public: public };
    }
}

// Storage Access -----------------------------------------------------------------------------------------------------

impl StorePublicPolicy of Store<PublicPolicy> {
    #[inline(always)]
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<PublicPolicy> {
        return StorePublicPolicy::read_at_offset(address_domain, base, 0);
    }

    #[inline(always)]
    fn write(address_domain: u32, base: StorageBaseAddress, value: PublicPolicy) -> SyscallResult<()> {
        return StorePublicPolicy::write_at_offset(
            address_domain, base, 0, value
        );
    }

    #[inline(always)]
    fn read_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8
    ) -> SyscallResult<PublicPolicy> {
        let public = Store::<bool>::read_at_offset(address_domain, base, offset)?;
        return Result::Ok(PublicPolicy { public: public });
    }

    #[inline(always)]
    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: PublicPolicy
    ) -> SyscallResult<()> {
        return Store::<bool>::write_at_offset(address_domain, base, offset, value.public);
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
    use starknet::{ContractAddress, SyscallResult};
    use starknet::storage_access::{Store, StorageBaseAddress, storage_base_address_const};
    use traits::{Into, TryInto};

    use influence::common::{config::entities, packed};
    use influence::components::{ComponentTrait, resolve};
    use influence::types::entity::{Entity, EntityTrait, EntityIntoFelt252, Felt252TryIntoEntity};

    use super::{PublicPolicy, PublicPolicyTrait};

    #[test]
    #[available_gas(1000000)]
    fn test_storage() {
        let access_policy = PublicPolicyTrait::new(true);
        let base = starknet::storage_base_address_from_felt252(42);

        Store::<PublicPolicy>::write(0, base, access_policy);
        let mut read_policy = Store::<PublicPolicy>::read(0, base).unwrap_syscall();
        assert(read_policy.public, 'not set');
    }
}