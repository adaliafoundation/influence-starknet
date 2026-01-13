#[starknet::contract]
mod ClaimTestnetSway {
    use array::{ArrayTrait, SpanTrait};
    use hash::LegacyHash;
    use option::OptionTrait;
    use starknet::ContractAddress;
    use traits::{Into, TryInto};

    use influence::{components, config, contracts};
    use influence::components::{Unique, UniqueTrait};
    use influence::config::errors;
    use influence::contracts::sway::{ISwayDispatcher, ISwayDispatcherTrait};
    use influence::types::{Context, MerkleTree, MerkleTreeTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct TestnetSwayClaimed {
        amount: u256,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        TestnetSwayClaimed: TestnetSwayClaimed
    }

    #[external(v0)]
    fn run(ref self: ContractState, proof: Span<felt252>, amount: u256, context: Context) {
        // Calculate Merkle leaf (address, amount)
        let leaf = LegacyHash::<felt252>::hash(context.caller.into(), amount.try_into().unwrap());

        // Verify Merkle proof
        let mut merkle_tree = MerkleTreeTrait::new();
        let expected_root = merkle_tree.compute_root(leaf, proof);
        let actual_root = config::get('TESTNET_SWAY_MERKLE_ROOT');
        assert(expected_root == actual_root, errors::INVALID_MERKLE_PROOF);

        // Whitelist for > 5 million SWAY
        if amount > 5000000 * 1000000 {
            let mut whitelist_path: Array<felt252> = Default::default();
            whitelist_path.append('TestnetSwayWhitelist');
            whitelist_path.append(context.caller.into());
            assert(components::get::<Unique>(whitelist_path.span()).is_some(), 'not whitelisted');
        }

        // Check if already claimed
        let mut unique_path: Array<felt252> = Default::default();
        unique_path.append('TestnetSwayClaimed');
        unique_path.append(context.caller.into());
        assert(components::get::<Unique>(unique_path.span()).is_none(), errors::NOT_UNIQUE);

        // Send SWAY to caller
        ISwayDispatcher { contract_address: contracts::get('Sway') }.transfer(context.caller, amount);

        // Mark as claimed
        components::set::<Unique>(unique_path.span(), UniqueTrait::new());

        self.emit(TestnetSwayClaimed {
            amount: amount,
            caller: context.caller
        });
    }
}

// Tests --------------------------------------------------------------------------------------------------------------

use starknet::ContractAddress;

use influence::types::Context;

#[starknet::interface]
trait IClaimTestnetSway<TContractState> {
    fn run(
        ref self: TContractState,
        proof: Span<felt252>,
        amount: u256,
        context: Context
    );
}

#[cfg(test)]
mod tests {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use starknet::{ClassHash, ContractAddress, deploy_syscall};
    use traits::{Into, TryInto};

    use influence::{components, config};
    use influence::contracts::sway::{ISwayDispatcher, ISwayDispatcherTrait};
    use influence::components::{Unique, UniqueTrait};
    use influence::test::{helpers, mocks};

    use super::{ClaimTestnetSway, IClaimTestnetSwayLibraryDispatcher, IClaimTestnetSwayDispatcherTrait};

    #[test]
    #[available_gas(10000000)]
    #[should_panic(expected: ('E6014: not unique', 'ENTRYPOINT_FAILED'))]
    fn test_testnet_claim() {
        let caller = starknet::contract_address_const::<'ADMIN'>();
        starknet::testing::set_caller_address(caller);

        // Deploy SWAY
        let sway_address = helpers::deploy_sway();
        let amount: u256 = 1000000 * 1000000;
        starknet::testing::set_contract_address(caller);
        let sway = ISwayDispatcher { contract_address: sway_address };
        sway.mint(starknet::contract_address_const::<'DISPATCHER'>(), amount);

        // call TestnetSwayClaimed
        let player = 0x048242eca329a05af1909fa79cb1f9a4275ff89b987d405ec7de08f73b85588f;
        let mut proof: Array<felt252> = Default::default();
        proof.append(0x7f71c40cde1208b8ef7ad6e011c407206c7d459d4a1dc7607c9fbbfe87e7a22);
        proof.append(0x264a126e543031617cbd89bc91ed69892d3e83c1af5176c584e409287b95ad5);
        proof.append(0x782b939020ec114f3d17f7cd90ff232b63cb6528945a240f0df9811603a10f0);
        proof.append(0xbf3c3522a01c576d70567813ce1653c4e8fd89cec71168a6e28055fe131ee3);
        proof.append(0x25707ba924b5587cef1117eef0a2169a4010259a24f1b1223aab7e6d112276b);
        proof.append(0x7f0e80bb3157944afa8b9b0c78e3db1b52f1731da8c8c7fd46becde2c71e4f1);
        proof.append(0x78c13c564ae0622442843aee8079497777bc2587dda0ecedb551f44ca32dccc);
        proof.append(0x616a2fa6c6e6652c223cc9a541eba17565e2800674a9acaa88c9aac861a489e);
        proof.append(0x5d38b52162f39f2b572d315ba1a59178484d6a743944190a3c48fb3d47f8e56);
        proof.append(0xcd41dff07fc8ec90ce6dcae9a2c2dc7647b4bf60f6eb8fbe7aa4004ef3ea56);
        proof.append(0x675204ee5f847306d3c2ca0eeb4a9e48bc45ea1cedd874fd6f74de915f4d36);
        proof.append(0x68fce8d4a9123cbd4f65c4c7db7c6b1595e3ad1f9356ea3e45ac58cc2f64600);

        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        config::set('TESTNET_SWAY_MERKLE_ROOT', 0x762286a1db1960b969e8762b884f3c851eb8624f22d9186abf9d983880c3db2);
        let class_hash: ClassHash = ClaimTestnetSway::TEST_CLASS_HASH.try_into().unwrap();
        IClaimTestnetSwayLibraryDispatcher { class_hash: class_hash }.run(
            proof.span(), 278824 * 1000000, mocks::context(player)
        );

        // Verify SWAY transfer
        assert(sway.balance_of(player.try_into().unwrap()) == 278824 * 1000000, 'Invalid SWAY balance');

        // Try to claim again
        IClaimTestnetSwayLibraryDispatcher { class_hash: class_hash }.run(
            proof.span(), 278824 * 1000000, mocks::context(player)
        );
    }

    #[test]
    #[available_gas(10000000)]
    #[should_panic(expected: ('not whitelisted', 'ENTRYPOINT_FAILED'))]
    fn test_whitelisted_claim_fail() {
        let caller = starknet::contract_address_const::<'ADMIN'>();
        starknet::testing::set_caller_address(caller);

        // Deploy SWAY
        let sway_address = helpers::deploy_sway();
        let amount: u256 = 10000000 * 1000000;
        starknet::testing::set_contract_address(caller);
        let sway = ISwayDispatcher { contract_address: sway_address };
        sway.mint(starknet::contract_address_const::<'DISPATCHER'>(), amount);

        // call TestnetSwayClaimed
        let player = 0x006b8f42f782c1ceb3aa8a767a41cb12d0531f8c08a38cf9e8e763f82cf73d2f;
        let mut proof: Array<felt252> = Default::default();
        proof.append(0x6e6a44a5055fafde998802a150ca5292e0e86a859562e7483bf24d384347e29);
        proof.append(0x17075cacfb5d5931e6a78174d115af9d8084f6b8ada54555dd49a1c50d18ce2);
        proof.append(0x3ab30e588d7f75b7fe7f2356acf372fa28cc815928b906c6b4c823dbb4fd5c);
        proof.append(0x7b2e4efa13246192412006490aa04ba5639b633c45a68c8086c70b2e2da3d03);
        proof.append(0x63031ccffa4df64e11275118b12307bd3bd511c73549387d10422ce0b1f2991);
        proof.append(0xe593371a021b9508e9d66ba5d4bfd1167a18bedb02eb6d589dbac5b078aef4);
        proof.append(0x25b0fb420a93fb710874f660fdaa94e3486a9fd0b4b9d499b2e411798a995b5);
        proof.append(0x61ae3419cc47b36f80bb9e4640a2e52b4a7d7a3c73399da86c93f1c78ca77ed);
        proof.append(0x3a587140108131d17182848a56f3134bc6d2980d8bfb74d143e6d89944bedab);
        proof.append(0xcd41dff07fc8ec90ce6dcae9a2c2dc7647b4bf60f6eb8fbe7aa4004ef3ea56);
        proof.append(0x675204ee5f847306d3c2ca0eeb4a9e48bc45ea1cedd874fd6f74de915f4d36);
        proof.append(0x68fce8d4a9123cbd4f65c4c7db7c6b1595e3ad1f9356ea3e45ac58cc2f64600);

        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        config::set('TESTNET_SWAY_MERKLE_ROOT', 0x762286a1db1960b969e8762b884f3c851eb8624f22d9186abf9d983880c3db2);
        let class_hash: ClassHash = ClaimTestnetSway::TEST_CLASS_HASH.try_into().unwrap();
        IClaimTestnetSwayLibraryDispatcher { class_hash: class_hash }.run(
            proof.span(), 5055637 * 1000000, mocks::context(player)
        );
    }
}
