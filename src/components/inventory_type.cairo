use array::{ArrayTrait, SpanTrait};
use core::starknet::SyscallResultTrait;
use option::OptionTrait;
use result::ResultTrait;
use starknet::SyscallResult;
use starknet::storage_access::{Store, StorageBaseAddress, storage_base_address_const};
use traits::{Into, TryInto};

use influence::common::{packed, packed::{pack_u128, unpack_u128}};
use influence::components::{ComponentTrait, get};
use influence::config::errors;
use influence::types::entity::{Entity, EntityTrait, Felt252TryIntoEntity};
use influence::types::inventory_item::{InventoryItem, InventoryItemTrait, InventoryContentsTrait};

// Constants ----------------------------------------------------------------------------------------------------------

mod types {
    const WAREHOUSE_SITE: u64 = 1;
    const EXTRACTOR_SITE: u64 = 2;
    const REFINERY_SITE: u64 = 3;
    const BIOREACTOR_SITE: u64 = 4;
    const FACTORY_SITE: u64 = 5;
    const SHIPYARD_SITE: u64 = 6;
    const SPACEPORT_SITE: u64 = 7;
    const MARKETPLACE_SITE: u64 = 8;
    const HABITAT_SITE: u64 = 9;
    const WAREHOUSE_PRIMARY: u64 = 10;
    const PROPELLANT_TINY: u64 = 11;
    const PROPELLANT_SMALL: u64 = 12;
    const PROPELLANT_MEDIUM: u64 = 13;
    const PROPELLANT_LARGE: u64 = 14;
    const CARGO_SMALL: u64 = 15;
    const CARGO_MEDIUM: u64 = 16;
    const CARGO_LARGE: u64 = 17;
    const TANK_FARM_SITE: u64 = 18;
    const TANK_FARM_PRIMARY: u64 = 19;
}

// Component ----------------------------------------------------------------------------------------------------------

#[derive(Copy, Drop, Serde)]
struct InventoryType {
    mass: u64, // in g
    volume: u64, // in cm^3
    modifiable: bool, // whether crew modifiers are applied
    products: Span<InventoryItem>
}

impl InventoryTypeComponent of ComponentTrait<InventoryType> {
    fn name() -> felt252 {
        return 'InventoryType';
    }

    fn is_set(data: InventoryType) -> bool {
        return data.mass != 0 || data.volume != 0;
    }

    fn version() -> u64 {
        return 0;
    }
}

trait InventoryTypeTrait {
    fn by_type(id: u64) -> InventoryType;
}

impl InventoryTypeImpl of InventoryTypeTrait {
    fn by_type(id: u64) -> InventoryType {
        let mut path: Array<felt252> = Default::default();
        path.append(id.into());
        return get(path.span()).expect(errors::INVENTORY_TYPE_NOT_FOUND);
    }
}

// Storage Access -----------------------------------------------------------------------------------------------------

impl StoreInventoryType of Store<InventoryType> {
    #[inline(always)]
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<InventoryType> {
        return StoreInventoryType::read_at_offset(address_domain, base, 0);
    }

    #[inline(always)]
    fn write(address_domain: u32, base: StorageBaseAddress, value: InventoryType) -> SyscallResult<()> {
        return StoreInventoryType::write_at_offset(address_domain, base, 0, value);
    }

    #[inline(always)]
    fn read_at_offset(address_domain: u32, base: StorageBaseAddress, offset: u8) -> SyscallResult<InventoryType> {
        let low = Store::<u128>::read_at_offset(address_domain, base, offset)?;

        let products_len = unpack_u128(low, packed::EXP2_101, packed::EXP2_8).try_into().unwrap();
        let products = InventoryContentsTrait::read_storage(address_domain, base, offset + 1, products_len);

        return Result::Ok(InventoryType {
            mass: unpack_u128(low, packed::EXP2_0, packed::EXP2_50).try_into().unwrap(),
            volume: unpack_u128(low, packed::EXP2_50, packed::EXP2_50).try_into().unwrap(),
            modifiable: unpack_u128(low, packed::EXP2_100, packed::EXP2_1) == 1,
            products: products
        });
    }

    #[inline(always)]
    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: InventoryType
    ) -> SyscallResult<()> {
        let products_len = value.products.write_storage(address_domain, base, offset + 1);

        let mut low: u128 = 0;
        let mut modifiable: u128 = 0;

        if value.modifiable {
            modifiable = 1;
        }

        pack_u128(ref low, packed::EXP2_0, packed::EXP2_50, value.mass.into());
        pack_u128(ref low, packed::EXP2_50, packed::EXP2_50, value.volume.into());
        pack_u128(ref low, packed::EXP2_100, packed::EXP2_1, modifiable);
        pack_u128(ref low, packed::EXP2_101, packed::EXP2_8, products_len.into());

        return Store::<u128>::write_at_offset(address_domain, base, offset, low);
    }

    #[inline(always)]
    fn size() -> u8 {
        return 255;
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

    use influence::components::product_type::types as product_types;
    use influence::types::inventory_item::{InventoryItem, InventoryItemTrait};

    use super::{InventoryType, StoreInventoryType};

    #[test]
    #[available_gas(2000000)]
    fn test_storage() {
        let base = starknet::storage_base_address_from_felt252(42);

        let mut products: Array<InventoryItem> = Default::default();
        products.append(InventoryItemTrait::new(product_types::CARBON_DIOXIDE, 1936));
        products.append(InventoryItemTrait::new(product_types::OLIVINE, 4526));

        let mut to_store = InventoryType {
            mass: 562949953421312,
            volume: 562949953421312,
            modifiable: true,
            products: products.span(),
        };

        StoreInventoryType::write(0, base, to_store);
        let mut to_read = StoreInventoryType::read(0, base).unwrap();
        assert(to_read.mass == 562949953421312, 'wrong mass');
        assert(to_read.volume == 562949953421312, 'wrong volume');
        assert(to_read.modifiable, 'not modifiable');
        assert(to_read.products.len() == 2, 'wrong products length');

        assert((*to_read.products.at(0)).product == product_types::CARBON_DIOXIDE, 'wrong input product');
        assert((*to_read.products.at(0)).amount == 1936, 'wrong input quantity');
        assert((*to_read.products.at(1)).product == product_types::OLIVINE, 'wrong input product');
        assert((*to_read.products.at(1)).amount == 4526, 'wrong input quantity');
    }
}
