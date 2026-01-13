use array::{ArrayTrait, Span, SpanTrait};
use core::starknet::SyscallResultTrait;
use option::OptionTrait;
use result::ResultTrait;
use starknet::SyscallResult;
use starknet::storage_access::{Store, StorageBaseAddress, storage_base_address_const};
use traits::{Into, TryInto};

use influence::common::{config::entities, packed, packed::{pack_u128, unpack_u128}};
use influence::components::{ComponentTrait, resolve};
use influence::types::entity::{Entity, EntityTrait, EntityIntoFelt252, Felt252TryIntoEntity};

// Component ----------------------------------------------------------------------------------------------------------

#[derive(Copy, Drop, Serde)]
struct PrepaidPolicy {
    rate: u64, // rate in SWAY per hour (3600 IRL seconds)
    initial_term: u64, // initial term in seconds
    notice_period: u64 // notice period in seconds
}

impl PrepaidPolicyComponent of ComponentTrait<PrepaidPolicy> {
    fn name() -> felt252 {
        return 'PrepaidPolicy';
    }

    fn is_set(data: PrepaidPolicy) -> bool {
        return data.rate + data.initial_term + data.notice_period != 0;
    }

    fn version() -> u64 {
        return 0;
    }
}

trait PrepaidPolicyTrait {
    fn new(rate: u64, initial_term: u64, notice_period: u64) -> PrepaidPolicy;
}

impl PrepaidPolicyImpl of PrepaidPolicyTrait {
    fn new(rate: u64, initial_term: u64, notice_period: u64) -> PrepaidPolicy {
        return PrepaidPolicy { rate: rate, initial_term: initial_term, notice_period: notice_period };
    }
}

// Storage Access -----------------------------------------------------------------------------------------------------

impl StorePrepaidPolicy of Store<PrepaidPolicy> {
    #[inline(always)]
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<PrepaidPolicy> {
        return StorePrepaidPolicy::read_at_offset(address_domain, base, 0);
    }

    #[inline(always)]
    fn write(address_domain: u32, base: StorageBaseAddress, value: PrepaidPolicy) -> SyscallResult<()> {
        return StorePrepaidPolicy::write_at_offset(
            address_domain, base, 0, value
        );
    }

    #[inline(always)]
    fn read_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8
    ) -> SyscallResult<PrepaidPolicy> {
        let low = Store::<u128>::read_at_offset(address_domain, base, offset)?;

        return Result::Ok(PrepaidPolicy {
            rate: unpack_u128(low, packed::EXP2_0, packed::EXP2_64).try_into().unwrap(),
            initial_term: unpack_u128(low, packed::EXP2_64, packed::EXP2_28).try_into().unwrap(),
            notice_period: unpack_u128(low, packed::EXP2_92, packed::EXP2_28).try_into().unwrap()
        });
    }

    #[inline(always)]
    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: PrepaidPolicy
    ) -> SyscallResult<()> {
        let mut low: u128 = 0;
        pack_u128(ref low, packed::EXP2_0, packed::EXP2_64, value.rate.into());
        pack_u128(ref low, packed::EXP2_64, packed::EXP2_28, value.initial_term.into());
        pack_u128(ref low, packed::EXP2_92, packed::EXP2_28, value.notice_period.into());
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

    use super::{PrepaidPolicy, PrepaidPolicyTrait};

    #[test]
    #[available_gas(500000)]
    fn test_storage() {
        let access_policy = PrepaidPolicyTrait::new(1, 2, 3);
        let base = starknet::storage_base_address_from_felt252(42);

        Store::<PrepaidPolicy>::write(0, base, access_policy);
        let mut read_policy = Store::<PrepaidPolicy>::read(0, base).unwrap_syscall();
        assert(read_policy.rate == 1, 'rate should be 1');
        assert(read_policy.initial_term == 2, 'initial_term should be 2');
        assert(read_policy.notice_period == 3, 'notice should be 3');
    }
}