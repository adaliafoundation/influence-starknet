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
struct ContractPolicy {
    address: ContractAddress
}

impl ContractPolicyComponent of ComponentTrait<ContractPolicy> {
    fn name() -> felt252 {
        return 'ContractPolicy';
    }

    fn is_set(data: ContractPolicy) -> bool {
        return data.address.into() != 0;
    }

    fn version() -> u64 {
        return 0;
    }
}

trait ContractPolicyTrait {
    fn new(address: ContractAddress) -> ContractPolicy;
}

impl ContractPolicyImpl of ContractPolicyTrait {
    fn new(address: ContractAddress) -> ContractPolicy {
        return ContractPolicy { address: address };
    }
}

// Storage Access -----------------------------------------------------------------------------------------------------

impl StoreContractPolicy of Store<ContractPolicy> {
    #[inline(always)]
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<ContractPolicy> {
        return StoreContractPolicy::read_at_offset(address_domain, base, 0);
    }

    #[inline(always)]
    fn write(address_domain: u32, base: StorageBaseAddress, value: ContractPolicy) -> SyscallResult<()> {
        return StoreContractPolicy::write_at_offset(
            address_domain, base, 0, value
        );
    }

    #[inline(always)]
    fn read_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8
    ) -> SyscallResult<ContractPolicy> {
        let address = Store::<ContractAddress>::read_at_offset(
            address_domain, base, offset
        )?;

        return Result::Ok(ContractPolicy { address: address });
    }

    #[inline(always)]
    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: ContractPolicy
    ) -> SyscallResult<()> {
        return Store::<ContractAddress>::write_at_offset(
            address_domain, base, offset, value.address
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
    use array::{ArrayTrait, Span, SpanTrait};
    use core::starknet::SyscallResultTrait;
    use option::OptionTrait;
    use result::ResultTrait;
    use starknet::{ContractAddress, SyscallResult};
    use starknet::storage_access::{Store, StorageBaseAddress, storage_base_address_const};
    use traits::{Into, TryInto};

    use super::{ContractPolicy, ContractPolicyTrait};

    #[test]
    #[available_gas(1000000)]
    fn test_storage() {
        let access_policy = ContractPolicyTrait::new(starknet::contract_address_const::<42>());
        let base = starknet::storage_base_address_from_felt252(42);

        Store::<ContractPolicy>::write(0, base, access_policy);
        let mut read_policy = Store::<ContractPolicy>::read(0, base).unwrap_syscall();
        assert(read_policy.address == access_policy.address, 'contract address wrong');
    }
}
