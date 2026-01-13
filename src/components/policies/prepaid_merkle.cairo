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
struct PrepaidMerklePolicy {
    rate: u64, // rate in SWAY / Adalian day (IRL hour)
    initial_term: u64, // initial term in seconds
    notice_period: u64, // notice period in seconds
    merkle_root: felt252 // for use with Asteroid-wide lot lease policies (otherwise 0)
}

impl PrepaidMerklePolicyComponent of ComponentTrait<PrepaidMerklePolicy> {
    fn name() -> felt252 {
        return 'PrepaidMerklePolicy';
    }

    fn is_set(data: PrepaidMerklePolicy) -> bool {
        return data.rate + data.initial_term + data.notice_period != 0;
    }

    fn version() -> u64 {
        return 0;
    }
}

trait PrepaidMerklePolicyTrait {
    fn new(rate: u64, initial_term: u64, notice_period: u64) -> PrepaidMerklePolicy;
}

impl PrepaidMerklePolicyImpl of PrepaidMerklePolicyTrait {
    fn new(rate: u64, initial_term: u64, notice_period: u64) -> PrepaidMerklePolicy {
        return PrepaidMerklePolicy {
            rate: rate,
            initial_term: initial_term,
            notice_period: notice_period,
            merkle_root: 0
        };
    }
}

// Storage Access -----------------------------------------------------------------------------------------------------

impl StorePrepaidMerklePolicy of Store<PrepaidMerklePolicy> {
    #[inline(always)]
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<PrepaidMerklePolicy> {
        return StorePrepaidMerklePolicy::read_at_offset(address_domain, base, 0);
    }

    #[inline(always)]
    fn write(address_domain: u32, base: StorageBaseAddress, value: PrepaidMerklePolicy) -> SyscallResult<()> {
        return StorePrepaidMerklePolicy::write_at_offset(address_domain, base, 0, value);
    }

    #[inline(always)]
    fn read_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8
    ) -> SyscallResult<PrepaidMerklePolicy> {
        let low = Store::<u128>::read_at_offset(address_domain, base, offset)?;
        let merkle_root = Store::<felt252>::read_at_offset(address_domain, base, offset + 1)?;

        return Result::Ok(PrepaidMerklePolicy {
            rate: unpack_u128(low, packed::EXP2_0, packed::EXP2_64).try_into().unwrap(),
            initial_term: unpack_u128(low, packed::EXP2_64, packed::EXP2_28).try_into().unwrap(),
            notice_period: unpack_u128(low, packed::EXP2_92, packed::EXP2_28).try_into().unwrap(),
            merkle_root: merkle_root
        });
    }

    #[inline(always)]
    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: PrepaidMerklePolicy
    ) -> SyscallResult<()> {
        let mut low: u128 = 0;
        pack_u128(ref low, packed::EXP2_0, packed::EXP2_64, value.rate.into());
        pack_u128(ref low, packed::EXP2_64, packed::EXP2_28, value.initial_term.into());
        pack_u128(ref low, packed::EXP2_92, packed::EXP2_28, value.notice_period.into());

        Store::<felt252>::write_at_offset(address_domain, base, offset + 1, value.merkle_root)?;
        return Store::<u128>::write_at_offset(address_domain, base, offset, low);
    }

    #[inline(always)]
    fn size() -> u8 {
        return 2;
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

    use super::{PrepaidMerklePolicy, PrepaidMerklePolicyTrait};

    #[test]
    #[available_gas(500000)]
    fn test_storage() {
        let access_policy = PrepaidMerklePolicyTrait::new(1, 2, 3);
        let base = starknet::storage_base_address_from_felt252(42);

        Store::<PrepaidMerklePolicy>::write(0, base, access_policy);
        let mut read_policy = Store::<PrepaidMerklePolicy>::read(0, base).unwrap_syscall();
        assert(read_policy.rate == 1, 'rate should be 1');
        assert(read_policy.initial_term == 2, 'initial_term should be 2');
        assert(read_policy.notice_period == 3, 'notice should be 3');
        assert(read_policy.merkle_root == 0, 'merkle_root should be 0');
    }
}
