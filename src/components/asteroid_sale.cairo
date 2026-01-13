use array::{ArrayTrait, Span, SpanTrait};
use core::starknet::SyscallResultTrait;
use option::OptionTrait;
use result::ResultTrait;
use starknet::{ContractAddress, Felt252TryIntoContractAddress, SyscallResult};
use starknet::storage_access::{Store, StorageBaseAddress, storage_base_address_const};
use traits::{Into, TryInto};

use influence::components::{ComponentTrait, resolve};

#[derive(Copy, Drop, Serde)]
struct AsteroidSale {
    volume: u64
}

impl AsteroidSaleComponent of ComponentTrait<AsteroidSale> {
    fn name() -> felt252 {
        return 'AsteroidSale';
    }

    fn is_set(data: AsteroidSale) -> bool {
        return data.volume != 0;
    }

    fn version() -> u64 {
        return 0;
    }
}

// Storage Access -----------------------------------------------------------------------------------------------------

impl StoreAsteroidSale of Store<AsteroidSale> {
    #[inline(always)]
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<AsteroidSale> {
        return StoreAsteroidSale::read_at_offset(address_domain, base, 0);
    }

    #[inline(always)]
    fn write(address_domain: u32, base: StorageBaseAddress, value: AsteroidSale) -> SyscallResult<()> {
        return StoreAsteroidSale::write_at_offset(address_domain, base, 0, value);
    }

    #[inline(always)]
    fn read_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8
    ) -> SyscallResult<AsteroidSale> {
        let res = Store::<u64>::read_at_offset(address_domain, base, offset)?;
        return Result::Ok(AsteroidSale { volume: res });
    }

    #[inline(always)]
    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: AsteroidSale
    ) -> SyscallResult<()> {
        return Store::<u64>::write_at_offset(address_domain, base, offset, value.volume);
    }

    #[inline(always)]
    fn size() -> u8 {
        return 1;
    }
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use option::OptionTrait;
    use result::ResultTrait;
    use starknet::Store;

    use super::AsteroidSale;

    #[test]
    #[available_gas(1000000)]
    fn test_storage() {
    let base = starknet::storage_base_address_from_felt252(42);
        let sale = AsteroidSale { volume: 25 };

        Store::<AsteroidSale>::write(0, base, sale);
        let read_asteroid_sale = Store::<AsteroidSale>::read(0, base).unwrap();

        assert(sale.volume == read_asteroid_sale.volume, 'volume wrong');
    }
}
