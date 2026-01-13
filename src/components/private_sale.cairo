use array::{ArrayTrait, SpanTrait};
use core::starknet::SyscallResultTrait;
use option::OptionTrait;
use result::ResultTrait;
use starknet::SyscallResult;
use starknet::storage_access::{Store, StorageBaseAddress, storage_base_address_const};
use traits::{Into, TryInto};

use influence::common::{config::entities, packed, packed::{pack_u128, unpack_u128}};
use influence::components::{ComponentTrait, resolve};
use influence::types::entity::{Entity, EntityTrait, Felt252TryIntoEntity};

mod statuses {
    const CLOSED: u64 = 0;
    const OPEN: u64 = 1;
}

#[derive(Copy, Drop, Serde)]
struct PrivateSale {
    status: u64,
    amount: u64
}

impl PrivateSaleComponent of ComponentTrait<PrivateSale> {
    fn name() -> felt252 {
        return 'PrivateSale';
    }

    fn is_set(data: PrivateSale) -> bool {
        return data.status != statuses::CLOSED;
    }

    fn version() -> u64 {
        return 0;
    }
}

trait PrivateSaleTrait {
    fn new(amount: u64) -> PrivateSale;
}

impl PrivateSaleImpl of PrivateSaleTrait {
    fn new(amount: u64) -> PrivateSale {
        return PrivateSale {
            status: statuses::OPEN,
            amount: amount
        };
    }
}

// Storage Access -----------------------------------------------------------------------------------------------------

impl StorePrivateSale of Store<PrivateSale> {
    #[inline(always)]
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<PrivateSale> {
        return StorePrivateSale::read_at_offset(address_domain, base, 0);
    }

    #[inline(always)]
    fn write(address_domain: u32, base: StorageBaseAddress, value: PrivateSale) -> SyscallResult<()> {
        return StorePrivateSale::write_at_offset(address_domain, base, 0, value);
    }

    #[inline(always)]
    fn read_at_offset(address_domain: u32, base: StorageBaseAddress, offset: u8) -> SyscallResult<PrivateSale> {
        let low = Store::<u128>::read_at_offset(address_domain, base, offset)?;

        return Result::Ok(PrivateSale {
            status: unpack_u128(low, packed::EXP2_0, packed::EXP2_4).try_into().unwrap(),
            amount: unpack_u128(low, packed::EXP2_4, packed::EXP2_80).try_into().unwrap()
        });
    }

    #[inline(always)]
    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: PrivateSale
    ) -> SyscallResult<()> {
        let mut low: u128 = 0;

        pack_u128(ref low, packed::EXP2_0, packed::EXP2_4, value.status.into());
        pack_u128(ref low, packed::EXP2_4, packed::EXP2_80, value.amount.into());

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

    use influence::common::{config::entities, packed};
    use influence::components::{ComponentTrait, resolve};
    use influence::types::entity::{Entity, EntityTrait, Felt252TryIntoEntity};

    use super::{PrivateSale, statuses};

    #[test]
    #[available_gas(500000)]
    fn test_storage() {
        let base = starknet::storage_base_address_from_felt252(42);
        let sale = PrivateSale { status: statuses::OPEN, amount: 5678 };

        let entity = EntityTrait::new(entities::SHIP, 1);
        Store::<PrivateSale>::write(0, base, sale);
        let read_sale = Store::<PrivateSale>::read(0, base).unwrap();
        assert(read_sale.status == statuses::OPEN, 'status wrong');
        assert(read_sale.amount == 5678, 'amount wrong');
    }
}
