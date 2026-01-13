// Allows a user to designate a different address as the receiver of rewards
// Ex. allows a Goerli user to point to their mainnet Starknet address for testnet rewards

#[starknet::contract]
mod Designate {
    use starknet::{ContractAddress, get_caller_address};

    #[storage]
    struct Storage {
        designees: LegacyMap::<ContractAddress, ContractAddress>
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
      Designated: Designated
    }

    #[derive(Drop, starknet::Event)]
    struct Designated {
        designator: ContractAddress,
        designee: ContractAddress
    }

    #[external(v0)]
    fn designate(ref self: ContractState, designee: ContractAddress) {
        let caller = get_caller_address();
        self.designees.write(caller, designee);

        self.emit(Designated {
            designator: caller,
            designee: designee
        });
    }

    #[external(v0)]
    fn designee(self: @ContractState, designator: ContractAddress) -> ContractAddress {
        return self.designees.read(designator);
    }
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use starknet::ContractAddress;

    use super::Designate;

    #[test]
    #[available_gas(1000000)]
    fn test_constructor() {
        let caller = starknet::contract_address_const::<'PLAYER'>();
        starknet::testing::set_caller_address(caller);

        let mut state = Designate::contract_state_for_testing();
        Designate::designate(ref state, starknet::contract_address_const::<'DESIGNEE'>());
        let res = Designate::designee(@state, caller);

        assert(res == starknet::contract_address_const::<'DESIGNEE'>(), 'designee does not match');
    }
}
