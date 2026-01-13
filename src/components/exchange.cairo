use array::{ArrayTrait, Span, SpanTrait};
use core::starknet::SyscallResultTrait;
use option::OptionTrait;
use result::ResultTrait;
use starknet::SyscallResult;
use starknet::storage_access::{Store, StorageBaseAddress, storage_base_address_const};
use traits::{Into, TryInto};

use influence::common::{packed, packed::{split_felt252, pack_u128, unpack_u128}};
use influence::components::{ComponentTrait, resolve};
use influence::types::array::ArrayTraitExt;

// Component ----------------------------------------------------------------------------------------------------------

#[derive(Copy, Drop, Serde)]
struct Exchange {
    exchange_type: u64,
    maker_fee: u64, // fee in ten thousandths (i.e. 0.25% == 25)
    taker_fee: u64, // fee in ten thousandths
    orders: u64, // count of open orders
    allowed_products: Span<u64> // whitelist of products allowed for trading on exchange
}

impl ExchangeComponent of ComponentTrait<Exchange> {
    fn name() -> felt252 {
        return 'Exchange';
    }

    fn is_set(data: Exchange) -> bool {
        return data.exchange_type != 0;
    }

    fn version() -> u64 {
        return 0;
    }
}

trait ExchangeTrait {
    fn new(exchange_type: u64) -> Exchange;
}

impl ExchangeImpl of ExchangeTrait {
    fn new(exchange_type: u64) -> Exchange {
        return Exchange {
            exchange_type: exchange_type,
            maker_fee: 0,
            taker_fee: 0,
            orders: 0,
            allowed_products: Default::default().span()
        };
    }
}

// Storage Access -----------------------------------------------------------------------------------------------------

fn pack_product_u128s(mut products: Span<u64>) -> Span<u128> {
    let mut packed_products: Array<u128> = Default::default();
    let mut element = 0;
    let mut iter = 0;
    let mut shift = packed::EXP2_0;

    loop {
        if products.len() == 0 { break; }
        pack_u128(ref element, shift, packed::EXP2_18, (*products.pop_front().unwrap()).into());
        shift *= packed::EXP2_18;
        iter += 1;

        if iter == 6 || products.len() == 0 {
            packed_products.append(element);
            shift = packed::EXP2_0;
            element = 0;
            iter = 0;
        };
    };

    return packed_products.span();
}

fn unpack_product_u128s(mut elements: Span<u128>) -> Span<u64> {
    let mut products: Array<u64> = Default::default();

    if elements.len() == 0 {
        return products.span();
    }

    let mut element = *elements.pop_front().unwrap();

    loop {
        let pos0 = unpack_u128(element, packed::EXP2_0, packed::EXP2_18);
        if pos0 > 0 {
            products.append(pos0.try_into().unwrap());
        } else {
            break;
        }

        let pos1 = unpack_u128(element, packed::EXP2_18, packed::EXP2_18);
        if pos1 > 0 {
            products.append(pos1.try_into().unwrap());
        } else {
            break;
        }

        let pos2 = unpack_u128(element, packed::EXP2_36, packed::EXP2_18);
        if pos2 > 0 {
            products.append(pos2.try_into().unwrap());
        } else {
            break;
        }

        let pos3 = unpack_u128(element, packed::EXP2_54, packed::EXP2_18);
        if pos3 > 0 {
            products.append(pos3.try_into().unwrap());
        } else {
            break;
        }

        let pos4 = unpack_u128(element, packed::EXP2_72, packed::EXP2_18);
        if pos4 > 0 {
            products.append(pos4.try_into().unwrap());
        } else {
            break;
        }

        let pos5 = unpack_u128(element, packed::EXP2_90, packed::EXP2_18);
        if pos5 > 0 {
            products.append(pos5.try_into().unwrap());
        } else {
            break;
        }

        if elements.len() == 0 {break; }
        element = *elements.pop_front().unwrap();
    };

    return products.span();
}

impl StoreExchange of Store<Exchange> {
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<Exchange> {
        return StoreExchange::read_at_offset(address_domain, base, 0);
    }

    fn write(address_domain: u32, base: StorageBaseAddress, value: Exchange) -> SyscallResult<()> {
        return StoreExchange::write_at_offset(address_domain, base, 0, value);
    }

    fn read_at_offset(address_domain: u32, base: StorageBaseAddress, offset: u8) -> SyscallResult<Exchange> {
        let low = Store::<u128>::read_at_offset(address_domain, base, offset)?;
        let allowed_products_len: u8 = unpack_u128(low, packed::EXP2_0, packed::EXP2_8).try_into().unwrap();
        let mut packed_elements: Array<u128> = Default::default();
        let mut iter = 0;

        loop {
            if iter >= allowed_products_len { break; };
            let (low, high) = split_felt252(
                Store::<felt252>::read_at_offset(address_domain, base, offset + iter + 1).unwrap()
            );

            packed_elements.append(low);
            if high != 0 { packed_elements.append(high); }
            iter += 1;
        };

        return Result::Ok(Exchange {
            exchange_type: unpack_u128(low, packed::EXP2_8, packed::EXP2_16).try_into().unwrap(),
            maker_fee: unpack_u128(low, packed::EXP2_24, packed::EXP2_16).try_into().unwrap(),
            taker_fee: unpack_u128(low, packed::EXP2_40, packed::EXP2_16).try_into().unwrap(),
            orders: unpack_u128(low, packed::EXP2_56, packed::EXP2_32).try_into().unwrap(),
            allowed_products: unpack_product_u128s(packed_elements.span())
        });
    }

    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: Exchange
    ) -> SyscallResult<()> {
        let mut packed_elements = pack_product_u128s(value.allowed_products);
        let mut combined: felt252 = 0;
        let mut iter = 0;

        loop {
            if packed_elements.len() == 0 { break; }
            combined = (*packed_elements.pop_front().unwrap()).into();

            if packed_elements.len() > 0 {
                combined += (*packed_elements.pop_front().unwrap()).into() * packed::EXP2_128;
            }

            Store::<felt252>::write_at_offset(address_domain, base, offset + iter + 1, combined);
            iter += 1;
        };

        let mut low: u128 = 0;
        pack_u128(ref low, packed::EXP2_0, packed::EXP2_8, iter.into());
        pack_u128(ref low, packed::EXP2_8, packed::EXP2_16, value.exchange_type.into());
        pack_u128(ref low, packed::EXP2_24, packed::EXP2_16, value.maker_fee.into());
        pack_u128(ref low, packed::EXP2_40, packed::EXP2_16, value.taker_fee.into());
        pack_u128(ref low, packed::EXP2_56, packed::EXP2_32, value.orders.into());

        Store::<u128>::write_at_offset(address_domain, base, offset, low);
        return Result::Ok(());
    }

    #[inline(always)]
    fn size() -> u8 {
        return 255;
    }
}

// Tests ---------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use array::{ArrayTrait, Span, SpanTrait};
    use core::starknet::SyscallResultTrait;
    use option::OptionTrait;
    use result::ResultTrait;
    use starknet::SyscallResult;
    use starknet::storage_access::{Store, StorageBaseAddress, storage_base_address_const};
    use traits::{Into, TryInto};

    use super::{Exchange, ExchangeComponent, ExchangeImpl, ExchangeTrait, StoreExchange};

    #[test]
    #[available_gas(4000000)]
    fn test_storage() {
        let base = starknet::storage_base_address_from_felt252(42);
        let allowed_products: Array<u64> = array![15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1];
        let write_exchange = Exchange {
            exchange_type: 212,
            maker_fee: 25,
            taker_fee: 125,
            orders: 42,
            allowed_products: allowed_products.span()
        };

        StoreExchange::write(0, base, write_exchange);
        let read_exchange = StoreExchange::read(0, base).unwrap();
        assert(read_exchange.exchange_type == 212, 'exchange type wrong');
        assert(read_exchange.maker_fee == 25, 'maker fee wrong');
        assert(read_exchange.taker_fee == 125, 'taker fee wrong');
        assert(read_exchange.orders == 42, 'orders wrong');
        assert(read_exchange.allowed_products.len() == 15, 'contents length wrong');
        assert(*read_exchange.allowed_products.at(0) == 15, 'first product wrong');
        assert(*read_exchange.allowed_products.at(14) == 1, 'last product wrong');
    }

    #[test]
    #[available_gas(4000000)]
    fn test_store_empty() {
        let base = starknet::storage_base_address_from_felt252(42);
        let allowed_products: Array<u64> = Default::default();
        let write_exchange = Exchange {
            exchange_type: 1,
            maker_fee: 0,
            taker_fee: 0,
            orders: 0,
            allowed_products: allowed_products.span()
        };

        StoreExchange::write(0, base, write_exchange);
        let read_exchange = StoreExchange::read(0, base).unwrap();
        assert(read_exchange.exchange_type == 1, 'exchange type wrong');
        assert(read_exchange.maker_fee == 0, 'maker fee wrong');
        assert(read_exchange.taker_fee == 0, 'taker fee wrong');
        assert(read_exchange.orders == 0, 'orders wrong');
        assert(read_exchange.allowed_products.len() == 0, 'contents length wrong');
    }
}