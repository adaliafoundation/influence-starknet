#[starknet::contract]
mod DirectMessage {
    use array::{Array, ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use starknet::ContractAddress;

    use influence::types::Context;

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct DirectMessageSent {
        recipient: ContractAddress,
        content_hash: Span<felt252>, // IPFS content hash
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        DirectMessageSent: DirectMessageSent
    }

    #[external(v0)]
    fn run(ref self: ContractState, recipient: ContractAddress, content_hash: Span<felt252>, context: Context) {
        self.emit(DirectMessageSent {
            recipient: recipient,
            content_hash: content_hash,
            caller: context.caller
        });
    }
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use traits::{Into, TryInto};
    use starknet::testing;

    use influence::test::mocks;

    use super::DirectMessage;

    #[test]
    #[available_gas(4000000)]
    fn test_dm() {
        let recipient = starknet::contract_address_const::<'RECIPIENT'>();
        let mut content_hash: Array<felt252> = Default::default();
        content_hash.append('QmPjtFx2b8gx4kBEX3xZmCafmyWdfDj');
        content_hash.append('8UkNqfQGmFvtg4U');
        starknet::testing::set_block_timestamp(100);
        let context = mocks::context('PLAYER');

        let mut state = DirectMessage::contract_state_for_testing();
        DirectMessage::run(ref state, recipient, content_hash.span(), context);
    }
}
