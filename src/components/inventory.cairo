use array::{ArrayTrait, Span, SpanTrait};
use core::starknet::SyscallResultTrait;
use option::OptionTrait;
use result::ResultTrait;
use starknet::SyscallResult;
use starknet::storage_access::{Store, StorageBaseAddress, storage_base_address_const};
use traits::{Into, TryInto};

use influence::common::{packed, packed::{split_felt252, pack_u128, unpack_u128}};
use influence::components::inventory_type::types;
use influence::components::{ComponentTrait, resolve};
use influence::config::errors;
use influence::types::array::{ArrayTraitExt, ArrayHashTrait, SpanHashTrait};
use influence::types::inventory_item::{InventoryItem, InventoryItemTrait, InventoryContentsTrait};

// Constants ----------------------------------------------------------------------------------------------------------

const MAX_MASS: u64 = 1125899906842623; // 2 ** 50 - 1
const MAX_VOLUME: u64 = 1125899906842623; // 2 ** 50 - 1
const MAX_AMOUNT: u64 = 4294967295; // 2 ** 32 - 1

mod statuses {
    const UNAVAILABLE: u64 = 0;
    const AVAILABLE: u64 = 1;
}

// Component ----------------------------------------------------------------------------------------------------------

#[derive(Copy, Drop, Serde)]
struct Inventory {
    inventory_type: u64,
    status: u64,
    mass: u64, // in g
    volume: u64, // in cm^3
    reserved_mass: u64, // in g
    reserved_volume: u64, // in cm^3
    contents: Span<InventoryItem>,
    reservations: Span<InventoryItem> // only used when configuratio limits storage to > 1 product
}

impl InventoryComponent of ComponentTrait<Inventory> {
    fn name() -> felt252 {
        return 'Inventory';
    }

    fn is_set(data: Inventory) -> bool {
        return data.inventory_type != 0;
    }

    fn version() -> u64 {
        return 0;
    }
}

trait InventoryTrait {
    fn new(inventory_type: u64) -> Inventory;
    fn amount_of(self: Inventory, product: u64) -> u64;
    fn disable(ref self: Inventory);
    fn enable(ref self: Inventory);
    fn assert_ready(self: Inventory);
    fn assert_empty(self: Inventory);
}

impl InventoryImpl of InventoryTrait {
    fn new(inventory_type: u64) -> Inventory {
        return Inventory {
            status: statuses::AVAILABLE,
            inventory_type: inventory_type,
            mass: 0,
            volume: 0,
            reserved_mass: 0,
            reserved_volume: 0,
            contents: Default::default().span(),
            reservations: Default::default().span()
        };
    }

    fn amount_of(self: Inventory, product: u64) -> u64 {
        return self.contents.amount_of(product);
    }

    fn disable(ref self: Inventory) {
        self.status = statuses::UNAVAILABLE;
    }

    fn enable(ref self: Inventory) {
        self.status = statuses::AVAILABLE;
    }

    fn assert_ready(self: Inventory) {
        assert(self.status == statuses::AVAILABLE, errors::INVENTORY_UNAVAILABLE);
    }

    fn assert_empty(self: Inventory) {
        assert(self.reserved_mass + self.mass == 0, errors::INVENTORY_NOT_EMPTY);
    }
}

// Storage Access -----------------------------------------------------------------------------------------------------

impl StoreInventory of Store<Inventory> {
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<Inventory> {
        return StoreInventory::read_at_offset(address_domain, base, 0);
    }

    fn write(address_domain: u32, base: StorageBaseAddress, value: Inventory) -> SyscallResult<()> {
        return StoreInventory::write_at_offset(address_domain, base, 0, value);
    }

    fn read_at_offset(address_domain: u32, base: StorageBaseAddress, offset: u8) -> SyscallResult<Inventory> {
        let combined = Store::<felt252>::read_at_offset(address_domain, base, offset)?;
        let (low, high) = split_felt252(combined);

        let content_len = unpack_u128(low, packed::EXP2_0, packed::EXP2_8).try_into().unwrap();
        let contents = InventoryContentsTrait::read_storage(address_domain, base, offset + 1, content_len);

        let reservations_len = unpack_u128(low, packed::EXP2_108, packed::EXP2_8).try_into().unwrap();
        let computed_base = compute_base(base, 'outputs');
        let reservations = InventoryContentsTrait::read_storage(address_domain, computed_base, offset, reservations_len);

        return Result::Ok(Inventory {
            inventory_type: unpack_u128(high, packed::EXP2_0, packed::EXP2_16).try_into().unwrap(),
            status: unpack_u128(high, packed::EXP2_16, packed::EXP2_4).try_into().unwrap(),
            mass: unpack_u128(low, packed::EXP2_8, packed::EXP2_50).try_into().unwrap(),
            volume: unpack_u128(low, packed::EXP2_58, packed::EXP2_50).try_into().unwrap(),
            reserved_mass: unpack_u128(high, packed::EXP2_20, packed::EXP2_50).try_into().unwrap(),
            reserved_volume: unpack_u128(high, packed::EXP2_70, packed::EXP2_50).try_into().unwrap(),
            contents: contents,
            reservations: reservations
        });
    }

    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: Inventory
    ) -> SyscallResult<()> {
        let contents_len = value.contents.write_storage(address_domain, base, offset + 1);

        let computed_base = compute_base(base, 'outputs');
        let reservations_len = value.reservations.write_storage(address_domain, computed_base, offset);

        // Pack and store totals
        let mut low: u128 = 0;
        let mut high: u128 = 0;

        pack_u128(ref low, packed::EXP2_0, packed::EXP2_8, contents_len.into());
        pack_u128(ref low, packed::EXP2_8, packed::EXP2_50, value.mass.into());
        pack_u128(ref low, packed::EXP2_58, packed::EXP2_50, value.volume.into());
        pack_u128(ref low, packed::EXP2_108, packed::EXP2_8, reservations_len.into());

        pack_u128(ref high, packed::EXP2_0, packed::EXP2_16, value.inventory_type.into());
        pack_u128(ref high, packed::EXP2_16, packed::EXP2_4, value.status.into());
        pack_u128(ref high, packed::EXP2_20, packed::EXP2_50, value.reserved_mass.into());
        pack_u128(ref high, packed::EXP2_70, packed::EXP2_50, value.reserved_volume.into());

        let combined = low.into() + high.into() * packed::EXP2_128;
        Store::<felt252>::write_at_offset(address_domain, base, offset, combined);
        return Result::Ok(());
    }

    #[inline(always)]
    fn size() -> u8 {
        return 255;
    }
}

fn compute_base(base: StorageBaseAddress, contents_type: felt252) -> StorageBaseAddress {
    let mut computed_base_to_hash: Array<felt252> = Default::default();
    computed_base_to_hash.append(starknet::storage_address_from_base(base).into());
    computed_base_to_hash.append(contents_type);
    return starknet::storage_base_address_from_felt252(computed_base_to_hash.hash());
}

// Tests --------------------------------------------------------------------------------------------------------------=

#[cfg(test)]
mod tests {
    use array::{ArrayTrait, Span, SpanTrait};
    use core::starknet::SyscallResultTrait;
    use option::OptionTrait;
    use result::ResultTrait;
    use starknet::SyscallResult;
    use starknet::storage_access::{Store, StorageBaseAddress, storage_base_address_const};
    use traits::{Into, TryInto};

    use super::{Inventory, InventoryItem, InventoryItemTrait, InventoryTrait, StoreInventory, statuses};

    #[test]
    #[available_gas(2000000)]
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

        let reservations = array![
            InventoryItemTrait::new(1, 1), // 262145
            InventoryItemTrait::new(3, 2) // 524291
        ];

        let write_inv = Inventory {
            inventory_type: 212,
            status: statuses::AVAILABLE,
            mass: 3,
            volume: 6,
            reserved_mass: 9,
            reserved_volume: 12,
            contents: contents.span(),
            reservations: reservations.span()
        };

        StoreInventory::write(0, base, write_inv); // 6.8k
        let read_inv = StoreInventory::read(0, base).unwrap(); // 3.9k
        assert(read_inv.inventory_type == 212, 'capacity type wrong');
        assert(read_inv.status == statuses::AVAILABLE, 'status wrong');
        assert(read_inv.mass == 3, 'mass wrong');
        assert(read_inv.volume == 6, 'volume wrong');
        assert(read_inv.reserved_mass == 9, 'reserved mass wrong');
        assert(read_inv.reserved_volume == 12, 'reserved volume wrong');
        assert(read_inv.contents.len() == 7, 'contents length wrong');
        assert(*read_inv.contents.at(1).product == 3, 'resource type 1 wrong');
        assert(*read_inv.contents.at(1).amount == 2, 'amount 1 wrong');
        assert(read_inv.reservations.len() == 2, 'reservations length wrong');
        assert(*read_inv.reservations.at(1).product == 3, 'reservation type 1 wrong');
        assert(*read_inv.reservations.at(1).amount == 2, 'reservation amount 1 wrong');
    }
}