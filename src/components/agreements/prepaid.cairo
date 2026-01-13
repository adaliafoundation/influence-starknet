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

#[derive(Copy, Drop, Serde)]
struct PrepaidAgreement {
    rate: u64, // rate in SWAY hour (3600 IRL seconds)
    initial_term: u64, // initial term in seconds (0 makes it open ended)
    notice_period: u64, // notice in seconds
    start_time: u64, // time of agreement start (unix timestamp)
    end_time: u64, // time of end based on payments (unix timestamp)
    notice_time: u64 // time of notice
}

impl PrepaidAgreementComponent of ComponentTrait<PrepaidAgreement> {
    fn name() -> felt252 {
        return 'PrepaidAgreement';
    }

    fn is_set(data: PrepaidAgreement) -> bool {
        return data.end_time != 0;
    }

    fn version() -> u64 {
        return 0;
    }
}

trait PrepaidAgreementTrait {
    fn new(rate: u64, initial_term: u64, notice_period: u64, start_time: u64, end_time: u64) -> PrepaidAgreement;
}

impl PrepaidAgreementImpl of PrepaidAgreementTrait {
    fn new(rate: u64, initial_term: u64, notice_period: u64, start_time: u64, end_time: u64) -> PrepaidAgreement {
        return PrepaidAgreement {
            rate: rate,
            initial_term: initial_term,
            notice_period: notice_period,
            start_time: start_time,
            end_time: end_time,
            notice_time: 0
        };
    }
}

// Storage Access -----------------------------------------------------------------------------------------------------

impl StorePrepaidAgreement of Store<PrepaidAgreement> {
    #[inline(always)]
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<PrepaidAgreement> {
        return StorePrepaidAgreement::read_at_offset(address_domain, base, 0);
    }

    #[inline(always)]
    fn write(address_domain: u32, base: StorageBaseAddress, value: PrepaidAgreement) -> SyscallResult<()> {
        return StorePrepaidAgreement::write_at_offset(
            address_domain, base, 0, value
        );
    }

    #[inline(always)]
    fn read_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8
    ) -> SyscallResult<PrepaidAgreement> {
        let packed = Store::<felt252>::read_at_offset(address_domain, base, offset)?;
        let (low, high) = packed::split_felt252(packed);

        return Result::Ok(PrepaidAgreement {
            rate: unpack_u128(low, packed::EXP2_0, packed::EXP2_64).try_into().unwrap(),
            initial_term: unpack_u128(low, packed::EXP2_64, packed::EXP2_28).try_into().unwrap(),
            notice_period: unpack_u128(low, packed::EXP2_92, packed::EXP2_28).try_into().unwrap(),
            start_time: unpack_u128(high, packed::EXP2_0, packed::EXP2_36).try_into().unwrap(),
            end_time: unpack_u128(high, packed::EXP2_36, packed::EXP2_36).try_into().unwrap(),
            notice_time: unpack_u128(high, packed::EXP2_72, packed::EXP2_36).try_into().unwrap()
        });
    }

    #[inline(always)]
    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: PrepaidAgreement
    ) -> SyscallResult<()> {
        let mut low: u128 = 0;
        let mut high: u128 = 0;

        pack_u128(ref low, packed::EXP2_0, packed::EXP2_64, value.rate.into());
        pack_u128(ref low, packed::EXP2_64, packed::EXP2_28, value.initial_term.into());
        pack_u128(ref low, packed::EXP2_92, packed::EXP2_28, value.notice_period.into());

        pack_u128(ref high, packed::EXP2_0, packed::EXP2_36, value.start_time.into());
        pack_u128(ref high, packed::EXP2_36, packed::EXP2_36, value.end_time.into());
        pack_u128(ref high, packed::EXP2_72, packed::EXP2_36, value.notice_time.into());

        let packed: felt252 = low.into() + high.into() * packed::EXP2_128;
        return Store::<felt252>::write_at_offset(address_domain, base, offset, packed);
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

    use super::{PrepaidAgreement, PrepaidAgreementTrait};

    #[test]
    #[available_gas(500000)]
    fn test_storage() {
        let mut agreement = PrepaidAgreementTrait::new(1, 2, 3, 4, 5);
        let base = starknet::storage_base_address_from_felt252(42);

        Store::<PrepaidAgreement>::write(0, base, agreement); // 640
        let mut read_agreement = Store::<PrepaidAgreement>::read(0, base).unwrap_syscall(); // 730
        assert(read_agreement.rate == 1, 'rate should be equal');
        assert(read_agreement.initial_term == 2, 'initial_term should be equal');
        assert(read_agreement.notice_period == 3, 'notice_period should be equal');
        assert(read_agreement.start_time == 4, 'start_time should be equal');
        assert(read_agreement.end_time == 5, 'end_time should be equal');
        assert(read_agreement.notice_time == 0, 'notice_time should be equal');

        agreement.notice_time = 10;
        Store::<PrepaidAgreement>::write(0, base, agreement);
        read_agreement = Store::<PrepaidAgreement>::read(0, base).unwrap_syscall();
        assert(read_agreement.notice_time == 10, 'notice_time should be equal');
    }
}