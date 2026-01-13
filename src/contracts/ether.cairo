use starknet::ContractAddress;

// Mock contract to simulate ETH during tests
#[starknet::contract]
mod Ether {
    use array::{ArrayTrait};
    use clone::{Clone};
    use option::{OptionTrait};
    use starknet::{ClassHash, ContractAddress, get_caller_address};
    use traits::{Into, TryInto};
    use zeroable::Zeroable;

    use influence::interfaces::erc20::IERC20;

    #[storage]
    struct Storage {
        _name: felt252,
        _symbol: felt252,
        _decimals: u8,
        _total_supply: u256,
        balances: LegacyMap::<ContractAddress, u256>,
        allowances: LegacyMap::<(ContractAddress, ContractAddress), u256>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Transfer: Transfer,
        Approval: Approval,
    }

    #[derive(Drop, starknet::Event)]
    struct Transfer {
        from: ContractAddress,
        to: ContractAddress,
        value: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Approval {
        owner: ContractAddress,
        spender: ContractAddress,
        value: u256,
    }

    #[constructor]
    fn constructor(ref self: ContractState, name: felt252, symbol: felt252, decimals: u8) {
        self._name.write(name);
        self._symbol.write(symbol);
        self._decimals.write(decimals);
    }

    // ERC20 ----------------------------------------------------------------------------------------------------------

    #[external(v0)]
    fn allowance(self: @ContractState, owner: ContractAddress, spender: ContractAddress) -> u256 {
        return self.allowances.read((owner, spender));
    }

    #[external(v0)]
    fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool {
        let caller = get_caller_address();
        _approve(ref self, caller, spender, amount);
        return true;
    }

    #[external(v0)]
    fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
        return self.balances.read(account);
    }

    #[external(v0)]
    fn balanceOf(self: @ContractState, account: ContractAddress) -> u256 {
        return balance_of(self, account);
    }

    #[external(v0)]
    fn decimals(self: @ContractState) -> u8 {
        return self._decimals.read();
    }

    #[external(v0)]
    fn decrease_allowance(ref self: ContractState, spender: ContractAddress, subtracted_value: u256) {
        let caller = get_caller_address();
        _approve(ref self, caller, spender, self.allowances.read((caller, spender)) - subtracted_value);
    }

    #[external(v0)]
    fn decreaseAllowance(ref self: ContractState, spender: ContractAddress, subtracted_value: u256) {
        return decrease_allowance(ref self, spender, subtracted_value);
    }

    #[external(v0)]
    fn increase_allowance(ref self: ContractState, spender: ContractAddress, added_value: u256) {
        let caller = get_caller_address();
        _approve(ref self, caller, spender, self.allowances.read((caller, spender)) + added_value);
    }

    #[external(v0)]
    fn increaseAllowance(ref self: ContractState, spender: ContractAddress, subtracted_value: u256) {
        return increaseAllowance(ref self, spender, subtracted_value);
    }

    #[external(v0)]
    fn name(self: @ContractState) -> felt252 {
        return self._name.read();
    }

    #[external(v0)]
    fn symbol(self: @ContractState) -> felt252 {
        return self._symbol.read();
    }

    #[external(v0)]
    fn total_supply(self: @ContractState) -> u256 {
        return self._total_supply.read();
    }

    #[external(v0)]
    fn totalSupply(self: @ContractState) -> u256 {
        return total_supply(self);
    }

    #[external(v0)]
    fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) {
        let sender = get_caller_address();
        _transfer(ref self, sender, recipient, amount);
    }

    #[external(v0)]
    fn transfer_from(ref self: ContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256) {
        let caller = get_caller_address();
        _spend_allowance(ref self, sender, caller, amount);
        _transfer(ref self, sender, recipient, amount);
    }

    #[external(v0)]
    fn transferFrom(ref self: ContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256) {
        return transfer_from(ref self, sender, recipient, amount);
    }

    // Private --------------------------------------------------------------------------------------------------------

    fn _transfer(ref self: ContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256) {
        assert(!sender.is_zero(), 'ERC20: transfer from 0');
        assert(!recipient.is_zero(), 'ERC20: transfer to 0');
        self.balances.write(sender, self.balances.read(sender) - amount);
        self.balances.write(recipient, self.balances.read(recipient) + amount);
        self.emit(Transfer { from: sender, to: recipient, value: amount });
    }

    fn _spend_allowance(ref self: ContractState, owner: ContractAddress, spender: ContractAddress, amount: u256) {
        let current_allowance = self.allowances.read((owner, spender));
        let ONES_MASK = 0xffffffffffffffffffffffffffffffff_u128;
        let is_unlimited_allowance = (current_allowance.low == ONES_MASK) & (current_allowance.high == ONES_MASK);

        if !is_unlimited_allowance {
            _approve(ref self, owner, spender, current_allowance - amount);
        }
    }

    fn _approve(ref self: ContractState, owner: ContractAddress, spender: ContractAddress, amount: u256) {
        assert(!spender.is_zero(), 'ERC20: approve from 0');
        self.allowances.write((owner, spender), amount);
        self.emit(Approval { owner, spender, value: amount });
    }

    fn _burn(ref self: ContractState, account: ContractAddress, amount: u256) {
        assert(!account.is_zero(), 'ERC20: burn from 0');
        self._total_supply.write(self._total_supply.read() - amount);
        self.balances.write(account, self.balances.read(account) - amount);
        self.emit(Transfer { from: account, to:  Zeroable::zero(), value: amount });
    }

    fn _mint(ref self: ContractState, recipient: ContractAddress, amount: u256) {
        assert(!recipient.is_zero(), 'ERC20: mint to 0');
        self._total_supply.write(self._total_supply.read() + amount);
        self.balances.write(recipient, self.balances.read(recipient) + amount);
        self.emit(Transfer { from: Zeroable::zero(), to: recipient, value: amount });
    }
}
