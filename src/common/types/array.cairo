use array::{ArrayTrait, SpanTrait, serialize_array_helper, deserialize_array_helper};
use core::starknet::SyscallResultTrait;
use option::{Option, OptionTrait};
use poseidon::poseidon_hash_span;
use result::ResultTrait;
use starknet::{Store, StorageBaseAddress, SyscallResult};
use traits::{Into, TryInto};

trait ArrayHashTrait {
    fn hash(self: @Array<felt252>) -> felt252;
}

impl ArrayHashImpl of ArrayHashTrait {
    fn hash(self: @Array<felt252>) -> felt252 {
        return poseidon_hash_span(self.span());
    }
}

trait SpanHashTrait {
    fn hash(self: Span<felt252>) -> felt252;
}

impl SpanHashImpl of SpanHashTrait {
    fn hash(self: Span<felt252>) -> felt252 {
        return poseidon_hash_span(self);
    }
}

trait ArrayTraitExt<T> {
    fn append_all(ref self: Array<T>, ref arr: Array<T>);
    fn pop_front_n(ref self: Array<T>, n: usize);
    fn reverse(self: @Array<T>) -> Array<T>;
    fn contains<impl TPartialEq: PartialEq<T>>(self: @Array<T>, item: T) -> bool;
    fn index_of<impl TPartialEq: PartialEq<T>>(self: @Array<T>, item: T) -> Option<usize>;
    fn find<impl TPartialEq: PartialEq<T>>(self: @Array<T>, item: T) -> Option<T>;
    fn occurrences_of<impl TPartialEq: PartialEq<T>>(self: @Array<T>, item: T) -> usize;
    fn min<impl TPartialEq: PartialEq<T>, impl TPartialOrd: PartialOrd<T>>(
        self: @Array<T>
    ) -> Option<T>;
    fn index_of_min<impl TPartialEq: PartialEq<T>, impl TPartialOrd: PartialOrd<T>>(
        self: @Array<T>
    ) -> Option<usize>;
    fn max<impl TPartialEq: PartialEq<T>, impl TPartialOrd: PartialOrd<T>>(
        self: @Array<T>
    ) -> Option<T>;
    fn index_of_max<impl TPartialEq: PartialEq<T>, impl TPartialOrd: PartialOrd<T>>(
        self: @Array<T>
    ) -> Option<usize>;
}

trait SpanTraitExt<T> {
    fn pop_front_n(ref self: Span<T>, n: usize);
    fn pop_back_n(ref self: Span<T>, n: usize);
    fn reverse(self: Span<T>) -> Array<T>;
    fn contains<impl TPartialEq: PartialEq<T>>(self: Span<T>, item: T) -> bool;
    fn index_of<impl TPartialEq: PartialEq<T>>(self: Span<T>, item: T) -> Option<usize>;
    fn find<impl TPartialEq: PartialEq<T>>(self: Span<T>, item: T) -> Option<T>;
    fn occurrences_of<impl TPartialEq: PartialEq<T>>(self: Span<T>, item: T) -> usize;
    fn min<impl TPartialEq: PartialEq<T>, impl TPartialOrd: PartialOrd<T>>(
        self: Span<T>
    ) -> Option<T>;
    fn index_of_min<impl TPartialEq: PartialEq<T>, impl TPartialOrd: PartialOrd<T>>(
        self: Span<T>
    ) -> Option<usize>;
    fn max<impl TPartialEq: PartialEq<T>, impl TPartialOrd: PartialOrd<T>>(
        self: Span<T>
    ) -> Option<T>;
    fn index_of_max<impl TPartialEq: PartialEq<T>, impl TPartialOrd: PartialOrd<T>>(
        self: Span<T>
    ) -> Option<usize>;
}

impl ArrayExtImpl<T, impl TCopy: Copy<T>, impl TDrop: Drop<T>> of ArrayTraitExt<T> {
    fn append_all(ref self: Array<T>, ref arr: Array<T>) {
        match arr.pop_front() {
            Option::Some(v) => {
                self.append(v);
                self.append_all(ref arr);
            },
            Option::None(()) => (),
        }
    }

    fn pop_front_n(ref self: Array<T>, mut n: usize) {
        // Can't do self.span().pop_front_n();
        loop {
            if n == 0 {
                break ();
            }
            match self.pop_front() {
                Option::Some(v) => {
                    n -= 1;
                },
                Option::None(_) => {
                    break ();
                },
            };
        };
    }

    fn reverse(self: @Array<T>) -> Array<T> {
        self.span().reverse()
    }

    fn contains<impl TPartialEq: PartialEq<T>>(self: @Array<T>, item: T) -> bool {
        self.span().contains(item)
    }

    fn index_of<impl TPartialEq: PartialEq<T>>(self: @Array<T>, item: T) -> Option<usize> {
        self.span().index_of(item)
    }

    fn find<impl TPartialEq: PartialEq<T>>(self: @Array<T>, item: T) -> Option<T> {
        self.span().find(item)
    }

    fn occurrences_of<impl TPartialEq: PartialEq<T>>(self: @Array<T>, item: T) -> usize {
        self.span().occurrences_of(item)
    }

    fn min<impl TPartialEq: PartialEq<T>, impl TPartialOrd: PartialOrd<T>>(
        self: @Array<T>
    ) -> Option<T> {
        self.span().min()
    }

    fn index_of_min<impl TPartialEq: PartialEq<T>, impl TPartialOrd: PartialOrd<T>>(
        self: @Array<T>
    ) -> Option<usize> {
        self.span().index_of_min()
    }

    fn max<impl TPartialEq: PartialEq<T>, impl TPartialOrd: PartialOrd<T>>(
        self: @Array<T>
    ) -> Option<T> {
        self.span().max()
    }

    fn index_of_max<impl TPartialEq: PartialEq<T>, impl TPartialOrd: PartialOrd<T>>(
        mut self: @Array<T>
    ) -> Option<usize> {
        self.span().index_of_max()
    }
}

impl SpanImpl<T, impl TCopy: Copy<T>, impl TDrop: Drop<T>> of SpanTraitExt<T> {
    fn pop_front_n(ref self: Span<T>, mut n: usize) {
        loop {
            if n == 0 {
                break ();
            }
            match self.pop_front() {
                Option::Some(v) => {
                    n -= 1;
                },
                Option::None(_) => {
                    break ();
                },
            };
        };
    }

    fn pop_back_n(ref self: Span<T>, mut n: usize) {
        loop {
            if n == 0 {
                break ();
            }
            match self.pop_back() {
                Option::Some(v) => {
                    n -= 1;
                },
                Option::None(_) => {
                    break ();
                },
            };
        };
    }

    fn reverse(mut self: Span<T>) -> Array<T> {
        let mut response: Array<T> = Default::default();
        loop {
            match self.pop_back() {
                Option::Some(v) => {
                    response.append(*v);
                },
                Option::None(_) => {
                    break (); // Can't `break response;` "Variable was previously moved"
                },
            };
        };
        response
    }

    fn contains<impl TPartialEq: PartialEq<T>>(mut self: Span<T>, item: T) -> bool {
        loop {
            match self.pop_front() {
                Option::Some(v) => {
                    if *v == item {
                        break true;
                    }
                },
                Option::None(_) => {
                    break false;
                },
            };
        }
    }

    fn index_of<impl TPartialEq: PartialEq<T>>(mut self: Span<T>, item: T) -> Option<usize> {
        let mut index = 0_usize;
        loop {
            match self.pop_front() {
                Option::Some(v) => {
                    if *v == item {
                        break Option::Some(index);
                    }
                    index += 1;
                },
                Option::None(_) => {
                    break Option::None(());
                },
            };
        }
    }

    fn find<impl TPartialEq: PartialEq<T>>(mut self: Span<T>, item: T) -> Option<T> {
        loop {
            match self.pop_front() {
                Option::Some(v) => {
                    if *v == item {
                        break Option::Some(*v);
                    }
                },
                Option::None(_) => {
                    break Option::None(());
                },
            };
        }
    }

    fn occurrences_of<impl TPartialEq: PartialEq<T>>(mut self: Span<T>, item: T) -> usize {
        let mut count = 0_usize;
        loop {
            match self.pop_front() {
                Option::Some(v) => {
                    if *v == item {
                        count += 1;
                    }
                },
                Option::None(_) => {
                    break count;
                },
            };
        }
    }

    fn min<impl TPartialEq: PartialEq<T>, impl TPartialOrd: PartialOrd<T>>(
        mut self: Span<T>
    ) -> Option<T> {
        let mut min = match self.pop_front() {
            Option::Some(item) => *item,
            Option::None(_) => {
                return Option::None(());
            },
        };
        loop {
            match self.pop_front() {
                Option::Some(item) => {
                    if *item < min {
                        min = *item
                    }
                },
                Option::None(_) => {
                    break Option::Some(min);
                },
            };
        }
    }

    fn index_of_min<impl TPartialEq: PartialEq<T>, impl TPartialOrd: PartialOrd<T>>(
        mut self: Span<T>
    ) -> Option<usize> {
        let mut index = 0;
        let mut index_of_min = 0;
        let mut min: T = match self.pop_front() {
            Option::Some(item) => *item,
            Option::None(_) => {
                return Option::None(());
            },
        };
        loop {
            match self.pop_front() {
                Option::Some(item) => {
                    if *item < min {
                        index_of_min = index + 1;
                        min = *item;
                    }
                },
                Option::None(_) => {
                    break Option::Some(index_of_min);
                },
            };
            index += 1;
        }
    }

    fn max<impl TPartialEq: PartialEq<T>, impl TPartialOrd: PartialOrd<T>>(
        mut self: Span<T>
    ) -> Option<T> {
        let mut max = match self.pop_front() {
            Option::Some(item) => *item,
            Option::None(_) => {
                return Option::None(());
            },
        };
        loop {
            match self.pop_front() {
                Option::Some(item) => {
                    if *item > max {
                        max = *item
                    }
                },
                Option::None(_) => {
                    break Option::Some(max);
                },
            };
        }
    }

    fn index_of_max<impl TPartialEq: PartialEq<T>, impl TPartialOrd: PartialOrd<T>>(
        mut self: Span<T>
    ) -> Option<usize> {
        let mut index = 0;
        let mut index_of_max = 0;
        let mut max = match self.pop_front() {
            Option::Some(item) => *item,
            Option::None(_) => {
                return Option::None(());
            },
        };
        loop {
            match self.pop_front() {
                Option::Some(item) => {
                    if *item > max {
                        index_of_max = index + 1;
                        max = *item
                    }
                },
                Option::None(_) => {
                    break Option::Some(index_of_max);
                },
            };
            index += 1;
        }
    }
}

impl StoreArray of Store<Array<felt252>> {
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<Array<felt252>> {
        return StoreArray::read_at_offset(address_domain, base, 0);
    }

    fn write(address_domain: u32, base: StorageBaseAddress, value: Array<felt252>) -> SyscallResult<()> {
        return StoreArray::write_at_offset(address_domain, base, 0, value);
    }

    fn read_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8
    ) -> SyscallResult<Array<felt252>> {
        let len = Store::<u8>::read_at_offset(address_domain, base, offset).unwrap();
        let mut result: Array<felt252> = Default::default();
        let mut iter: u8 = 0;

        loop {
            if iter >= len { break(); }
            let el = Store::<felt252>::read_at_offset(
                address_domain, base, offset + iter + 1).unwrap();
            result.append(el);
            iter += 1;
        };

        return Result::Ok(result);
    }

    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: Array<felt252>
    ) -> SyscallResult<()> {
        let len: u8 = value.len().try_into().unwrap();
        Store::<u8>::write_at_offset(address_domain, base, offset, len);
        let mut iter: u8 = 0;

        loop {
            if iter >= len { break(); }
            let el = *value.at(iter.into());
            Store::<felt252>::write_at_offset(address_domain, base, offset + iter + 1, el);
            iter += 1;
        };

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
    use array::{ArrayTrait, SpanTrait, serialize_array_helper, deserialize_array_helper};
    use option::{Option, OptionTrait};
    use poseidon::poseidon_hash_span;

    use super::ArrayTraitExt;

    #[test]
    #[available_gas(1000000)]
    fn test_array_ext_append_all() {
        let mut arr = array![4, 5, 6];
        let mut result = array![1, 2];
        result.append_all(ref arr);

        assert(*result.at(2) == 4, 'result[2] == 4');
        assert(*result.at(3) == 5, 'result[2] == 5');
        assert(*result.at(4) == 6, 'result[2] == 6');
    }
}
