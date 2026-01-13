use hash::LegacyHash;
use option::OptionTrait;
use starknet::{contract_address, contract_address_to_felt252, ContractAddress, SyscallResultTrait};
use starknet::class_hash::Felt252TryIntoClassHash;
use starknet::storage_access::StorageAddress;
use traits::TryInto;

mod asteroid;
mod contract_policy;
mod crew;
mod crewmate;
mod designate;
mod dispatcher;
mod escrow;
mod ether;
mod ship;
mod sway;

use asteroid::Asteroid;
use contract_policy::ContractPolicy;
use crew::Crew;
use crewmate::Crewmate;
use designate::Designate;
use dispatcher::Dispatcher;
use ether::Ether;
use ship::Ship;
use sway::Sway;

const SELECTOR: felt252 = 0x2361a02d123003fad95d3f4ec2191474a1462bc52c050f04491cee9fe4b8aae; // contract_registry

fn get(name: felt252) -> ContractAddress {
    let base = starknet::storage_base_address_from_felt252(LegacyHash::hash(SELECTOR, name));
    let address = starknet::storage_address_from_base_and_offset(base, 0);
    return starknet::storage_read_syscall(0, address).unwrap_syscall().try_into().expect('not contract address');
}

fn set(name: felt252, value: ContractAddress) {
    let base = starknet::storage_base_address_from_felt252(LegacyHash::hash(SELECTOR, name));
    let address = starknet::storage_address_from_base_and_offset(base, 0);
    starknet::storage_write_syscall(0, address, contract_address_to_felt252(value)).unwrap_syscall();
}
