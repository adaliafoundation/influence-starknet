use array::{ArrayTrait, Span, SpanTrait};
use core::starknet::SyscallResultTrait;
use option::OptionTrait;
use result::ResultTrait;
use starknet::SyscallResult;
use starknet::storage_access::{Store, StorageBaseAddress, storage_base_address_const};
use traits::{Into, TryInto};

use influence::common::{config::entities, packed, packed::{split_felt252, pack_u128, unpack_u128}};
use influence::components::{ComponentTrait, resolve};
use influence::types::entity::{Entity, EntityTrait, EntityIntoFelt252, Felt252TryIntoEntity};

// Constants ----------------------------------------------------------------------------------------------------------

mod statuses {
    const UNINITIALIZED: u64 = 0;
    const OPEN: u64 = 1;
    const FILLED: u64 = 2;
    const CANCELLED: u64 = 3;
}

mod types {
    const LIMIT_BUY: u64 = 1;
    const LIMIT_SELL: u64 = 2;
}

// Component ----------------------------------------------------------------------------------------------------------

#[derive(Copy, Drop, Serde)]
struct Order {
    status: u64,
    amount: u64,
    valid_time: u64,
    maker_fee: u64 // in units of 1/10000
}

impl OrderComponent of ComponentTrait<Order> {
    fn name() -> felt252 {
        return 'Order';
    }

    fn is_set(data: Order) -> bool {
        return data.status != 0;
    }

    fn version() -> u64 {
        return 0;
    }
}

// Storage Access -----------------------------------------------------------------------------------------------------

impl StoreOrder of Store<Order> {
    #[inline(always)]
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<Order> {
        return StoreOrder::read_at_offset(address_domain, base, 0);
    }

    #[inline(always)]
    fn write(address_domain: u32, base: StorageBaseAddress, value: Order) -> SyscallResult<()> {
        return StoreOrder::write_at_offset(address_domain, base, 0, value);
    }

    #[inline(always)]
    fn read_at_offset(address_domain: u32, base: StorageBaseAddress, offset: u8) -> SyscallResult<Order> {
        let packed = Store::<u128>::read_at_offset(address_domain, base, offset)?;

        return Result::Ok(Order {
            status: unpack_u128(packed, packed::EXP2_0, packed::EXP2_4).try_into().unwrap(),
            amount: unpack_u128(packed, packed::EXP2_4, packed::EXP2_32).try_into().unwrap(),
            valid_time: unpack_u128(packed, packed::EXP2_36, packed::EXP2_36).try_into().unwrap(),
            maker_fee: unpack_u128(packed, packed::EXP2_72, packed::EXP2_16).try_into().unwrap()
        });
    }

    #[inline(always)]
    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: Order
    ) -> SyscallResult<()> {
        let mut packed: u128 = 0;

        pack_u128(ref packed, packed::EXP2_0, packed::EXP2_4, value.status.into());
        pack_u128(ref packed, packed::EXP2_4, packed::EXP2_32, value.amount.into());
        pack_u128(ref packed, packed::EXP2_36, packed::EXP2_36, value.valid_time.into());
        pack_u128(ref packed, packed::EXP2_72, packed::EXP2_16, value.maker_fee.into());

        return Store::<u128>::write_at_offset(address_domain, base, offset, packed);
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
    use traits::{Into, TryInto};

    use influence::common::{config::entities, packed};
    use influence::components::{ComponentTrait, resolve};
    use influence::types::entity::{Entity, EntityTrait, EntityIntoFelt252, Felt252TryIntoEntity};

    use super::{Order, types, statuses};

    #[test]
    #[available_gas(500000)]
    fn test_storage() {
        let base = starknet::storage_base_address_from_felt252(42);
        let order = Order {
            status: statuses::OPEN,
            amount: 4294967295,
            valid_time: 1703001302,
            maker_fee: 10000
        };

        Store::<Order>::write(0, base, order);
        let read_order = Store::<Order>::read(0, base).unwrap_syscall();
        assert(read_order.status == order.status, 'status does not match');
        assert(read_order.amount == order.amount, 'amount does not match');
        assert(read_order.valid_time == order.valid_time, 'valid_time does not match');
        assert(read_order.maker_fee == order.maker_fee, 'maker_fee does not match');
    }
}
