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
struct WhitelistAgreement {
    whitelisted: bool
}

impl WhitelistAgreementComponent of ComponentTrait<WhitelistAgreement> {
    fn name() -> felt252 {
        return 'WhitelistAgreement';
    }

    fn is_set(data: WhitelistAgreement) -> bool {
        return data.whitelisted;
    }

    fn version() -> u64 {
        return 0;
    }
}

trait WhitelistAgreementTrait {
    fn new(whitelisted: bool) -> WhitelistAgreement;
}

impl WhitelistAgreementImpl of WhitelistAgreementTrait {
    fn new(whitelisted: bool) -> WhitelistAgreement {
        return WhitelistAgreement { whitelisted: whitelisted };
    }
}

// Storage Access -----------------------------------------------------------------------------------------------------

impl StoreWhitelistAgreement of Store<WhitelistAgreement> {
    #[inline(always)]
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<WhitelistAgreement> {
        return StoreWhitelistAgreement::read_at_offset(address_domain, base, 0);
    }

    #[inline(always)]
    fn write(address_domain: u32, base: StorageBaseAddress, value: WhitelistAgreement) -> SyscallResult<()> {
        return StoreWhitelistAgreement::write_at_offset(
            address_domain, base, 0, value
        );
    }

    #[inline(always)]
    fn read_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8
    ) -> SyscallResult<WhitelistAgreement> {
        let res = Store::<bool>::read_at_offset(address_domain, base, offset)?;
        return Result::Ok(WhitelistAgreement { whitelisted: res });
    }

    #[inline(always)]
    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: WhitelistAgreement
    ) -> SyscallResult<()> {
        return Store::<bool>::write_at_offset(address_domain, base, offset, value.whitelisted);
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

    use super::{WhitelistAgreement, WhitelistAgreementTrait};

    #[test]
    #[available_gas(1000000)]
    fn test_storage() {
        let mut agreement = WhitelistAgreementTrait::new(true);
        let base = starknet::storage_base_address_from_felt252(42);

        Store::<WhitelistAgreement>::write(0, base, agreement);
        let mut read_agreement = Store::<WhitelistAgreement>::read(0, base).unwrap_syscall();
        assert(read_agreement.whitelisted, 'should be whitelisted');
    }
}