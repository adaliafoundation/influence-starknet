use array::{ArrayTrait, SpanTrait};
use core::starknet::SyscallResultTrait;
use option::OptionTrait;
use result::ResultTrait;
use starknet::SyscallResult;
use starknet::storage_access::{Store, StorageBaseAddress};
use traits::{Into, TryInto};

use influence::common::{packed, packed::{pack_u128, unpack_u128}};
use influence::components::ComponentTrait;
use influence::types::array::ArrayHashTrait;
use influence::types::{Entity, EntityTrait};

mod products {
    const EXPLORER: u64 = 1;
    const STRATEGIST: u64 = 2;
    const INDUSTRIALIST: u64 = 3;
}

#[derive(Copy, Drop, Serde)]
struct BuildingAllowance {
    building_type: u64,
    count: u64
}

#[derive(Copy, Drop, Serde)]
struct StarterPack {
    product_id: u64,
    restricted_until: u64,
    valid: bool,
    invalidated_at: u64,
    building_allowances: Span<BuildingAllowance>,
    lot_allowance: u64,
    food_reload_allowance: u64,
    core_sample_allowance: u64
}

#[derive(Copy, Drop, Serde)]
struct StarterPackBuildingFunding {
    crew: Entity,
    restricted_until: u64
}

#[derive(Copy, Drop, Serde)]
struct StarterPackLotLease {
    crew: Entity
}

impl StarterPackComponent of ComponentTrait<StarterPack> {
    fn name() -> felt252 {
        return 'StarterPack';
    }

    fn is_set(data: StarterPack) -> bool {
        return data.product_id != 0;
    }

    fn version() -> u64 {
        return 0;
    }
}

impl StarterPackBuildingFundingComponent of ComponentTrait<StarterPackBuildingFunding> {
    fn name() -> felt252 {
        return 'StarterPackBuildingFunding';
    }

    fn is_set(data: StarterPackBuildingFunding) -> bool {
        return !data.crew.is_empty();
    }

    fn version() -> u64 {
        return 0;
    }
}

impl StarterPackLotLeaseComponent of ComponentTrait<StarterPackLotLease> {
    fn name() -> felt252 {
        return 'StarterPackLotLease';
    }

    fn is_set(data: StarterPackLotLease) -> bool {
        return !data.crew.is_empty();
    }

    fn version() -> u64 {
        return 0;
    }
}

trait StarterPackTrait {
    fn building_allowance(self: StarterPack, building_type: u64) -> u64;
}

impl StarterPackImpl of StarterPackTrait {
    fn building_allowance(self: StarterPack, building_type: u64) -> u64 {
        let mut allowances = self.building_allowances;
        let mut count = 0;

        loop {
            match allowances.pop_front() {
                Option::Some(allowance) => {
                    if *allowance.building_type == building_type {
                        count = *allowance.count;
                        break;
                    }
                },
                Option::None(_) => {
                    break;
                },
            };
        };

        return count;
    }
}

impl StoreStarterPack of Store<StarterPack> {
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<StarterPack> {
        return Self::read_at_offset(address_domain, base, 0);
    }

    fn write(address_domain: u32, base: StorageBaseAddress, value: StarterPack) -> SyscallResult<()> {
        return Self::write_at_offset(address_domain, base, 0, value);
    }

    fn read_at_offset(address_domain: u32, base: StorageBaseAddress, offset: u8) -> SyscallResult<StarterPack> {
        let low = Store::<u128>::read_at_offset(address_domain, base, offset)?;
        let high = Store::<u128>::read_at_offset(address_domain, base, offset + 1)?;
        let allowances_len = unpack_u128(low, packed::EXP2_44, packed::EXP2_8).try_into().unwrap();
        let building_allowances = read_building_allowances(address_domain, allowances_base(base), offset, allowances_len);

        return Result::Ok(StarterPack {
            product_id: unpack_u128(low, packed::EXP2_0, packed::EXP2_8).try_into().unwrap(),
            restricted_until: unpack_u128(low, packed::EXP2_8, packed::EXP2_36).try_into().unwrap(),
            valid: unpack_u128(low, packed::EXP2_100, packed::EXP2_1) == 1,
            invalidated_at: unpack_u128(high, packed::EXP2_0, packed::EXP2_36).try_into().unwrap(),
            building_allowances: building_allowances,
            lot_allowance: unpack_u128(low, packed::EXP2_101, packed::EXP2_8).try_into().unwrap(),
            food_reload_allowance: unpack_u128(low, packed::EXP2_52, packed::EXP2_32).try_into().unwrap(),
            core_sample_allowance: unpack_u128(low, packed::EXP2_84, packed::EXP2_16).try_into().unwrap()
        });
    }

    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: StarterPack
    ) -> SyscallResult<()> {
        let allowances_len = write_building_allowances(
            value.building_allowances, address_domain, allowances_base(base), offset
        );
        let mut low: u128 = 0;
        let mut high: u128 = 0;
        let valid = if value.valid { 1 } else { 0 };

        pack_u128(ref low, packed::EXP2_0, packed::EXP2_8, value.product_id.into());
        pack_u128(ref low, packed::EXP2_8, packed::EXP2_36, value.restricted_until.into());
        pack_u128(ref low, packed::EXP2_44, packed::EXP2_8, allowances_len.into());
        pack_u128(ref low, packed::EXP2_52, packed::EXP2_32, value.food_reload_allowance.into());
        pack_u128(ref low, packed::EXP2_84, packed::EXP2_16, value.core_sample_allowance.into());
        pack_u128(ref low, packed::EXP2_100, packed::EXP2_1, valid);
        pack_u128(ref low, packed::EXP2_101, packed::EXP2_8, value.lot_allowance.into());
        pack_u128(ref high, packed::EXP2_0, packed::EXP2_36, value.invalidated_at.into());

        Store::<u128>::write_at_offset(address_domain, base, offset, low).unwrap_syscall();
        return Store::<u128>::write_at_offset(address_domain, base, offset + 1, high);
    }

    #[inline(always)]
    fn size() -> u8 {
        return 255;
    }
}

impl StoreStarterPackLotLease of Store<StarterPackLotLease> {
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<StarterPackLotLease> {
        return Self::read_at_offset(address_domain, base, 0);
    }

    fn write(address_domain: u32, base: StorageBaseAddress, value: StarterPackLotLease) -> SyscallResult<()> {
        return Self::write_at_offset(address_domain, base, 0, value);
    }

    fn read_at_offset(address_domain: u32, base: StorageBaseAddress, offset: u8) -> SyscallResult<StarterPackLotLease> {
        let low = Store::<u128>::read_at_offset(address_domain, base, offset)?;

        return Result::Ok(StarterPackLotLease {
            crew: unpack_u128(low, packed::EXP2_0, packed::EXP2_64).try_into().unwrap()
        });
    }

    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: StarterPackLotLease
    ) -> SyscallResult<()> {
        let mut low: u128 = 0;

        pack_u128(ref low, packed::EXP2_0, packed::EXP2_64, value.crew.into());

        return Store::<u128>::write_at_offset(address_domain, base, offset, low);
    }

    #[inline(always)]
    fn size() -> u8 {
        return 1;
    }
}

impl StoreStarterPackBuildingFunding of Store<StarterPackBuildingFunding> {
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<StarterPackBuildingFunding> {
        return Self::read_at_offset(address_domain, base, 0);
    }

    fn write(address_domain: u32, base: StorageBaseAddress, value: StarterPackBuildingFunding) -> SyscallResult<()> {
        return Self::write_at_offset(address_domain, base, 0, value);
    }

    fn read_at_offset(address_domain: u32, base: StorageBaseAddress, offset: u8) -> SyscallResult<StarterPackBuildingFunding> {
        let low = Store::<u128>::read_at_offset(address_domain, base, offset)?;

        return Result::Ok(StarterPackBuildingFunding {
            crew: unpack_u128(low, packed::EXP2_0, packed::EXP2_64).try_into().unwrap(),
            restricted_until: unpack_u128(low, packed::EXP2_64, packed::EXP2_36).try_into().unwrap()
        });
    }

    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: StarterPackBuildingFunding
    ) -> SyscallResult<()> {
        let mut low: u128 = 0;

        pack_u128(ref low, packed::EXP2_0, packed::EXP2_64, value.crew.into());
        pack_u128(ref low, packed::EXP2_64, packed::EXP2_36, value.restricted_until.into());

        return Store::<u128>::write_at_offset(address_domain, base, offset, low);
    }

    #[inline(always)]
    fn size() -> u8 {
        return 1;
    }
}

fn allowances_base(base: StorageBaseAddress) -> StorageBaseAddress {
    let mut to_hash: Array<felt252> = Default::default();
    to_hash.append(starknet::storage_address_from_base(base).into());
    to_hash.append('building_allowances');
    return starknet::storage_base_address_from_felt252(to_hash.hash());
}

fn read_building_allowances(
    address_domain: u32, base: StorageBaseAddress, offset: u8, length: u8
) -> Span<BuildingAllowance> {
    let mut allowances: Array<BuildingAllowance> = Default::default();
    let mut iter: u8 = 0;

    loop {
        if iter >= length { break; };
        let raw = Store::<felt252>::read_at_offset(address_domain, base, offset + iter).unwrap();
        let raw_u64: u64 = raw.try_into().unwrap();
        let building_type = raw_u64 % 256;
        let count = raw_u64 / 256;
        allowances.append(BuildingAllowance { building_type: building_type, count: count });
        iter += 1;
    };

    return allowances.span();
}

fn write_building_allowances(
    mut allowances: Span<BuildingAllowance>, address_domain: u32, base: StorageBaseAddress, offset: u8
) -> u8 {
    let mut iter: u8 = 0;

    loop {
        match allowances.pop_front() {
            Option::Some(allowance) => {
                let raw: felt252 = (*allowance.building_type + *allowance.count * 256).into();
                Store::<felt252>::write_at_offset(address_domain, base, offset + iter, raw).unwrap_syscall();
                iter += 1;
            },
            Option::None(_) => {
                break;
            },
        };
    };

    return iter;
}
