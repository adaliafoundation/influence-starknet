use array::{ArrayTrait, SpanTrait};
use serde::Serde;
use option::OptionTrait;
use traits::Into;
use influence::types::{Entity, EntityTrait};

fn key(kind: felt252, entity: Entity, slot: u64) -> felt252 {
    poseidon::poseidon_hash_span(array![kind, entity.into(), slot.into()].span())
}

fn hash<T, impl S: Serde<T>, impl D: Drop<T>>(value: @T) -> felt252 {
    let mut data = array![];
    Serde::<T>::serialize(value, ref data);
    poseidon::poseidon_hash_span(data.span())
}

fn parse<T, impl S: Serde<T>, impl D: Drop<T>>(mut args: Span<felt252>) -> T {
    let value = Serde::<T>::deserialize(ref args).expect('invalid mission arguments');
    assert(args.is_empty(), 'trailing mission arguments');
    value
}

fn encoded<T, impl S: Serde<T>, impl D: Drop<T>>(value: @T) -> Array<felt252> {
    let mut data = array![];
    Serde::<T>::serialize(value, ref data);
    data
}

fn segment(data: Span<felt252>, start: u32, length: u32) -> Span<felt252> {
    let mut output = array![];
    let mut i = 0;
    loop {
        if i == length {
            break;
        }
        output.append(*data.at(start + i));
        i += 1;
    };
    output.span()
}
