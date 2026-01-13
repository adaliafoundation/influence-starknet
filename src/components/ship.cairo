use array::{ArrayTrait, SpanTrait};
use cmp::max;
use core::starknet::SyscallResultTrait;
use option::OptionTrait;
use result::ResultTrait;
use starknet::SyscallResult;
use starknet::storage_access::{Store, StorageBaseAddress, storage_base_address_const};
use traits::{Into, TryInto};

use cubit::f128::{Fixed, FixedTrait};

use influence::config::{entities, errors};
use influence::common::{packed, packed::{split_felt252, pack_u128, unpack_u128}};
use influence::components::{ComponentTrait, inventory_type::types as inventory_types,
    process_type::types as process_types, station_type::types as station_types,
    product_type::types as product_types};
use influence::types::entity::{Entity, EntityTrait, Felt252TryIntoEntity};

// Constants ----------------------------------------------------------------------------------------------------------

mod statuses {
    const UNDER_CONSTRUCTION: u64 = 0;
    const AVAILABLE: u64 = 1;
    const DISABLED: u64 = 3;
}

mod variants {
    const STANDARD: u64 = 1;
    const COBALT_PIONEER: u64 = 2;
    const TITANIUM_PIONEER: u64 = 3;
    const AUREATE_PIONEER: u64 = 4;
}

// Component ----------------------------------------------------------------------------------------------------------

#[derive(Copy, Drop, Serde)]
struct Ship {
    ship_type: u64,
    status: u64,
    ready_at: u64, // IRL unix time
    variant: u64, // ship cosmetic variant (per ship type)
    emergency_at: u64, // IRL unix time
    transit_origin: Entity,
    transit_departure: u64, // in-game time since EPOCH
    transit_destination: Entity,
    transit_arrival: u64 // in-game time since EPOCH
}

impl ShipComponent of ComponentTrait<Ship> {
    fn name() -> felt252 {
        return 'Ship';
    }

    fn is_set(data: Ship) -> bool {
        return data.ship_type != 0;
    }

    fn version() -> u64 {
        return 0;
    }
}

trait ShipTrait {
    fn new(ship_type: u64, variant: u64) -> Ship;
    fn assert_ready(self: Ship, now: u64);
    fn assert_stationary(self: Ship);
    fn complete_transit(ref self: Ship);
    fn disable(ref self: Ship);
    fn extend_ready(ref self: Ship, new_ready_at: u64);
}

impl ShipImpl of ShipTrait {
    fn new(ship_type: u64, variant: u64) -> Ship {
        return Ship {
            ship_type: ship_type,
            status: statuses::UNDER_CONSTRUCTION,
            ready_at: 0,
            emergency_at: 0,
            variant: variant,
            transit_origin: EntityTrait::new(0, 0),
            transit_departure: 0,
            transit_destination: EntityTrait::new(0, 0),
            transit_arrival: 0
        };
    }

    fn assert_ready(self: Ship, now: u64) {
        assert(self.status == statuses::AVAILABLE && self.ready_at <= now, errors::SHIP_NOT_READY);
    }

    // Asserts that the ship is available and not in transit
    // TODO: add check for when ship is being delivered (temporarily exploitable)
    fn assert_stationary(self: Ship) {
        assert(self.status == statuses::AVAILABLE && self.transit_departure == 0, 'ship in transit');
    }

    fn complete_transit(ref self: Ship) {
        self.transit_origin = EntityTrait::new(0, 0);
        self.transit_departure = 0;
        self.transit_destination = EntityTrait::new(0, 0);
        self.transit_arrival = 0;
    }

    // Disable ship and remove ongoing emergency
    fn disable(ref self: Ship) {
        self.status = statuses::DISABLED;
        self.emergency_at = 0;
    }

    // Extend ready time
    fn extend_ready(ref self: Ship, new_ready_at: u64) {
        self.ready_at = max(self.ready_at, new_ready_at);
    }
}

// Storage Access -----------------------------------------------------------------------------------------------------

impl StoreShip of Store<Ship> {
    #[inline(always)]
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<Ship> {
        return StoreShip::read_at_offset(address_domain, base, 0);
    }

    #[inline(always)]
    fn write(address_domain: u32, base: StorageBaseAddress, value: Ship) -> SyscallResult<()> {
        return StoreShip::write_at_offset(address_domain, base, 0, value);
    }

    #[inline(always)]
    fn read_at_offset(address_domain: u32, base: StorageBaseAddress, offset: u8) -> SyscallResult<Ship> {
        let combined = Store::<felt252>::read_at_offset(address_domain, base, offset).unwrap();
        let (low, high) = split_felt252(combined);
        let second = Store::<u128>::read_at_offset(address_domain, base, offset + 1).unwrap();

        let ship_type = unpack_u128(low, packed::EXP2_0, packed::EXP2_16).try_into().unwrap();
        let variant = unpack_u128(low, packed::EXP2_28, packed::EXP2_8).try_into().unwrap();
        let mut result = ShipTrait::new(ship_type, variant);

        result.status = unpack_u128(low, packed::EXP2_16, packed::EXP2_4).try_into().unwrap();
        result.ready_at = unpack_u128(low, packed::EXP2_36, packed::EXP2_36).try_into().unwrap();
        result.emergency_at = unpack_u128(second, packed::EXP2_80, packed::EXP2_36).try_into().unwrap();
        result.transit_arrival = unpack_u128(low, packed::EXP2_72, packed::EXP2_40).try_into().unwrap();

        // If not in transit, don't bother unpacking
        if result.transit_arrival != 0 {
            result.transit_origin = unpack_u128(high, packed::EXP2_0, packed::EXP2_80).try_into().unwrap();
            result.transit_departure = unpack_u128(high, packed::EXP2_80, packed::EXP2_40).try_into().unwrap();
            result.transit_destination = unpack_u128(second, packed::EXP2_0, packed::EXP2_80).try_into().unwrap();
        }

        // ready_at and variant swapped due to initial incorrect packing
        // result is a "hole" between bit 20 and 28 (available for future expansion)
        return Result::Ok(result);
    }

    #[inline(always)]
    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: Ship
    ) -> SyscallResult<()> {
        let mut low: u128 = 0;
        let mut high: u128 = 0;
        let mut second: u128 = 0;

        pack_u128(ref low, packed::EXP2_0, packed::EXP2_16, value.ship_type.into());
        pack_u128(ref low, packed::EXP2_16, packed::EXP2_4, value.status.into());
        pack_u128(ref low, packed::EXP2_36, packed::EXP2_36, value.ready_at.into());
        pack_u128(ref second, packed::EXP2_80, packed::EXP2_36, value.emergency_at.into());
        pack_u128(ref low, packed::EXP2_28, packed::EXP2_8, value.variant.into());
        pack_u128(ref high, packed::EXP2_0, packed::EXP2_80, value.transit_origin.into());
        pack_u128(ref high, packed::EXP2_80, packed::EXP2_40, value.transit_departure.into());
        pack_u128(ref second, packed::EXP2_0, packed::EXP2_80, value.transit_destination.into());
        pack_u128(ref low, packed::EXP2_72, packed::EXP2_40, value.transit_arrival.into());

        Store::<u128>::write_at_offset(address_domain, base, offset + 1, second);
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

    use influence::components::ship_type::types as ship_types;
    use influence::config::entities;
    use influence::types::{Entity, EntityTrait};

    use super::{Ship, ShipTrait, StoreShip};

    #[test]
    #[available_gas(1000000)]
    fn test_storage() {
        let base = starknet::storage_base_address_from_felt252(42);
        StoreShip::write(0, base, Ship {
            ship_type: ship_types::LIGHT_TRANSPORT,
            status: 1,
            ready_at: 1576800000,
            emergency_at: 1576800000,
            variant: 1,
            transit_origin: EntityTrait::new(3, 1),
            transit_departure: 21775405632,
            transit_destination: EntityTrait::new(3, 1),
            transit_arrival: 21806768832
        });

        let mut read_ship = StoreShip::read(0, base).unwrap();
        assert(read_ship.ship_type == ship_types::LIGHT_TRANSPORT, 'wrong ship type');
        assert(read_ship.variant == 1, 'wrong variant');
        assert(read_ship.status == 1, 'wrong status');
        assert(read_ship.ready_at == 1576800000, 'wrong ready_at');
        assert(read_ship.emergency_at == 1576800000, 'wrong emergency_at');
        assert(read_ship.transit_origin == EntityTrait::new(3, 1), 'wrong transit_origin');
        assert(read_ship.transit_departure == 21775405632, 'wrong transit_departure');
        assert(read_ship.transit_destination == EntityTrait::new(3, 1), 'wrong transit_destination');
        assert(read_ship.transit_arrival == 21806768832, 'wrong transit_arrival');
    }
}