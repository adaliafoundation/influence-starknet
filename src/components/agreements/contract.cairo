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
struct ContractAgreement {
    address: ContractAddress
}

impl ContractAgreementComponent of ComponentTrait<ContractAgreement> {
    fn name() -> felt252 {
        return 'ContractAgreement';
    }

    fn is_set(data: ContractAgreement) -> bool {
        return data.address.into() != 0;
    }

    fn version() -> u64 {
        return 0;
    }
}

trait ContractAgreementTrait {
    fn new(address: ContractAddress) -> ContractAgreement;
}

impl ContractAgreementImpl of ContractAgreementTrait {
    fn new(address: ContractAddress) -> ContractAgreement {
        return ContractAgreement { address: address };
    }
}

// Storage Access -----------------------------------------------------------------------------------------------------

impl StoreContractAgreement of Store<ContractAgreement> {
    #[inline(always)]
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<ContractAgreement> {
        return StoreContractAgreement::read_at_offset(address_domain, base, 0);
    }

    #[inline(always)]
    fn write(address_domain: u32, base: StorageBaseAddress, value: ContractAgreement) -> SyscallResult<()> {
        return StoreContractAgreement::write_at_offset(
            address_domain, base, 0, value
        );
    }

    #[inline(always)]
    fn read_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8
    ) -> SyscallResult<ContractAgreement> {
        let address = Store::<ContractAddress>::read_at_offset(
            address_domain, base, offset
        )?;

        return Result::Ok(ContractAgreement { address: address });
    }

    #[inline(always)]
    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: ContractAgreement
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

    use influence::common::{config::entities, packed};
    use influence::components::{ComponentTrait, resolve};
    use influence::types::entity::{Entity, EntityTrait, EntityIntoFelt252, Felt252TryIntoEntity};

    use super::{ContractAgreement, ContractAgreementTrait};

    #[test]
    #[available_gas(1000000)]
    fn test_storage() {
        let access_policy = ContractAgreementTrait::new(starknet::contract_address_const::<42>());
        let base = starknet::storage_base_address_from_felt252(42);

        Store::<ContractAgreement>::write(0, base, access_policy);
        let mut read_policy = Store::<ContractAgreement>::read(0, base).unwrap_syscall();
        assert(read_policy.address == access_policy.address, 'contract address wrong');
    }
}