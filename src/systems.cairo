use hash::LegacyHash;
use option::OptionTrait;
use starknet::{ClassHash, class_hash_to_felt252, ContractAddress, SyscallResultTrait};
use starknet::class_hash::Felt252TryIntoClassHash;
use starknet::storage_access::StorageAddress;
use traits::TryInto;

mod agreements;
mod construction;
mod control;
mod crew;
mod deliveries;
mod deposits;
mod emergencies;
mod orders;
mod policies;
mod production;
mod random_events;
mod rewards;
mod sales;
mod scanning;
mod seeding;
mod ship;

mod annotate_event;
mod change_name;
mod configure_exchange;
mod direct_message;
mod helpers;
mod read_component;
mod rekey_inbox;
mod type_component;
mod write_component;

const SELECTOR: felt252 = 0x1c2852b7a8ead7c40858249619f19fe5ab00073db54fc993db455e2f84db68f; // system_registry

fn get(name: felt252) -> ClassHash {
    let base = starknet::storage_base_address_from_felt252(LegacyHash::hash(SELECTOR, name));
    let address = starknet::storage_address_from_base_and_offset(base, 0);
    return starknet::storage_read_syscall(0, address).unwrap_syscall().try_into().unwrap();
}

fn set(name: felt252, value: ClassHash) {
    let base = starknet::storage_base_address_from_felt252(LegacyHash::hash(SELECTOR, name));
    let address = starknet::storage_address_from_base_and_offset(base, 0);
    starknet::storage_write_syscall(0, address, class_hash_to_felt252(value)).unwrap_syscall();
}
