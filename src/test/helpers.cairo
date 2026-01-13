use array::{ArrayTrait, SpanTrait};
use debug::PrintTrait;
use option::OptionTrait;
use result::ResultTrait;
use traits::TryInto;
use starknet::{ClassHash, Felt252TryIntoClassHash, ContractAddress, deploy_syscall};

use influence::{config, contracts, systems};
use influence::contracts::{Asteroid, Crew, Crewmate, Dispatcher, Ship, Sway};
use influence::contracts::sway::{ISwayDispatcher, ISwayDispatcherTrait};

fn init() {
    let mut dispatcher_state = Dispatcher::contract_state_for_testing();
    Dispatcher::constructor(ref dispatcher_state, starknet::contract_address_const::<'ADMIN'>());
}

fn gas_report(log: felt252, prev: u128) -> u128 {
    let mut gas = testing::get_available_gas();
    log.print();

    if prev != 0 {
        (prev - gas).print();
    } else {
        gas.print();
    }

    '----------'.print();
    return gas;
}

fn deploy_system(name: felt252, class_hash_raw: felt252) {
    let class_hash: ClassHash = class_hash_raw.try_into().unwrap();
    deploy_syscall(class_hash, 0, Default::default().span(), false);
    systems::set(name, class_hash);
}

fn deploy_asteroid() -> ContractAddress {
    let class_hash: ClassHash = Asteroid::TEST_CLASS_HASH.try_into().unwrap();
    let calldata = array!['Influence Asteroids', 'INFAST', 'ADMIN'];
    let (address, _) = deploy_syscall(class_hash, 0, calldata.span(), false).unwrap();

    contracts::set('Asteroid', address);
    return address;
}

fn deploy_crew() -> ContractAddress {
    let class_hash: ClassHash = Crew::TEST_CLASS_HASH.try_into().unwrap();
    let calldata = array!['Influence Crew', 'INFCREW', 'ADMIN'];
    let (address, _) = deploy_syscall(class_hash, 0, calldata.span(), false).unwrap();

    contracts::set('Crew', address);
    return address;
}

fn deploy_crewmate() -> ContractAddress {
    let class_hash: ClassHash = Crewmate::TEST_CLASS_HASH.try_into().unwrap();
    let calldata = array!['Influence Crewmate', 'INFCRM', 20000, 'ADMIN'];
    let (address, _) = deploy_syscall(class_hash, 0, calldata.span(), false).unwrap();

    contracts::set('Crewmate', address);
    return address;
}

fn deploy_ship() -> ContractAddress {
    let class_hash: ClassHash = Ship::TEST_CLASS_HASH.try_into().unwrap();
    let calldata = array!['Influence Ship', 'INFSHIP', 'ADMIN'];
    let (address, _) = deploy_syscall(class_hash, 0, calldata.span(), false).unwrap();

    contracts::set('Ship', address);
    return address;
}

fn deploy_sway() -> ContractAddress {
    let class_hash: ClassHash = Sway::TEST_CLASS_HASH.try_into().unwrap();
    let mut constructor_data: Array<felt252> = Default::default();
    constructor_data.append('Standard Weighted Adalian Yield');
    constructor_data.append('SWAY');
    constructor_data.append(6);
    constructor_data.append('ADMIN');
    let (sway_address, _) = deploy_syscall(class_hash, 0, constructor_data.span(), false).unwrap();

    starknet::testing::set_contract_address(starknet::contract_address_const::<'ADMIN'>());
    ISwayDispatcher { contract_address: sway_address }.add_grant(starknet::contract_address_const::<'ADMIN'>(), 2);
    starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());

    contracts::set('Sway', sway_address);
    return sway_address;
}