use array::{ArrayTrait, SpanTrait};
use core::starknet::SyscallResultTrait;
use option::OptionTrait;
use result::ResultTrait;
use starknet::SyscallResult;
use starknet::storage_access::{Store, StorageBaseAddress, storage_base_address_const};
use traits::{Into, TryInto};

use influence::common::{packed, packed::{pack_u128, unpack_u128}};
use influence::components::{ComponentTrait, get};
use influence::config::errors;
use influence::types::entity::{Entity, EntityTrait, Felt252TryIntoEntity};

// Constants ----------------------------------------------------------------------------------------------------------

mod types {
    const BASIC: u64 = 1;
}

// Component ----------------------------------------------------------------------------------------------------------

#[derive(Copy, Drop, Serde)]
struct ExchangeType {
    allowed_products: u64
}

impl ExchangeTypeComponent of ComponentTrait<ExchangeType> {
    fn name() -> felt252 {
        return 'ExchangeType';
    }

    fn is_set(data: ExchangeType) -> bool {
        return data.allowed_products != 0;
    }

    fn version() -> u64 {
        return 0;
    }
}

trait ExchangeTypeTrait {
    fn by_type(id: u64) -> ExchangeType;
}

impl ExchangeTypeImpl of ExchangeTypeTrait {
    fn by_type(id: u64) -> ExchangeType {
        let mut path: Array<felt252> = Default::default();
        path.append(id.into());
        return get(path.span()).expect(errors::EXCHANGE_TYPE_NOT_FOUND);
    }
}

// Storage Access -----------------------------------------------------------------------------------------------------

impl StoreExchangeType of Store<ExchangeType> {
    #[inline(always)]
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<ExchangeType> {
        return StoreExchangeType::read_at_offset(address_domain, base, 0);
    }

    #[inline(always)]
    fn write(address_domain: u32, base: StorageBaseAddress, value: ExchangeType) -> SyscallResult<()> {
        return StoreExchangeType::write_at_offset(address_domain, base, 0, value);
    }

    #[inline(always)]
    fn read_at_offset(address_domain: u32, base: StorageBaseAddress, offset: u8) -> SyscallResult<ExchangeType> {
        let low = Store::<u128>::read_at_offset(address_domain, base, offset)?;

        return Result::Ok(ExchangeType {
            allowed_products: unpack_u128(low, packed::EXP2_0, packed::EXP2_16).try_into().unwrap()
        });
    }

    #[inline(always)]
    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: ExchangeType
    ) -> SyscallResult<()> {
        let mut low: u128 = 0;

        pack_u128(ref low, packed::EXP2_0, packed::EXP2_16, value.allowed_products.into());

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

    use super::{ExchangeType, StoreExchangeType};

    #[test]
    #[available_gas(500000)]
    fn test_storage() {
        let base = starknet::storage_base_address_from_felt252(42);
        let mut to_store = ExchangeType { allowed_products: 65000 };

        StoreExchangeType::write(0, base, to_store);
        let mut to_read = StoreExchangeType::read(0, base).unwrap();
        assert(to_read.allowed_products == 65000, 'wrong allowed_products');
    }
}
