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

// Constants ----------------------------------------------------------------------------------------------------------

mod types {
    const CORE_SAMPLE_TIME: u64 = 1;
    const CORE_SAMPLE_QUALITY: u64 = 2;
    const HOPPER_TRANSPORT_TIME: u64 = 3;
    const EXTRACTION_TIME: u64 = 4;
    const CONSTRUCTION_TIME: u64 = 5;
    const INVENTORY_MASS_CAPACITY: u64 = 6;
    const PROPELLANT_EXHAUST_VELOCITY: u64 = 7;
    const REFINING_TIME: u64 = 8;
    const MANUFACTURING_TIME: u64 = 9;
    const REACTION_TIME: u64 = 10;
    const FREE_TRANSPORT_DISTANCE: u64 = 11;
    const DECONSTRUCTION_YIELD: u64 = 12;
    const SECONDARY_REFINING_YIELD: u64 = 13;
    const FOOD_CONSUMPTION_TIME: u64 = 14;
    const FOOD_RATIONING_PENALTY: u64 = 15;
    const MARKETPLACE_FEE_ENFORCEMENT: u64 = 16;
    const MARKETPLACE_FEE_REDUCTION: u64 = 17;
    const PROPELLANT_FLOW_RATE: u64 = 18;
    const INVENTORY_VOLUME_CAPACITY: u64 = 19;
    const SHIP_INTEGRATION_TIME: u64 = 20;
}

// Component ----------------------------------------------------------------------------------------------------------

#[derive(Copy, Drop, Serde)]
struct ModifierType {
    class: u64,
    dept_type: u64,
    dept_eff: u64, // in increments of 0.0001
    mgmt_eff: u64, // efficiency for the management department in increments of 0.0001
    trait_type: u64,
    trait_eff: u64, // in increments of 0.0001
    further_modified: bool // indicates whether modifier is further modified by station / food bonus
}

impl ModifierTypeComponent of ComponentTrait<ModifierType> {
    fn name() -> felt252 {
        return 'ModifierType';
    }

    fn is_set(data: ModifierType) -> bool {
        return data.class != 0 || data.dept_type != 0 || data.trait_type != 0;
    }

    fn version() -> u64 {
        return 0;
    }
}

trait ModifierTypeTrait {
    fn by_type(id: u64) -> ModifierType;
}

impl ModifierTypeImpl of ModifierTypeTrait {
    fn by_type(id: u64) -> ModifierType {
        let mut path: Array<felt252> = Default::default();
        path.append(id.into());
        return get(path.span()).expect(errors::MODIFIER_TYPE_NOT_FOUND);
    }
}

// Storage Access -----------------------------------------------------------------------------------------------------

impl StoreModifierType of Store<ModifierType> {
    #[inline(always)]
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<ModifierType> {
        return StoreModifierType::read_at_offset(address_domain, base, 0);
    }

    #[inline(always)]
    fn write(address_domain: u32, base: StorageBaseAddress, value: ModifierType) -> SyscallResult<()> {
        return StoreModifierType::write_at_offset(address_domain, base, 0, value);
    }

    #[inline(always)]
    fn read_at_offset(address_domain: u32, base: StorageBaseAddress, offset: u8) -> SyscallResult<ModifierType> {
        let low = Store::<u128>::read_at_offset(address_domain, base, offset)?;

        return Result::Ok(ModifierType {
            class: unpack_u128(low, packed::EXP2_0, packed::EXP2_8).try_into().unwrap(),
            dept_type: unpack_u128(low, packed::EXP2_8, packed::EXP2_8).try_into().unwrap(),
            dept_eff: unpack_u128(low, packed::EXP2_16, packed::EXP2_16).try_into().unwrap(),
            mgmt_eff: unpack_u128(low, packed::EXP2_32, packed::EXP2_16).try_into().unwrap(),
            trait_type: unpack_u128(low, packed::EXP2_48, packed::EXP2_20).try_into().unwrap(),
            trait_eff: unpack_u128(low, packed::EXP2_68, packed::EXP2_16).try_into().unwrap(),
            further_modified: unpack_u128(low, packed::EXP2_84, packed::EXP2_1) == 1
        });
    }

    #[inline(always)]
    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: ModifierType
    ) -> SyscallResult<()> {
        let mut low: u128 = 0;
        let mut further_modified: u128 = 0;

        if value.further_modified {
            further_modified = 1;
        }

        pack_u128(ref low, packed::EXP2_0, packed::EXP2_8, value.class.into());
        pack_u128(ref low, packed::EXP2_8, packed::EXP2_8, value.dept_type.into());
        pack_u128(ref low, packed::EXP2_16, packed::EXP2_16, value.dept_eff.into());
        pack_u128(ref low, packed::EXP2_32, packed::EXP2_16, value.mgmt_eff.into());
        pack_u128(ref low, packed::EXP2_48, packed::EXP2_20, value.trait_type.into());
        pack_u128(ref low, packed::EXP2_68, packed::EXP2_16, value.trait_eff.into());
        pack_u128(ref low, packed::EXP2_84, packed::EXP2_1, further_modified);

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
    use array::{ArrayTrait, SpanTrait};
    use core::starknet::SyscallResultTrait;
    use option::OptionTrait;
    use result::ResultTrait;
    use starknet::SyscallResult;
    use starknet::storage_access::{Store, StorageBaseAddress, storage_base_address_const};
    use traits::{Into, TryInto};

    use super::{ModifierType, StoreModifierType};

    #[test]
    #[available_gas(500000)]
    fn test_storage() {
        let base = starknet::storage_base_address_from_felt252(42);
        let mut to_store = ModifierType {
            class: 5,
            dept_type: 12,
            dept_eff: 250,
            mgmt_eff: 50,
            trait_type: 42,
            trait_eff: 750,
            further_modified: true
        };

        StoreModifierType::write(0, base, to_store);
        let mut to_read = StoreModifierType::read(0, base).unwrap();
        assert(to_read.class == 5, 'wrong class');
        assert(to_read.dept_type == 12, 'wrong dept_type');
        assert(to_read.dept_eff == 250, 'wrong dept_eff');
        assert(to_read.mgmt_eff == 50, 'wrong mgmt_eff');
        assert(to_read.trait_type == 42, 'wrong trait_type');
        assert(to_read.trait_eff == 750, 'wrong trait_eff');
        assert(to_read.further_modified, 'wrong further_modified');
    }
}
