use array::{ArrayTrait, SpanTrait};
use core::starknet::SyscallResultTrait;
use option::OptionTrait;
use result::ResultTrait;
use starknet::SyscallResult;
use starknet::storage_access::{Store, StorageBaseAddress, storage_base_address_const};
use traits::{Into, TryInto};

use cubit::f64::{Fixed, FixedTrait};

use influence::common::{packed, packed::{split_felt252, pack_u128, unpack_u128}};
use influence::components::{ComponentTrait, resolve, process_type::types as processes};
use influence::config::entities;
use influence::types::entity::{Entity, EntityTrait, Felt252TryIntoEntity};

// Constants ----------------------------------------------------------------------------------------------------------

mod statuses {
    const IDLE: u64 = 0;
    const RUNNING: u64 = 1;
}

mod types {
    const REFINERY: u64 = 1;
    const FACTORY: u64 = 2;
    const BIOREACTOR: u64 = 3;
    const SHIPYARD: u64 = 4;
}

// Component ----------------------------------------------------------------------------------------------------------

#[derive(Copy, Drop, Serde)]
struct Processor {
    processor_type: u64,
    status: u64,
    running_process: u64, // process type
    output_product: u64, // the prioritized output product
    recipes: Fixed, // in number of recipes
    secondary_eff: Fixed, // efficiency of crew in reducing secondary output penalty
    destination: Entity,
    destination_slot: u64,
    finish_time: u64
}

impl ProcessorComponent of ComponentTrait<Processor> {
    fn name() -> felt252 {
        return 'Processor';
    }

    fn is_set(data: Processor) -> bool {
        return data.processor_type != 0;
    }

    fn version() -> u64 {
        return 1;
    }
}

trait ProcessorTrait {
    fn new(processor_type: u64) -> Processor;
    fn reset(ref self: Processor);
    fn assert_ready(self: Processor);
    fn assert_finished(self: Processor, now: u64);
}

impl ProcessorImpl of ProcessorTrait {
    fn new(processor_type: u64) -> Processor {
        return Processor {
            processor_type: processor_type,
            status: statuses::IDLE,
            running_process: 0,
            output_product: 0,
            recipes: FixedTrait::ZERO(),
            secondary_eff: FixedTrait::ZERO(),
            destination: EntityTrait::new(0, 0),
            destination_slot: 0,
            finish_time: 0
        };
    }

    // NOTE: secondary eff not reset to save on state updates
    fn reset(ref self: Processor) {
        self.status = statuses::IDLE;
        self.running_process = 0;
        self.output_product = 0;
        self.recipes = FixedTrait::ZERO();
        self.destination = EntityTrait::new(0, 0);
        self.destination_slot = 0;
        self.finish_time = 0;
    }

    fn assert_ready(self: Processor) {
        assert(self.status == statuses::IDLE, 'processor not ready');
    }

    fn assert_finished(self: Processor, now: u64) {
        assert(self.status == statuses::RUNNING, 'processor not running');
        assert(self.finish_time <= now, 'processor not finished');
    }
}

// Storage Access -----------------------------------------------------------------------------------------------------

impl StoreProcessor of Store<Processor> {
    #[inline(always)]
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<Processor> {
        return StoreProcessor::read_at_offset(address_domain, base, 0);
    }

    #[inline(always)]
    fn write(address_domain: u32, base: StorageBaseAddress, value: Processor) -> SyscallResult<()> {
        return StoreProcessor::write_at_offset(address_domain, base, 0, value);
    }

    #[inline(always)]
    fn read_at_offset(address_domain: u32, base: StorageBaseAddress, offset: u8) -> SyscallResult<Processor> {
        let combined = Store::<felt252>::read_at_offset(address_domain, base, offset)?;
        let (low, high) = split_felt252(combined);
        let recipes = FixedTrait::new(unpack_u128(high, packed::EXP2_22, packed::EXP2_64).try_into().unwrap(), false);
        let mut secondary_eff = Store::<u64>::read_at_offset(address_domain, base, offset + 1)?;

        return Result::Ok(Processor {
            processor_type: unpack_u128(high, packed::EXP2_0, packed::EXP2_18).try_into().unwrap(), // 18 high
            status: unpack_u128(high, packed::EXP2_18, packed::EXP2_4).try_into().unwrap(), // 4 high
            running_process: unpack_u128(low, packed::EXP2_0, packed::EXP2_18).try_into().unwrap(), // 18 low
            output_product: unpack_u128(low, packed::EXP2_18, packed::EXP2_18).try_into().unwrap(), // 18 low
            recipes: recipes, // 64 high
            secondary_eff: FixedTrait::new(secondary_eff, false), // second slot (defaults to 1)
            destination: unpack_u128(low, packed::EXP2_36, packed::EXP2_80).try_into().unwrap(), // 80 low
            destination_slot: unpack_u128(low, packed::EXP2_116, packed::EXP2_8).try_into().unwrap(), // 8 low
            finish_time: unpack_u128(high, packed::EXP2_86, packed::EXP2_36).try_into().unwrap() // 36 high
        });
    }

    #[inline(always)]
    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: Processor
    ) -> SyscallResult<()> {
        Store::<u64>::write_at_offset(address_domain, base, offset + 1, value.secondary_eff.mag)?;

        let mut low: u128 = 0;
        let mut high: u128 = 0;

        pack_u128(ref high, packed::EXP2_0, packed::EXP2_18, value.processor_type.into());
        pack_u128(ref high, packed::EXP2_18, packed::EXP2_4, value.status.into());
        pack_u128(ref low, packed::EXP2_0, packed::EXP2_18, value.running_process.into());
        pack_u128(ref low, packed::EXP2_18, packed::EXP2_18, value.output_product.into());
        pack_u128(ref high, packed::EXP2_22, packed::EXP2_64, value.recipes.mag.into());
        pack_u128(ref low, packed::EXP2_36, packed::EXP2_80, value.destination.into());
        pack_u128(ref low, packed::EXP2_116, packed::EXP2_8, value.destination_slot.into());
        pack_u128(ref high, packed::EXP2_86, packed::EXP2_36, value.finish_time.into());

        let combined = low.into() + high.into() * packed::EXP2_128;
        return Store::<felt252>::write_at_offset(address_domain, base, offset, combined);
    }

    #[inline(always)]
    fn size() -> u8 {
        return 2;
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

    use cubit::f64::{Fixed, FixedTrait};

    use influence::common::packed;
    use influence::components::{ComponentTrait, resolve};
    use influence::config::entities;
    use influence::types::entity::{Entity, EntityTrait, Felt252TryIntoEntity};

    use super::{Processor, ProcessorTrait, StoreProcessor, types, statuses};

    #[test]
    #[available_gas(500000)]
    fn test_storage() {
        let base = starknet::storage_base_address_from_felt252(42);
        let processor = Processor {
            processor_type: types::REFINERY,
            status: statuses::RUNNING,
            running_process: 3,
            output_product: 4,
            recipes: FixedTrait::new_unscaled(5, false),
            secondary_eff: FixedTrait::ONE(),
            destination: EntityTrait::new(entities::BUILDING, 42),
            destination_slot: 1,
            finish_time: 6
        };

        Store::<Processor>::write(0, base, processor);
        let read_processor = Store::<Processor>::read(0, base).unwrap();
        assert(read_processor.processor_type == types::REFINERY, 'processor type wrong');
        assert(read_processor.status == statuses::RUNNING, 'status wrong');
        assert(read_processor.running_process == 3, 'running process wrong');
        assert(read_processor.output_product == 4, 'output product wrong');
        assert(read_processor.recipes == processor.recipes, 'recipes wrong');
        assert(read_processor.secondary_eff == processor.secondary_eff, 'secondary eff wrong');
        assert(read_processor.destination == EntityTrait::new(entities::BUILDING, 42), 'destination wrong');
        assert(read_processor.destination_slot == 1, 'destination slot wrong');
        assert(read_processor.finish_time == 6, 'finish time wrong');
    }
}
