use array::{ArrayTrait, Span, SpanTrait};
use core::starknet::SyscallResultTrait;
use option::OptionTrait;
use result::ResultTrait;
use starknet::SyscallResult;
use starknet::storage_access::{Store, StorageBaseAddress, storage_base_address_const};
use traits::{Into, TryInto};

use influence::common::{config::entities, packed, packed::{split_felt252, pack_u128, unpack_u128}};
use influence::components::{ComponentTrait, resolve};
use influence::types::array::ArrayTraitExt;
use influence::types::entity::{Entity, Felt252TryIntoEntity, EntityTrait};
use influence::types::inventory_item::{InventoryItem, InventoryItemTrait, InventoryContentsTrait};

// Constants ----------------------------------------------------------------------------------------------------------

mod statuses {
    const PACKAGED: u64 = 3; // packaged at origin, can be cancelled by origin controller
    const ON_HOLD: u64 = 1; // on-hold at destination (requires system to complete, ex. processor)
    const SENT: u64 = 4; // sent to destination, can be completed by anyone
    const COMPLETE: u64 = 2; // complete at destination
}

// Component ----------------------------------------------------------------------------------------------------------

#[derive(Copy, Drop, Serde)]
struct Delivery {
    status: u64,
    origin: Entity,
    origin_slot: u64,
    dest: Entity,
    dest_slot: u64,
    finish_time: u64,
    contents: Span<InventoryItem>
}

impl DeliveryComponent of ComponentTrait<Delivery> {
    fn name() -> felt252 {
        return 'Delivery';
    }

    fn is_set(data: Delivery) -> bool {
        return data.status != 0;
    }

    fn version() -> u64 {
        return 0;
    }
}

// Storage Access -----------------------------------------------------------------------------------------------------

impl StoreDelivery of Store<Delivery> {
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<Delivery> {
        return StoreDelivery::read_at_offset(address_domain, base, 0);
    }

    fn write(address_domain: u32, base: StorageBaseAddress, value: Delivery) -> SyscallResult<()> {
        return StoreDelivery::write_at_offset(address_domain, base, 0, value);
    }

    fn read_at_offset(address_domain: u32, base: StorageBaseAddress, offset: u8) -> SyscallResult<Delivery> {
        let combined = Store::<felt252>::read_at_offset(address_domain, base, offset)?;
        let (low, high) = split_felt252(combined);

        let content_len: u8 = unpack_u128(high, packed::EXP2_0, packed::EXP2_8).try_into().unwrap();
        let contents = InventoryContentsTrait::read_storage(address_domain, base, offset + 1, content_len);

        return Result::Ok(Delivery {
            status: unpack_u128(high, packed::EXP2_8, packed::EXP2_4).try_into().unwrap(),
            origin: unpack_u128(high, packed::EXP2_12, packed::EXP2_80).try_into().unwrap(),
            origin_slot: unpack_u128(high, packed::EXP2_92, packed::EXP2_8).try_into().unwrap(),
            dest: unpack_u128(low, packed::EXP2_0, packed::EXP2_80).try_into().unwrap(),
            dest_slot: unpack_u128(low, packed::EXP2_80, packed::EXP2_8).try_into().unwrap(),
            finish_time: unpack_u128(low, packed::EXP2_88, packed::EXP2_36).try_into().unwrap(),
            contents: contents
        });
    }

    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: Delivery
    ) -> SyscallResult<()> {
        let length = value.contents.write_storage(address_domain, base, offset + 1);

        // Pack totals
        let mut low: u128 = 0;
        let mut high: u128 = 0;

        pack_u128(ref high, packed::EXP2_0, packed::EXP2_8, length.into());
        pack_u128(ref high, packed::EXP2_8, packed::EXP2_4, value.status.into());
        pack_u128(ref high, packed::EXP2_12, packed::EXP2_80, value.origin.into());
        pack_u128(ref high, packed::EXP2_92, packed::EXP2_8, value.origin_slot.into());
        pack_u128(ref low, packed::EXP2_0, packed::EXP2_80, value.dest.into());
        pack_u128(ref low, packed::EXP2_80, packed::EXP2_8, value.dest_slot.into());
        pack_u128(ref low, packed::EXP2_88, packed::EXP2_36, value.finish_time.into());

        let combined = low.into() + high.into() * packed::EXP2_128;
        Store::<felt252>::write_at_offset(address_domain, base, offset, combined);

        return Result::Ok(());
    }

    #[inline(always)]
    fn size() -> u8 {
        return 255;
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
    use influence::types::array::ArrayTraitExt;
    use influence::types::entity::{Entity, Felt252TryIntoEntity, EntityTrait};
    use influence::types::inventory_item::{InventoryItem, InventoryItemTrait, InventoryContentsTrait};

    use super::{Delivery, StoreDelivery};

    #[test]
    #[available_gas(5000000)]
    fn test_storage() {
        let base = starknet::storage_base_address_from_felt252(42);
        let contents = array![
            InventoryItemTrait::new(1, 1), // 262145
            InventoryItemTrait::new(3, 2), // 524291
            InventoryItemTrait::new(5, 3), // 786437
            InventoryItemTrait::new(7, 4), // 1048583
            InventoryItemTrait::new(2, 5), // 1310722
            InventoryItemTrait::new(4, 6), // 1572868
            InventoryItemTrait::new(6, 7) // 1835014
        ];

        let origin = EntityTrait::new(entities::BUILDING, 42);
        let dest = EntityTrait::new(entities::SHIP, 43);
        let write_del = Delivery {
            status: 1,
            origin: origin,
            origin_slot: 0,
            dest: dest,
            dest_slot: 1,
            finish_time: 69,
            contents: contents.span()
        };

        Store::<Delivery>::write(0, base, write_del);
        let read_del = Store::<Delivery>::read(0, base).unwrap();

        assert(read_del.status == 1, 'status wrong');
        assert(read_del.origin == origin, 'origin wrong');
        assert(read_del.origin_slot == 0, 'origin slot wrong');
        assert(read_del.dest == dest, 'dest wrong');
        assert(read_del.dest_slot == 1, 'dest slot wrong');
        assert(read_del.finish_time == 69, 'finish time wrong');
        assert(read_del.contents.len() == 7, 'contents length wrong');
        assert(*read_del.contents.at(6).product == 6, 'resource type 1 wrong');
        assert(*read_del.contents.at(6).amount == 7, 'amount 1 wrong');
    }
}