#[starknet::contract]
mod RekeyInbox {
    use array::{Array, ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use starknet::ContractAddress;
    use traits::Into;

    use influence::{components, contracts};
    use influence::components::{Account, AccountTrait};
    use influence::config::errors;
    use influence::types::{Context, Entity, EntityTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct RekeyedInbox {
        messaging_key_x: u256,
        messaging_key_y: u256,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        RekeyedInbox: RekeyedInbox
    }

    #[external(v0)]
    fn run(ref self: ContractState, messaging_key_x: u256, messaging_key_y: u256, context: Context) {
        let mut unique_key: Array<felt252> = Default::default();
        unique_key.append(context.caller.into());
        components::set::<Account>(unique_key.span(), AccountTrait::new(messaging_key_x, messaging_key_y));

        self.emit(RekeyedInbox {
            messaging_key_x: messaging_key_x,
            messaging_key_y: messaging_key_y,
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

    use influence::components;
    use influence::components::Account;
    use influence::types::entity::EntityTrait;
    use influence::test::{helpers, mocks};

    use super::RekeyInbox;

    #[test]
    #[available_gas(4000000)]
    fn test_rekey_inbox() {
        let context = mocks::context('PLAYER');

        let mut state = RekeyInbox::contract_state_for_testing();
        let messaging_key_x = 0x1234567890abcdef;
        let messaging_key_y = 0xabcdef1234567890;
        RekeyInbox::run(ref state, messaging_key_x, messaging_key_y, context);

        // Check that the account was created
        let mut unique_key: Array<felt252> = Default::default();
        unique_key.append(context.caller.into());

        let account = components::get::<Account>(unique_key.span()).expect('account not set');
        assert(account.messaging_key_x == messaging_key_x, 'wrong key x');
        assert(account.messaging_key_y == messaging_key_y, 'wrong key y');
    }
}
