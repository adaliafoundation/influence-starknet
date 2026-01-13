use array::{ArrayTrait, Span, SpanTrait};
use core::starknet::SyscallResultTrait;
use option::OptionTrait;
use result::ResultTrait;
use starknet::SyscallResult;
use starknet::storage_access::{Store, StorageBaseAddress, storage_base_address_const};
use traits::{Into, TryInto};

use cubit::f64::{Fixed, FixedTrait};

use influence::common::{packed, packed::{split_felt252, pack_u128, unpack_u128}};
use influence::components::{ComponentTrait, resolve};
use influence::config::errors;

// Constants ----------------------------------------------------------------------------------------------------------

const MAX_YIELD: u64 = 10000000; // 10m kg / 10k tonnes

mod statuses {
    const UNDISCOVERED: u64 = 0;
    const SAMPLING: u64 = 1;
    const SAMPLED: u64 = 2;
    const USED: u64 = 3;
}

// Component ----------------------------------------------------------------------------------------------------------

#[derive(Copy, Drop, Serde)]
struct Deposit {
    status: u64,
    resource: u64,
    initial_yield: u64,
    remaining_yield: u64,
    finish_time: u64, // time when core sampling is complete
    yield_eff: Fixed
}

impl DepositComponent of ComponentTrait<Deposit> {
    fn name() -> felt252 {
        return 'Deposit';
    }

    fn is_set(data: Deposit) -> bool {
        return data.status != statuses::UNDISCOVERED;
    }

    fn version() -> u64 {
        return 0;
    }
}

trait DepositTrait {
    fn new(resource: u64) -> Deposit;
    fn assert_extractable(self: Deposit);
}

impl DepositImpl of DepositTrait {
    fn new(resource: u64) -> Deposit {
        return Deposit {
            status: statuses::UNDISCOVERED,
            resource: resource,
            initial_yield: 0,
            remaining_yield: 0,
            finish_time: 0,
            yield_eff: FixedTrait::ZERO()
        };
    }

    fn assert_extractable(self: Deposit) {
        assert(self.status == statuses::SAMPLED || self.status == statuses::USED, errors::INCORRECT_STATUS);
    }
}

// Storage Access -----------------------------------------------------------------------------------------------------

impl StoreDeposit of Store<Deposit> {
    #[inline(always)]
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<Deposit> {
        return StoreDeposit::read_at_offset(address_domain, base, 0);
    }

    #[inline(always)]
    fn write(address_domain: u32, base: StorageBaseAddress, value: Deposit) -> SyscallResult<()> {
        return StoreDeposit::write_at_offset(address_domain, base, 0, value);
    }

    #[inline(always)]
    fn read_at_offset(address_domain: u32, base: StorageBaseAddress, offset: u8) -> SyscallResult<Deposit> {
        let combined = Store::<felt252>::read_at_offset(address_domain, base, offset)?;
        let (low, high) = split_felt252(combined);

        return Result::Ok(Deposit {
            status: unpack_u128(low, packed::EXP2_0, packed::EXP2_4).try_into().unwrap(),
            resource: unpack_u128(low, packed::EXP2_4, packed::EXP2_18).try_into().unwrap(),
            initial_yield: unpack_u128(low, packed::EXP2_22, packed::EXP2_32).try_into().unwrap(),
            remaining_yield: unpack_u128(low, packed::EXP2_54, packed::EXP2_32).try_into().unwrap(),
            finish_time: unpack_u128(low, packed::EXP2_86, packed::EXP2_36).try_into().unwrap(),
            yield_eff: FixedTrait::new(unpack_u128(high, packed::EXP2_0, packed::EXP2_64).try_into().unwrap(), false)
        });
    }

    #[inline(always)]
    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: Deposit
    ) -> SyscallResult<()> {
        assert(!value.yield_eff.sign, 'multiplier must be positive');
        let mut low: u128 = 0;
        let mut high: u128 = 0;

        pack_u128(ref low, packed::EXP2_0, packed::EXP2_4, value.status.into());
        pack_u128(ref low, packed::EXP2_4, packed::EXP2_18, value.resource.into());
        pack_u128(ref low, packed::EXP2_22, packed::EXP2_32, value.initial_yield.into());
        pack_u128(ref low, packed::EXP2_54, packed::EXP2_32, value.remaining_yield.into());
        pack_u128(ref low, packed::EXP2_86, packed::EXP2_36, value.finish_time.into());
        pack_u128(ref high, packed::EXP2_0, packed::EXP2_64, value.yield_eff.mag.into());

        let combined = low.into() + high.into() * packed::EXP2_128;
        return Store::<felt252>::write_at_offset(address_domain, base, offset, combined);
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

    use cubit::f64::{Fixed, FixedTrait};
    use cubit::f64::test::helpers::assert_precise;

    use super::{Deposit, DepositTrait, statuses};

    #[test]
    #[available_gas(500000)]
    fn test_storage() {
        let base = starknet::storage_base_address_from_felt252(42);
        let deposit = Deposit {
            status: statuses::SAMPLING,
            resource: 42,
            initial_yield: 3,
            remaining_yield: 2,
            finish_time: 5,
            yield_eff: FixedTrait::new(5, false)
        };

        Store::<Deposit>::write(0, base, deposit);
        let saved_deposit = Store::<Deposit>::read(0, base).unwrap_syscall();
        assert(saved_deposit.status == deposit.status, 'status does not match');
        assert(saved_deposit.resource == deposit.resource, 'resource does not match');
        assert(saved_deposit.initial_yield == deposit.initial_yield, 'initial_yield does not match');
        assert(saved_deposit.remaining_yield == deposit.remaining_yield, 'yield does not match');
        assert(saved_deposit.finish_time == deposit.finish_time, 'finish_time does not match');
        assert_precise(saved_deposit.yield_eff, deposit.yield_eff.into(), 'yield_eff does not match', Option::None(()));
    }
}
