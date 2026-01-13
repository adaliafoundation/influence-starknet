use array::{ArrayTrait, SpanTrait};
use core::starknet::SyscallResultTrait;
use option::OptionTrait;
use result::ResultTrait;
use starknet::SyscallResult;
use starknet::storage_access::{Store, StorageBaseAddress, storage_base_address_const};
use traits::{Into, TryInto};

use influence::common::{packed, packed::{split_felt252, pack_u128, unpack_u128}};
use influence::components::{ComponentTrait, resolve};
use influence::types::entity::{Entity, EntityTrait};

// Constants ----------------------------------------------------------------------------------------------------------

const MAX_EXTRACTION_TIME: u64 = 31536000; // in-game time in seconds
const MAX_YIELD_PER_RUN: u64 = 42949672960000000; // 10,000,000 kg (f64)

mod statuses {
    const IDLE: u64 = 0;
    const RUNNING: u64 = 1;
}

mod types {
    const BASIC: u64 = 1;
}

// Component ----------------------------------------------------------------------------------------------------------

#[derive(Copy, Drop, Serde)]
struct Extractor {
    extractor_type: u64,
    status: u64,
    output_product: u64,
    yield: u64, // in units
    destination: Entity,
    destination_slot: u64,
    finish_time: u64 // time when extractor run completes
}

impl ExtractorComponent of ComponentTrait<Extractor> {
    fn name() -> felt252 {
        return 'Extractor';
    }

    fn is_set(data: Extractor) -> bool {
        return data.extractor_type != 0;
    }

    fn version() -> u64 {
        return 0;
    }
}

trait ExtractorTrait {
    fn new(extractor_type: u64) -> Extractor;
    fn reset(ref self: Extractor);
    fn assert_ready(self: Extractor);
    fn assert_finished(self: Extractor, now: u64);
}

impl ExtractorImpl of ExtractorTrait {
    fn new(extractor_type: u64) -> Extractor {
        return Extractor {
            extractor_type: extractor_type,
            status: statuses::IDLE,
            output_product: 0,
            yield: 0,
            destination: EntityTrait::new(0, 0),
            destination_slot: 0,
            finish_time: 0
        };
    }

    fn reset(ref self: Extractor) {
        self.status = statuses::IDLE;
        self.output_product = 0;
        self.yield = 0;
        self.destination = EntityTrait::new(0, 0);
        self.destination_slot = 0;
        self.finish_time = 0;
    }

    fn assert_ready(self: Extractor) {
        assert(self.status == statuses::IDLE, 'processor not ready');
    }

    fn assert_finished(self: Extractor, now: u64) {
        assert(self.status == statuses::RUNNING, 'processor not running');
        assert(self.finish_time <= now, 'processor not finished');
    }
}

// Storage Access -----------------------------------------------------------------------------------------------------

impl StoreExtractor of Store<Extractor> {
    #[inline(always)]
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<Extractor> {
        return StoreExtractor::read_at_offset(address_domain, base, 0);
    }

    #[inline(always)]
    fn write(address_domain: u32, base: StorageBaseAddress, value: Extractor) -> SyscallResult<()> {
        return StoreExtractor::write_at_offset(address_domain, base, 0, value);
    }

    #[inline(always)]
    fn read_at_offset(address_domain: u32, base: StorageBaseAddress, offset: u8) -> SyscallResult<Extractor> {
        let combined = Store::<felt252>::read_at_offset(address_domain, base, offset)?;
        let (low, high) = split_felt252(combined);

        return Result::Ok(Extractor {
            extractor_type: unpack_u128(low, packed::EXP2_0, packed::EXP2_16).try_into().unwrap(),
            status: unpack_u128(low, packed::EXP2_16, packed::EXP2_4).try_into().unwrap(),
            output_product: unpack_u128(low, packed::EXP2_20, packed::EXP2_18).try_into().unwrap(),
            yield: unpack_u128(low, packed::EXP2_38, packed::EXP2_32).try_into().unwrap(),
            destination: unpack_u128(high, packed::EXP2_0, packed::EXP2_80).try_into().unwrap(),
            destination_slot: unpack_u128(high, packed::EXP2_80, packed::EXP2_8).try_into().unwrap(),
            finish_time: unpack_u128(low, packed::EXP2_70, packed::EXP2_36).try_into().unwrap()
        });
    }

    #[inline(always)]
    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: Extractor
    ) -> SyscallResult<()> {
        let mut low: u128 = 0;
        let mut high: u128 = 0;

        pack_u128(ref low, packed::EXP2_0, packed::EXP2_16, value.extractor_type.into());
        pack_u128(ref low, packed::EXP2_16, packed::EXP2_4, value.status.into());
        pack_u128(ref low, packed::EXP2_20, packed::EXP2_18, value.output_product.into());
        pack_u128(ref low, packed::EXP2_38, packed::EXP2_32, value.yield.into());
        pack_u128(ref high, packed::EXP2_0, packed::EXP2_80, value.destination.into());
        pack_u128(ref high, packed::EXP2_80, packed::EXP2_8, value.destination_slot.into());
        pack_u128(ref low, packed::EXP2_70, packed::EXP2_36, value.finish_time.into());

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
    use array::{ArrayTrait, SpanTrait};
    use core::starknet::SyscallResultTrait;
    use option::OptionTrait;
    use result::ResultTrait;
    use starknet::SyscallResult;
    use starknet::storage_access::{Store, StorageBaseAddress, storage_base_address_const};
    use traits::{Into, TryInto};

    use influence::common::packed;
    use influence::config::entities;
    use influence::components::{ComponentTrait, resolve};
    use influence::types::entity::{Entity, EntityTrait};

    use super::{Extractor, ExtractorTrait, ExtractorImpl, ExtractorComponent, StoreExtractor, types, statuses};

    #[test]
    #[available_gas(500000)]
    fn test_extractor() {
        let base = starknet::storage_base_address_from_felt252(42);
        let warehouse = EntityTrait::new(entities::BUILDING, 13);
        let extractor = Extractor {
            extractor_type: types::BASIC,
            status: statuses::RUNNING,
            output_product: 42,
            yield: 3,
            destination: warehouse,
            destination_slot: 1,
            finish_time: 5
        };

        Store::<Extractor>::write(0, base, extractor);
        let read_extractor = Store::<Extractor>::read(0, base).unwrap();
        assert(read_extractor.extractor_type == extractor.extractor_type, 'extractor_type does not match');
        assert(read_extractor.status == extractor.status, 'status does not match');
        assert(read_extractor.output_product == extractor.output_product, 'output_product does not match');
        assert(read_extractor.yield == extractor.yield, 'yield does not match');
        assert(read_extractor.finish_time == extractor.finish_time, 'finish_time does not match');
    }
}