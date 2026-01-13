use hash::LegacyHash;
use option::OptionTrait;
use starknet::{ClassHash, ContractAddress, SyscallResultTrait};
use starknet::class_hash::Felt252TryIntoClassHash;
use starknet::storage_access::StorageAddress;
use traits::{Into, TryInto};

#[derive(Copy, Drop, Serde)]
struct Context {
    caller: ContractAddress,
    now: u64,
    payment_to: ContractAddress,
    payment_amount: u64
}

trait ContextTrait {
    fn is_admin(self: Context) -> bool;
}

const SELECTOR: felt252 = 0x3fcec3aaf5f6b9511b7cf944cd33aae089925e7701f84b0983428e149e86b80; // role_grants

impl ContextImpl of ContextTrait {
    fn is_admin(self: Context) -> bool {
        let caller: felt252 = self.caller.into();
        let hashed = LegacyHash::hash(LegacyHash::hash(SELECTOR, caller), 1);
        let base = starknet::storage_base_address_from_felt252(hashed);
        let address = starknet::storage_address_from_base_and_offset(base, 0);
        return starknet::storage_read_syscall(0, address).unwrap_syscall() == 1;
    }
}
