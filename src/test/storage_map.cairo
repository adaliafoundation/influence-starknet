use core::hash::LegacyHash;
use starknet::{ClassHash, ContractAddress};
use starknet::storage_access::storage_base_address_from_felt252;
use traits::Into;

#[starknet::contract]
mod StorageMapCompatibility {
    use starknet::{ClassHash, ContractAddress};
    use starknet::storage::{Map, StorageAsPointer, StoragePathEntry};
    use traits::Into;

    #[storage]
    struct Storage {
        address_key: Map::<ContractAddress, u256>,
        address_pair_key: Map::<(ContractAddress, ContractAddress), u256>,
        felt_key: Map::<felt252, felt252>,
        u64_key: Map::<u64, u256>,
        address_u64_key: Map::<(ContractAddress, u64), bool>,
        u256_key: Map::<u256, ContractAddress>,
        class_hash_key: Map::<felt252, ClassHash>,
    }

    fn address_key_address(self: @ContractState, key: ContractAddress) -> felt252 {
        self.address_key.entry(key).as_ptr().__storage_pointer_address__.into()
    }

    fn address_pair_key_address(
        self: @ContractState, key: (ContractAddress, ContractAddress)
    ) -> felt252 {
        self.address_pair_key.entry(key).as_ptr().__storage_pointer_address__.into()
    }

    fn felt_key_address(self: @ContractState, key: felt252) -> felt252 {
        self.felt_key.entry(key).as_ptr().__storage_pointer_address__.into()
    }

    fn u64_key_address(self: @ContractState, key: u64) -> felt252 {
        self.u64_key.entry(key).as_ptr().__storage_pointer_address__.into()
    }

    fn address_u64_key_address(self: @ContractState, key: (ContractAddress, u64)) -> felt252 {
        self.address_u64_key.entry(key).as_ptr().__storage_pointer_address__.into()
    }

    fn u256_key_address(self: @ContractState, key: u256) -> felt252 {
        self.u256_key.entry(key).as_ptr().__storage_pointer_address__.into()
    }

    fn class_hash_key_address(self: @ContractState, key: felt252) -> felt252 {
        self.class_hash_key.entry(key).as_ptr().__storage_pointer_address__.into()
    }
}

fn legacy_map_address<Key, impl KeyLegacyHash: LegacyHash<Key>>(
    field_selector: felt252, key: Key
) -> felt252 {
    storage_base_address_from_felt252(LegacyHash::hash(field_selector, key)).into()
}

#[test]
fn test_map_storage_addresses_match_legacy_map_formula() {
    let state = StorageMapCompatibility::contract_state_for_testing();
    let account = starknet::contract_address_const::<'ACCOUNT'>();
    let operator = starknet::contract_address_const::<'OPERATOR'>();

    // Field selectors are sn_keccak(field_name), matching the legacy storage base formula.
    assert(
        StorageMapCompatibility::address_key_address(@state, account)
            == legacy_map_address(
                0x3b5f948d459d42c92d23d62117ec334958b7c0cd114d1aa8dc49afe76121bc9,
                account
            ),
        'address key mismatch'
    );
    assert(
        StorageMapCompatibility::address_pair_key_address(@state, (account, operator))
            == legacy_map_address(
                0x3c2e1a9399f39a995bd7c3d032fa9720a819e90558f02efa8fb727f414219c4,
                (account, operator)
            ),
        'address pair key mismatch'
    );
    assert(
        StorageMapCompatibility::felt_key_address(@state, 'sample_key')
            == legacy_map_address(
                0x28b0b806fd40c8ab7845b66619dc13a182f33a2b7de47813c6b405f8458da41,
                'sample_key'
            ),
        'felt key mismatch'
    );
    assert(
        StorageMapCompatibility::u64_key_address(@state, 42)
            == legacy_map_address(
                0x1946895bc82346038e429273f0cbe6cbd883f8712d2ff886b5ce0117380e12,
                42_u64
            ),
        'u64 key mismatch'
    );
    assert(
        StorageMapCompatibility::address_u64_key_address(@state, (account, 42))
            == legacy_map_address(
                0x3d95db12bd917f23103903ef34ecb43a467683b4cc2746550e9eb56694eb0e1,
                (account, 42_u64)
            ),
        'address u64 key mismatch'
    );
    assert(
        StorageMapCompatibility::u256_key_address(@state, 123456)
            == legacy_map_address(
                0x2affa8929a71eea819d48319e017a4ecadb04d9275a8908db571d58f711fc0a,
                123456_u256
            ),
        'u256 key mismatch'
    );
    assert(
        StorageMapCompatibility::class_hash_key_address(@state, 'class_hash')
            == legacy_map_address(
                0x22797298f45a381b97677cf5746ce04ea013358c577495731d4fedf772aeb35,
                'class_hash'
            ),
        'class hash value mismatch'
    );
}
