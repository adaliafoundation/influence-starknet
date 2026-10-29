use influence::systems::missions::ClaimMissionReward::{
    Event, MissionAccepted, MissionCompleted, MissionRewardClaimed
};
use influence::contracts::sway::{ISwayDispatcher, ISwayDispatcherTrait};
use array::{ArrayTrait, SpanTrait};
use option::OptionTrait;
use serde::Serde;
use traits::{Into, TryInto};
use starknet::{ClassHash, ContractAddress, SyscallResultTrait};
use influence::components;
use influence::components::Mission;
use influence::types::{Context, Entity, EntityTrait};

#[derive(Copy, Drop, Serde)]
struct Assignment {
    campaign: felt252,
    subject: Entity,
    mission: u32
}

fn read(path: Span<felt252>) -> felt252 {
    match components::get::<Mission>(path) {
        Option::Some(v) => v.value,
        Option::None(_) => 0
    }
}

fn write(path: Span<felt252>, value: felt252) {
    if read(path) != value {
        components::set::<Mission>(path, Mission { value });
    }
}

fn state(a: Assignment, slot: felt252) -> felt252 {
    read(array!['Evidence', a.campaign, a.subject.into(), slot].span())
}

fn set_state(a: Assignment, slot: felt252, value: felt252) {
    write(array!['Evidence', a.campaign, a.subject.into(), slot].span(), value);
}

fn bit(index: u32) -> u128 {
    assert(index < 128, 'invalid bit');
    let mut b = 1_u128;
    let mut i = 0;
    loop {
        if i == index {
            break;
        };
        b *= 2;
        i += 1;
    };
    b
}

fn lifecycle(a: Assignment) -> u128 {
    read(array!['Lifecycle', a.campaign, a.subject.into(), (a.mission / 32).into()].span())
        .try_into()
        .unwrap()
}

fn has_flag(word: u128, mission: u32, kind: u32) -> bool {
    assert(kind < 3, 'invalid lifecycle flag');
    word / bit(kind * 32 + mission % 32) % 2 == 1
}

fn flag(a: Assignment, kind: u32) -> bool {
    has_flag(lifecycle(a), a.mission, kind)
}

fn emit(event: Event) {
    let mut keys = array![];
    let mut data = array![];
    starknet::Event::append_keys_and_data(@event, ref keys, ref data);
    starknet::syscalls::emit_event_syscall(keys.span(), data.span()).unwrap_syscall();
}

fn set_flag(a: Assignment, kind: u32) {
    let word = lifecycle(a);
    if !has_flag(word, a.mission, kind) {
        let page = a.mission / 32;
        let path = array!['Lifecycle', a.campaign, a.subject.into(), page.into()].span();
        components::set::<
            Mission
        >(path, Mission { value: (word + bit(kind * 32 + a.mission % 32)).into() });
        if kind == 0 {
            emit(
                Event::MissionAccepted(
                    MissionAccepted { campaign: a.campaign, subject: a.subject, mission: a.mission }
                )
            );
        } else if kind == 1 {
            emit(
                Event::MissionCompleted(
                    MissionCompleted {
                        campaign: a.campaign, subject: a.subject, mission: a.mission
                    }
                )
            );
        }
    }
}

fn implementation(a: Assignment) -> ClassHash {
    let count: u32 = read(array!['DefinitionCount', a.campaign].span()).try_into().unwrap();
    assert(a.mission < count, 'unknown mission');
    let raw = read(array!['Definition', a.campaign].span());
    assert(raw != 0, 'unknown campaign');
    raw.try_into().unwrap()
}

fn evaluate(
    a: Assignment, operation: u32, action: felt252, args: Span<felt252>, context: Context
) -> Span<felt252> {
    let mut data = array![];
    Serde::<Assignment>::serialize(@a, ref data);
    Serde::<u32>::serialize(@operation, ref data);
    data.append(action);
    Serde::<Span<felt252>>::serialize(@args, ref data);
    Serde::<Context>::serialize(@context, ref data);
    starknet::syscalls::library_call_syscall(implementation(a), selector!("evaluate"), data.span())
        .unwrap_syscall()
}

fn set_lock(value: felt252) {
    let address = components::resolve('Mission', array!['ExecutionLock'].span());
    starknet::Store::<felt252>::write(0, address, value).unwrap_syscall();
}

fn lock() {
    let path = array!['ExecutionLock'].span();
    assert(read(path) == 0, 'mission reentry');
    set_lock(1);
}

fn unlock() {
    set_lock(0);
}

fn accept(a: Assignment, context: Context) {
    assert(!flag(a, 0), 'mission already accepted');
    lock();
    evaluate(a, 0, 0, array![].span(), context);
    set_flag(a, 0);
    evaluate(a, 2, 0, array![].span(), context);
    unlock();
}

fn validate(a: Assignment, args: Span<felt252>, context: Context) {
    assert(flag(a, 0), 'mission not accepted');
    lock();
    evaluate(a, 2, 0, args, context);
    unlock();
}

fn claim(a: Assignment, context: Context) {
    let word = lifecycle(a);
    assert(has_flag(word, a.mission, 0) && has_flag(word, a.mission, 1), 'mission incomplete');
    assert(!has_flag(word, a.mission, 2), 'reward already paid');
    lock();
    let mut raw = evaluate(a, 3, 0, array![].span(), context);
    let (beneficiary, amount) = Serde::<(ContractAddress, u128)>::deserialize(ref raw).unwrap();
    assert(raw.is_empty(), 'invalid reward response');
    assert(!beneficiary.is_zero(), 'invalid beneficiary');
    set_flag(a, 2);
    assert(
        ISwayDispatcher { contract_address: influence::contracts::get('Sway') }
            .transfer(beneficiary, amount.into()),
        'reward transfer failed'
    );
    emit(
        Event::MissionRewardClaimed(
            MissionRewardClaimed {
                campaign: a.campaign,
                subject: a.subject,
                mission: a.mission,
                recipient: beneficiary,
                amount
            }
        )
    );
    unlock();
}

