use array::{ArrayTrait, array_slice, Span, SpanTrait};
use dict::{Felt252DictTrait, Felt252DictEntryTrait};
use option::OptionTrait;
use result::ResultTrait;
use serde::Serde;
use starknet::SyscallResult;
use starknet::{Store, StorageBaseAddress, storage_base_address_const};
use traits::{Into, TryInto};

use influence::common::{packed, packed::{split_felt252, pack_u128, unpack_u128}};
use influence::types::array::ArrayTraitExt;

#[derive(Copy, Drop, Serde)]
struct InventoryItem {
    product: u64,
    amount: u64
}

trait InventoryItemTrait {
    fn new(product: u64, amount: u64) -> InventoryItem;
}

impl InventoryItemImpl of InventoryItemTrait {
    #[inline(always)]
    fn new(product: u64, amount: u64) -> InventoryItem {
        return InventoryItem { product: product, amount: amount };
    }
}

impl InventoryItemIntoFelt252 of Into<InventoryItem, felt252> {
    #[inline(always)]
    fn into(self: InventoryItem) -> felt252 {
        return (self.product + self.amount * 262144).into();
    }
}

impl InventoryItemIntoU256 of Into<InventoryItem, u256> {
    #[inline(always)]
    fn into(self: InventoryItem) -> u256 {
        let as_felt: felt252 = self.into();
        return as_felt.into();
    }
}

impl U256TryIntoInventoryItem of TryInto<u256, InventoryItem> {
    #[inline(always)]
    fn try_into(self: u256) -> Option<InventoryItem> {
        let raw: u64 = self.try_into().unwrap();
        let (amount, product) = integer::u64_safe_divmod(raw, 262144_u64.try_into().unwrap());
        return Option::Some(InventoryItem { product: product, amount: amount });
    }
}

impl InventoryItemAdd of Add<InventoryItem> {
    #[inline(always)]
    fn add(lhs: InventoryItem, rhs: InventoryItem) -> InventoryItem {
        assert(lhs.product == rhs.product, 'different products');
        return InventoryItemTrait::new(lhs.product, lhs.amount + rhs.amount);
    }
}

impl InventoryItemAddEq of AddEq<InventoryItem> {
    #[inline(always)]
    fn add_eq(ref self: InventoryItem, other: InventoryItem) {
        assert(self.product == other.product, 'different products');
        self.amount += other.amount;
    }
}

impl InventoryItemSub of Sub<InventoryItem> {
    #[inline(always)]
    fn sub(lhs: InventoryItem, rhs: InventoryItem) -> InventoryItem {
        assert(lhs.product == rhs.product, 'different products');
        assert(lhs.amount >= rhs.amount, 'not enough items');
        return InventoryItemTrait::new(lhs.product, lhs.amount - rhs.amount);
    }
}

impl InventoryItemSubEq of SubEq<InventoryItem> {
    #[inline(always)]
    fn sub_eq(ref self: InventoryItem, other: InventoryItem) {
        assert(self.product == other.product, 'different products');
        assert(self.amount >= other.amount, 'not enough items');
        self.amount -= other.amount;
    }
}

// InventoryContents is an implicit data type consisting of a span of InventoryItems
trait InventoryContentsTrait {
    fn amount_of(self: Span<InventoryItem>, product: u64) -> u64;
    fn read_storage(address_domain: u32, base: StorageBaseAddress, offset: u8, length: u8) -> Span<InventoryItem>;
    fn write_storage(self: Span<InventoryItem>, address_domain: u32, base: StorageBaseAddress, offset: u8) -> u8;
}

impl InventoryContentsImpl of InventoryContentsTrait {
    fn amount_of(mut self: Span<InventoryItem>, product: u64) -> u64 {
        loop {
            match self.pop_front() {
                Option::Some(v) => {
                    if *v.product == product {
                        break *v.amount;
                    }
                },
                Option::None(_) => {
                    break 0;
                },
            };
        }
    }

    fn read_storage(address_domain: u32, base: StorageBaseAddress, offset: u8, length: u8) -> Span<InventoryItem> {
        let mut contents: Array<InventoryItem> = Default::default();
        let mut iter: u8 = 0;

        loop {
            if iter >= length { break; };
            let combined = Store::<felt252>::read_at_offset(address_domain, base, offset + iter).unwrap();
            let (low, high) = split_felt252(combined);

            let pos0 = unpack_u128(high, packed::EXP2_0, packed::EXP2_18).try_into().unwrap();
            if pos0 != 0 {
                contents.append(InventoryItem {
                    product: pos0,
                    amount: unpack_u128(low, packed::EXP2_0, packed::EXP2_32).try_into().unwrap()
                });
            } else {
                break;
            }

            let pos1 = unpack_u128(high, packed::EXP2_18, packed::EXP2_18).try_into().unwrap();
            if pos1 != 0 {
                contents.append(InventoryItem {
                    product: pos1,
                    amount: unpack_u128(low, packed::EXP2_32, packed::EXP2_32).try_into().unwrap()
                });
            } else {
                break;
            }

            let pos2 = unpack_u128(high, packed::EXP2_36, packed::EXP2_18).try_into().unwrap();
            if pos2 != 0 {
                contents.append(InventoryItem {
                    product: pos2,
                    amount: unpack_u128(low, packed::EXP2_64, packed::EXP2_32).try_into().unwrap()
                });
            } else {
                break;
            }

            let pos3 = unpack_u128(high, packed::EXP2_54, packed::EXP2_18).try_into().unwrap();
            if pos3 != 0 {
                contents.append(InventoryItem {
                    product: pos3,
                    amount: unpack_u128(low, packed::EXP2_96, packed::EXP2_32).try_into().unwrap()
                });
            } else {
                break;
            }

            let pos4 = unpack_u128(high, packed::EXP2_72, packed::EXP2_18).try_into().unwrap();
            if pos4 != 0 {
                contents.append(InventoryItem {
                    product: pos4,
                    amount: unpack_u128(high, packed::EXP2_90, packed::EXP2_32).try_into().unwrap()
                });
            } else {
                break;
            }

            iter += 1;
        };

        return contents.span();
    }

    fn write_storage(self: Span<InventoryItem>, address_domain: u32, base: StorageBaseAddress, offset: u8) -> u8 {
        let mut iter: u8 = 0;

        loop {
            let len = self.len();
            let start: usize = (iter * 5).into();
            let mut low: u128 = 0;
            let mut high: u128 = 0;

            if start < len {
                pack_u128(ref high, packed::EXP2_0, packed::EXP2_18, (*self.at(start)).product.into());
                pack_u128(ref low, packed::EXP2_0, packed::EXP2_32, (*self.at(start)).amount.into());
            } else {
                break;
            }

            if start + 1 < len {
                pack_u128(ref high, packed::EXP2_18, packed::EXP2_18, (*self.at(start + 1)).product.into());
                pack_u128(ref low, packed::EXP2_32, packed::EXP2_32, (*self.at(start + 1)).amount.into());
            }

            if start + 2 < len {
                pack_u128(ref high, packed::EXP2_36, packed::EXP2_18, (*self.at(start + 2)).product.into());
                pack_u128(ref low, packed::EXP2_64, packed::EXP2_32, (*self.at(start + 2)).amount.into());
            }

            if start + 3 < len {
                pack_u128(ref high, packed::EXP2_54, packed::EXP2_18, (*self.at(start + 3)).product.into());
                pack_u128(ref low, packed::EXP2_96, packed::EXP2_32, (*self.at(start + 3)).amount.into());
            }

            if start + 4 < len {
                pack_u128(ref high, packed::EXP2_72, packed::EXP2_18, (*self.at(start + 4)).product.into());
                pack_u128(ref high, packed::EXP2_90, packed::EXP2_32, (*self.at(start + 4)).amount.into());
            }

            let combined = low.into() + high.into() * packed::EXP2_128;
            Store::<felt252>::write_at_offset(address_domain, base, offset + iter, combined);
            iter += 1;
        };

        return iter;
    }
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use option::OptionTrait;
    use traits::{Into, TryInto};

    use influence::common::packed;
    use influence::types::array::ArrayTraitExt;

    use super::{InventoryItem, InventoryItemTrait, U256TryIntoInventoryItem};

    #[test]
    #[available_gas(50000)]
    fn test_item_packing() {
        let item = InventoryItemTrait::new(69, 42);
        let raw: felt252 = item.into();
        assert(raw == 11010117, 'wrong raw value');
    }

    #[test]
    #[available_gas(100000)]
    fn test_item_unpacking() {
        let raw: u256 = 11010117;
        let item: InventoryItem = raw.try_into().unwrap();
        assert(item.product == 69, 'wrong resource type');
        assert(item.amount == 42, 'wrong amount');
    }
}