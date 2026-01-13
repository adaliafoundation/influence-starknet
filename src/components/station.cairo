use array::{ArrayTrait, SpanTrait};
use core::starknet::SyscallResultTrait;
use option::OptionTrait;
use result::ResultTrait;
use starknet::SyscallResult;
use starknet::storage_access::{Store, StorageBaseAddress, storage_base_address_const};
use traits::{Into, TryInto};

use cubit::f64::{Fixed, FixedTrait};

use influence::common::{packed, packed::{pack_u128, unpack_u128}};
use influence::components::{ComponentTrait, resolve};
use influence::types::entity::{Entity, EntityTrait, Felt252TryIntoEntity};

// Component ----------------------------------------------------------------------------------------------------------

#[derive(Copy, Drop, Serde)]
struct Station {
    station_type: u64,
    population: u64 // current population in # of crews
}

impl StationComponent of ComponentTrait<Station> {
    fn name() -> felt252 {
        return 'Station';
    }

    fn is_set(data: Station) -> bool {
        return data.station_type != 0;
    }

    fn version() -> u64 {
        return 0;
    }
}

trait StationTrait {
    fn new(station_type: u64) -> Station;
    fn assert_empty(self: Station);
}

impl StationImpl of StationTrait {
    fn new(station_type: u64) -> Station {
        return Station { station_type: station_type, population: 0 };
    }

    fn assert_empty(self: Station) {
        assert(self.population == 0, 'station is not empty');
    }

    // fn assert_space_available(self: Station, to_add: u64) {
    //     assert(self.population + to_add <= config(self.station_type).cap, 'station is full');
    // }
}

// Storage Access -----------------------------------------------------------------------------------------------------

impl StoreStation of Store<Station> {
    #[inline(always)]
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<Station> {
        return StoreStation::read_at_offset(address_domain, base, 0);
    }

    #[inline(always)]
    fn write(address_domain: u32, base: StorageBaseAddress, value: Station) -> SyscallResult<()> {
        return StoreStation::write_at_offset(address_domain, base, 0, value);
    }

    #[inline(always)]
    fn read_at_offset(address_domain: u32, base: StorageBaseAddress, offset: u8) -> SyscallResult<Station> {
        let low = Store::<u128>::read_at_offset(address_domain, base, offset)?;

        return Result::Ok(Station {
            station_type: unpack_u128(low, packed::EXP2_0, packed::EXP2_16).try_into().unwrap(),
            population: unpack_u128(low, packed::EXP2_16, packed::EXP2_32).try_into().unwrap()
        });
    }

    #[inline(always)]
    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: Station
    ) -> SyscallResult<()> {
        let mut low: u128 = 0;

        pack_u128(ref low, packed::EXP2_0, packed::EXP2_16, value.station_type.into());
        pack_u128(ref low, packed::EXP2_16, packed::EXP2_32, value.population.into());

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

    use influence::common::packed;
    use influence::components::{ComponentTrait, resolve, station_type::types as station_types};
    use influence::types::entity::{Entity, EntityTrait, Felt252TryIntoEntity};

    use super::{Station, StationTrait, StationImpl, StoreStation};

    #[test]
    #[available_gas(1500000)]
    fn test_storage() {
        let base = starknet::storage_base_address_from_felt252(42);
        let mut station = StationTrait::new(station_types::HABITAT);

        StoreStation::write(0, base, station);
        let mut read_station = StoreStation::read(0, base).unwrap();
        assert(read_station.population == 0, 'wrong population');

        station.population = 100;
        StoreStation::write(0, base, station);
        read_station = StoreStation::read(0, base).unwrap();
        assert(read_station.population == 100, 'wrong cap');
    }
}