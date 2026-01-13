use starknet::{ContractAddress, EthAddress};

#[starknet::interface]
trait ISway<TContractState> {
    fn mint(ref self: TContractState, recipient: ContractAddress, amount: u256);

    fn transfer_with_confirmation(
        ref self: TContractState,
        recipient: ContractAddress,
        amount: u128,
        memo: felt252,
        consumer: ContractAddress
    ) -> bool;

    fn transfer_from_with_confirmation(
        ref self: TContractState,
        sender: ContractAddress,
        recipient: ContractAddress,
        amount: u128,
        memo: felt252,
        consumer: ContractAddress
    ) -> bool;

    fn confirm_receipt(
        ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u128, memo: felt252
    );

    // Permissions
    fn add_grant(ref self: TContractState, account: ContractAddress, role: u64);
    fn has_grant(self: @TContractState, account: ContractAddress, role: u64) -> bool;
    fn revoke_grant(ref self: TContractState, account: ContractAddress, role: u64);

    // Bridging
    fn get_l1_bridge(self: @TContractState) -> EthAddress;
    fn get_l2_token(self: @TContractState) -> ContractAddress;
    fn set_l1_bridge(ref self: TContractState, l1_bridge: EthAddress);
    fn initiate_withdrawal(ref self: TContractState, l1_recipient: EthAddress, amount: u256);
    fn handle_deposit(
        ref self: TContractState,
        from_address: felt252, // L1 Bridge
        to_address: ContractAddress, // L2 destination account
        amount_low: felt252,
        amount_high: felt252
    );

    // Governor Messaging
    fn set_l1_sway_volume_address(ref self: TContractState, l1_sway_volume_address: EthAddress);

    // ERC20
    fn allowance(self: @TContractState, owner: ContractAddress, spender: ContractAddress) -> u256;
    fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> bool;
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
    fn balanceOf(self: @TContractState, account: ContractAddress) -> u256;
    fn decimals(self: @TContractState) -> u8;
    fn decrease_allowance(ref self: TContractState, spender: ContractAddress, subtracted_value: u256);
    fn decreaseAllowance(ref self: TContractState, spender: ContractAddress, subtracted_value: u256);
    fn increase_allowance(ref self: TContractState, spender: ContractAddress, added_value: u256);
    fn increaseAllowance(ref self: TContractState, spender: ContractAddress, added_value: u256);
    fn name(self: @TContractState) -> felt252;
    fn symbol(self: @TContractState) -> felt252;
    fn total_supply(self: @TContractState) -> u256;
    fn totalSupply(self: @TContractState) -> u256;
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256) -> bool;
    fn transfer_from(ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256) -> bool;
    fn transferFrom(ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256) -> bool;
}

#[starknet::contract]
mod Sway {
    use array::{ArrayTrait};
    use clone::{Clone};
    use option::{OptionTrait};
    use starknet::{ClassHash, ContractAddress, get_caller_address, info::get_block_timestamp};
    use starknet::eth_address::{EthAddress, EthAddressZeroable, Felt252TryIntoEthAddress};
    use starknet::syscalls::{send_message_to_l1_syscall, replace_class_syscall};
    use traits::{Into, TryInto};
    use zeroable::Zeroable;

    use influence::interfaces::erc20::IERC20;

    const RECORDING_PERIOD: u64 = 1000000; // in seconds

    mod roles {
        const ADMIN: u64 = 1;
    }

    #[storage]
    struct Storage {
        _decimals: u8,
        _name: felt252,
        _symbol: felt252,
        _total_supply: u256,
        allowances: LegacyMap::<(ContractAddress, ContractAddress), u256>,
        balances: LegacyMap::<ContractAddress, u256>,
        confirmations: LegacyMap::<felt252, felt252>,
        l1_bridge_address: EthAddress,
        l1_sway_volume_address: EthAddress,
        period_volumes: LegacyMap::<u64, u256>,
        role_grants: LegacyMap::<(ContractAddress, u64), bool>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Transfer: Transfer,
        Approval: Approval,
        DepositHandled: DepositHandled,
        WithdrawInitiated: WithdrawInitiated,
        ConfirmationCreated: ConfirmationCreated,
        ReceiptConfirmed: ReceiptConfirmed,
        L1BridgeUpdated: L1BridgeUpdated
    }

    #[derive(Drop, starknet::Event)]
    struct Transfer {
        #[key]
        from: ContractAddress,
        #[key]
        to: ContractAddress,
        value: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Approval {
        #[key]
        owner: ContractAddress,
        #[key]
        spender: ContractAddress,
        value: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct DepositHandled {
        account: ContractAddress,
        amount: u256,
        sender: EthAddress
    }

    #[derive(Drop, starknet::Event)]
    struct WithdrawInitiated {
        l1_recipient: EthAddress,
        amount: u256,
        caller_address: ContractAddress
    }

    #[derive(Drop, starknet::Event)]
    struct ConfirmationCreated {
        from: ContractAddress,
        to: ContractAddress,
        value: u128,
        memo: felt252,
        consumer: ContractAddress
    }

    #[derive(Drop, starknet::Event)]
    struct ReceiptConfirmed {
        from: ContractAddress,
        to: ContractAddress,
        value: u128,
        memo: felt252,
        consumer: ContractAddress
    }

    #[derive(Drop, starknet::Event)]
    struct L1BridgeUpdated {
        address: EthAddress
    }

    #[constructor]
    fn constructor(ref self: ContractState, name: felt252, symbol: felt252, decimals: u8, admin: ContractAddress) {
        self._name.write(name);
        self._symbol.write(symbol);
        self._decimals.write(decimals);
        self.role_grants.write((admin, roles::ADMIN), true);
    }

    // Upgrade allows for the contract to be upgraded to a new implementation. Only the admin
    // role is capable of calling this function. The initial admin role will be revoked after deploy on mainnet
    // and successful audit to ensure immutability.
    #[external(v0)]
    fn upgrade(ref self: ContractState, class_hash: ClassHash) {
        assert(self.role_grants.read((get_caller_address(), roles::ADMIN)), 'SWAY: must be admin');
        replace_class_syscall(class_hash);
    }

    // Mint allows for the creation of new tokens. Only the admin role is capable of calling this function.
    // The initial admin role will be revoked after deploy on mainnet and successful audit to ensure immutability.
    #[external(v0)]
    fn mint(ref self: ContractState, recipient: ContractAddress, amount: u256) {
        assert(self.role_grants.read((get_caller_address(), roles::ADMIN)), 'ERC20: must be admin');
        _mint(ref self, recipient, amount);
    }

    // Generates a confirmation receipt for a transfer specifying a consumer contract that can consume it
    #[external(v0)]
    fn transfer_with_confirmation(
        ref self: ContractState,
        recipient: ContractAddress,
        amount: u128,
        memo: felt252,
        consumer: ContractAddress
    ) -> bool {
        let caller_address: ContractAddress = starknet::get_caller_address();
        assert(memo != 0, 'SWAY: memo cannot be zero');

        let mut to_hash: Array<felt252> = Default::default();
        to_hash.append(caller_address.into());
        to_hash.append(recipient.into());
        to_hash.append(amount.into());
        to_hash.append(memo);
        to_hash.append(consumer.into());
        let hashed = poseidon::poseidon_hash_span(to_hash.span());

        assert(self.confirmations.read(hashed) == 0, 'SWAY: already confirmed');
        self.confirmations.write(hashed, memo);
        transfer(ref self, recipient, amount.into());

        self.emit(ConfirmationCreated {
            from: caller_address,
            to: recipient,
            value: amount,
            memo: memo,
            consumer: consumer
        });

        return true;
    }

    #[external(v0)]
    fn transfer_from_with_confirmation(
        ref self: ContractState,
        sender: ContractAddress,
        recipient: ContractAddress,
        amount: u128,
        memo: felt252,
        consumer: ContractAddress
    ) -> bool {
        assert(memo != 0, 'SWAY: memo cannot be zero');

        let mut to_hash: Array<felt252> = Default::default();
        to_hash.append(sender.into());
        to_hash.append(recipient.into());
        to_hash.append(amount.into());
        to_hash.append(memo);
        to_hash.append(consumer.into());
        let hashed = poseidon::poseidon_hash_span(to_hash.span());

        assert(self.confirmations.read(hashed) == 0, 'SWAY: already confirmed');
        self.confirmations.write(hashed, memo);
        transfer_from(ref self, sender, recipient, amount.into());

        self.emit(ConfirmationCreated {
            from: sender,
            to: recipient,
            value: amount,
            memo: memo,
            consumer: consumer
        });

        return true;
    }

    // Confirms a receipt from a previously created confirmation (via transfer_with_confirmation)
    // The caller must be the previously specified consumer of the receipt
    #[external(v0)]
    fn confirm_receipt(
        ref self: ContractState, sender: ContractAddress, recipient: ContractAddress, amount: u128, memo: felt252
    ) {
        let caller_address: ContractAddress = starknet::get_caller_address();

        let mut to_hash: Array<felt252> = Default::default();
        to_hash.append(sender.into());
        to_hash.append(recipient.into());
        to_hash.append(amount.into());
        to_hash.append(memo);
        to_hash.append(caller_address.into());
        let hashed = poseidon::poseidon_hash_span(to_hash.span());

        assert(self.confirmations.read(hashed) != 0, 'SWAY: invalid receipt');
        self.confirmations.write((hashed), 0);

        self.emit(ReceiptConfirmed {
            from: sender,
            to: recipient,
            value: amount,
            memo: memo,
            consumer: caller_address
        });
    }

    #[external(v0)]
    fn confirmReceipt(
        ref self: ContractState, sender: ContractAddress, recipient: ContractAddress, amount: u128, memo: felt252
    ) {
        confirm_receipt(ref self, sender, recipient, amount, memo);
    }

    // Bridging -------------------------------------------------------------------------------------------------------

    #[external(v0)]
    fn get_l1_bridge(self: @ContractState) -> EthAddress {
        return self.l1_bridge_address.read();
    }

    #[external(v0)]
    fn get_l2_token(self: @ContractState) -> ContractAddress {
        return starknet::get_contract_address();
    }

    // Set the L1 bridge address to allow L2 <-> L1 bridging. Only the admin role is capable of calling this function.
    // The initial admin role will be revoked after deploy on mainnet and successful audit to ensure immutability.
    #[external(v0)]
    fn set_l1_bridge(ref self: ContractState, l1_bridge: EthAddress) {
        assert(self.role_grants.read((get_caller_address(), roles::ADMIN)), 'SWAY: must be admin');
        self.l1_bridge_address.write(l1_bridge);
        self.emit(L1BridgeUpdated { address: l1_bridge });
    }

    #[external(v0)]
    fn initiate_withdrawal(ref self: ContractState, l1_recipient: EthAddress, amount: u256) {
        let l1_bridge_address = self.l1_bridge_address.read();
        assert(amount != 0, 'Bridge: zero withdrawal');
        assert(l1_bridge_address.into() != 0, 'Bridge: zero bridge address');

        // Burn the tokens (i.e. send to zero)
        _burn(ref self, get_caller_address(), amount);

        // Send message to L1
        let mut payload: Array<felt252> = Default::default();
        payload.append(1); // PROCESS_WITHDRAWAL
        payload.append(l1_recipient.into());
        payload.append(amount.low.into());
        payload.append(amount.high.into());
        send_message_to_l1_syscall(to_address: l1_bridge_address.into(), payload: payload.span());

        self.emit(WithdrawInitiated {
            l1_recipient: l1_recipient,
            amount: amount,
            caller_address: get_caller_address()
        });
    }

    #[l1_handler]
    fn handle_deposit(
        ref self: ContractState,
        from_address: felt252, // L1 Bridge
        to_address: ContractAddress, // L2 destination account
        amount_low: felt252,
        amount_high: felt252,
        sender: felt252
    ) {
        assert(to_address.into() != 0, 'Bridge: zero address');
        assert(self.l1_bridge_address.read().into() != 0, 'Bridge: zero bridge address');
        assert(from_address == self.l1_bridge_address.read().into(), 'Bridge: from l1 bridge only');

        // Mint new tokens
        let amount = u256 { low: amount_low.try_into().unwrap(), high: amount_high.try_into().unwrap() };
        _mint(ref self, to_address, amount);

        self.emit(DepositHandled {
            account: to_address,
            amount: amount,
            sender: sender.try_into().unwrap()
        });
    }

    // Permissions ----------------------------------------------------------------------------------------------------
    // The initial admin role will be revoked after deploy on mainnet and successful audit to ensure immutability.

    #[external(v0)]
    fn add_grant(ref self: ContractState, account: ContractAddress, role: u64) {
        assert(self.role_grants.read((get_caller_address(), roles::ADMIN)), 'ERC20: must be admin');
        self.role_grants.write((account, role), true);
    }

    #[external(v0)]
    fn has_grant(self: @ContractState, account: ContractAddress, role: u64) -> bool {
        return self.role_grants.read((account, role));
    }

    #[external(v0)]
    fn revoke_grant(ref self: ContractState, account: ContractAddress, role: u64) {
        assert(self.role_grants.read((get_caller_address(), roles::ADMIN)), 'ERC20: must be admin');
        self.role_grants.write((account, role), false);
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
        return self.balances.read(account);
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
        decrease_allowance(ref self, spender, subtracted_value);
    }

    #[external(v0)]
    fn increase_allowance(ref self: ContractState, spender: ContractAddress, added_value: u256) {
        let caller = get_caller_address();
        _approve(ref self, caller, spender, self.allowances.read((caller, spender)) + added_value);
    }

    #[external(v0)]
    fn increaseAllowance(ref self: ContractState, spender: ContractAddress, added_value: u256) {
        increase_allowance(ref self, spender, added_value);
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
        return self._total_supply.read();
    }

    #[external(v0)]
    fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
        let sender = get_caller_address();
        _transfer(ref self, sender, recipient, amount);
        return true;
    }

    #[external(v0)]
    fn transfer_from(
        ref self: ContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool {
        let caller = get_caller_address();
        _spend_allowance(ref self, sender, caller, amount);
        _transfer(ref self, sender, recipient, amount);
        return true;
    }

    #[external(v0)]
    fn transferFrom(
        ref self: ContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool {
        transfer_from(ref self, sender, recipient, amount);
        return true;
    }

    // SWAY Governor Messaging ----------------------------------------------------------------------------------------

    #[external(v0)]
    fn set_l1_sway_volume_address(ref self: ContractState, l1_sway_volume_address: EthAddress) {
        assert(self.role_grants.read((get_caller_address(), roles::ADMIN)), 'SWAY: must be admin');
        self.l1_sway_volume_address.write(l1_sway_volume_address);
    }

    #[external(v0)]
    fn send_sway_volume_to_l1(ref self: ContractState, period: u64) {
        let to_address: EthAddress = self.l1_sway_volume_address.read();
        assert(to_address.into() != 0, 'SWAY: zero address');

        let mut payload: Array<felt252> = Default::default();
        payload.append(period.into());
        payload.append(self.period_volumes.read(period).try_into().unwrap());
        send_message_to_l1_syscall(to_address: to_address.into(), payload: payload.span());
    }

    fn current_period() -> u64 {
        return get_block_timestamp() / RECORDING_PERIOD;
    }

    // Private --------------------------------------------------------------------------------------------------------

    fn _transfer(ref self: ContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256) {
        assert(!sender.is_zero(), 'ERC20: transfer from 0');
        assert(!recipient.is_zero(), 'ERC20: transfer to 0');
        let balance = self.balances.read(sender);
        assert(balance >= amount, 'ERC20: insufficient balance');

        self.balances.write(sender, self.balances.read(sender) - amount);
        self.balances.write(recipient, self.balances.read(recipient) + amount);
        _after_token_transfer(ref self, sender, recipient, amount);
        self.emit(Transfer { from: sender, to: recipient, value: amount });
    }

    fn _spend_allowance(ref self: ContractState, owner: ContractAddress, spender: ContractAddress, amount: u256) {
        let current_allowance = self.allowances.read((owner, spender));
        let ONES_MASK = 0xffffffffffffffffffffffffffffffff_u128;
        let is_unlimited_allowance = (current_allowance.low == ONES_MASK) & (current_allowance.high == ONES_MASK);

        assert(current_allowance >= amount, 'ERC20: insufficient allowance');
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

    // Updates the period's volume after transfers (mints / burns excluded)
    fn _after_token_transfer(
        ref self: ContractState, from_address: ContractAddress, to_address: ContractAddress, amount: u256
    ) {
        let period = current_period();
        let period_volume: u256 = self.period_volumes.read(period) + amount;
        self.period_volumes.write(period, period_volume);
    }

    fn _mint(ref self: ContractState, recipient: ContractAddress, amount: u256) {
        assert(!recipient.is_zero(), 'ERC20: mint to 0');
        self._total_supply.write(self._total_supply.read() + amount);
        self.balances.write(recipient, self.balances.read(recipient) + amount);
        self.emit(Transfer { from: Zeroable::zero(), to: recipient, value: amount });
    }
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use traits::{Into, TryInto};
    use starknet::EthAddress;

    use influence::test::helpers;

    use super::Sway;

    #[test]
    #[available_gas(1000000)]
    fn test_constructor() {
        let caller = starknet::contract_address_const::<'ADMIN'>();
        starknet::testing::set_caller_address(caller);

        let mut state = Sway::contract_state_for_testing();
        Sway::constructor(ref state, 'Standard Weighted Adalian Yield', 'SWAY', 6, caller);
        let res = Sway::has_grant(@state, caller, Sway::roles::ADMIN);

        assert(res, 'deployer should be admin');
    }

    #[test]
    #[available_gas(1000000)]
    fn test_grants() {
        let caller = starknet::contract_address_const::<'ADMIN'>();
        starknet::testing::set_caller_address(caller);

        let mut state = Sway::contract_state_for_testing();
        Sway::constructor(ref state, 'Standard Weighted Adalian Yield', 'SWAY', 6, caller);

        Sway::add_grant(ref state, caller, Sway::roles::ADMIN);
        let res = Sway::has_grant(@state, caller, Sway::roles::ADMIN);
        assert(res, 'caller should be minter');

        Sway::revoke_grant(ref state, caller, Sway::roles::ADMIN);
        let res = Sway::has_grant(@state, caller, Sway::roles::ADMIN);
        assert(!res, 'caller should not be minter');
    }

    #[test]
    #[available_gas(1000000)]
    #[should_panic(expected: ('ERC20: must be admin', ))]
    fn test_mint_without_grant() {
        let caller = starknet::contract_address_const::<'ADMIN'>();
        starknet::testing::set_caller_address(caller);

        let mut state = Sway::contract_state_for_testing();
        Sway::constructor(ref state, 'Standard Weighted Adalian Yield', 'SWAY', 6, caller);

        let other = starknet::contract_address_const::<'OTHER'>();
        starknet::testing::set_caller_address(other);

        Sway::mint(ref state, other, (42 * 1000000).into());
    }

    #[test]
    #[available_gas(1000000)]
    fn test_mint() {
        let caller = starknet::contract_address_const::<'ADMIN'>();
        starknet::testing::set_caller_address(caller);

        let mut state = Sway::contract_state_for_testing();
        Sway::constructor(ref state, 'Standard Weighted Adalian Yield', 'SWAY', 6, caller);
        Sway::add_grant(ref state, caller, Sway::roles::ADMIN);

        let amount: u256 = (42 * 1000000).into();
        Sway::mint(ref state, caller, amount);
        let res = Sway::balance_of(@state, caller);
        assert(res == amount, 'caller should have funds');
    }

    #[test]
    #[available_gas(2000000)]
    fn test_transfer() {
        let caller = starknet::contract_address_const::<'ADMIN'>();
        starknet::testing::set_caller_address(caller);

        let mut state = Sway::contract_state_for_testing();
        Sway::constructor(ref state, 'Standard Weighted Adalian Yield', 'SWAY', 6, caller);
        Sway::add_grant(ref state, caller, Sway::roles::ADMIN);

        let amount: u256 = (42 * 1000000).into();
        Sway::mint(ref state, caller, amount);

        let receiver = starknet::contract_address_const::<'RECEIVER'>();
        Sway::transfer(ref state, receiver, amount);
        let res = Sway::balance_of(@state, receiver);
        assert(res == amount, 'receiver should be funded');
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic(expected: ('ERC20: insufficient allowance', ))]
    fn test_transfer_wrong_caller() {
        let caller = starknet::contract_address_const::<'ADMIN'>();
        starknet::testing::set_caller_address(caller);

        let mut state = Sway::contract_state_for_testing();
        Sway::constructor(ref state, 'Standard Weighted Adalian Yield', 'SWAY', 6, caller);
        Sway::add_grant(ref state, caller, Sway::roles::ADMIN);

        let amount: u256 = (42 * 1000000).into();
        Sway::mint(ref state, caller, amount);

        let receiver = starknet::contract_address_const::<'RECEIVER'>();
        let wrong_sender = starknet::contract_address_const::<'WRONG_SENDER'>();
        starknet::testing::set_caller_address(wrong_sender);
        Sway::transfer_from(ref state, caller, receiver, amount);
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic(expected: ('ERC20: insufficient balance', ))]
    fn test_insufficient_funds() {
        let caller = starknet::contract_address_const::<'ADMIN'>();
        starknet::testing::set_caller_address(caller);

        let mut state = Sway::contract_state_for_testing();
        Sway::constructor(ref state, 'Standard Weighted Adalian Yield', 'SWAY', 6, caller);
        Sway::add_grant(ref state, caller, Sway::roles::ADMIN);

        let amount: u256 = (42 * 1000000).into();
        Sway::mint(ref state, caller, amount);

        let receiver = starknet::contract_address_const::<'RECEIVER'>();
        Sway::transfer(ref state, receiver, (50 * 1000000).into());
    }

    #[test]
    #[available_gas(2000000)]
    fn test_send_with_approval() {
        let caller = starknet::contract_address_const::<'ADMIN'>();
        starknet::testing::set_caller_address(caller);
        let other_sender = starknet::contract_address_const::<'OTHER_SENDER'>();

        let mut state = Sway::contract_state_for_testing();
        Sway::constructor(ref state, 'Standard Weighted Adalian Yield', 'SWAY', 6, caller);
        Sway::add_grant(ref state, caller, Sway::roles::ADMIN);

        let amount: u256 = (42 * 1000000).into();
        Sway::mint(ref state, caller, amount);
        Sway::approve(ref state, other_sender, amount);

        starknet::testing::set_caller_address(other_sender);
        let receiver = starknet::contract_address_const::<'RECEIVER'>();
        Sway::transfer_from(ref state, caller, receiver, amount);

        let res = Sway::balance_of(@state, receiver);
        assert(res == amount, 'receiver should be funded');
    }

    #[test]
    #[available_gas(2000000)]
    fn test_transfer_with_confirmation() {
        let caller = starknet::contract_address_const::<'ADMIN'>();
        starknet::testing::set_caller_address(caller);

        let mut state = Sway::contract_state_for_testing();
        Sway::constructor(ref state, 'Standard Weighted Adalian Yield', 'SWAY', 6, caller);
        Sway::add_grant(ref state, caller, Sway::roles::ADMIN);

        let amount: u256 = (42 * 1000000).into();
        Sway::mint(ref state, caller, amount);

        let receiver = starknet::contract_address_const::<'RECEIVER'>();
        let consumer = starknet::contract_address_const::<'CONSUMER'>();
        Sway::transfer_with_confirmation(ref state, receiver, 42 * 1000000, 'memo1', consumer);

        starknet::testing::set_caller_address(consumer);
        Sway::confirm_receipt(ref state, caller, receiver, 42 * 1000000, 'memo1');

        let res = Sway::balance_of(@state, receiver);
        assert(res == amount, 'receiver should be funded');
    }

    #[test]
    #[available_gas(2000000)]
    fn test_transfer_with_confirmation_zero() {
        let caller = starknet::contract_address_const::<'ADMIN'>();
        starknet::testing::set_caller_address(caller);

        let mut state = Sway::contract_state_for_testing();
        Sway::constructor(ref state, 'Standard Weighted Adalian Yield', 'SWAY', 6, caller);
        Sway::add_grant(ref state, caller, Sway::roles::ADMIN);

        let amount: u256 = (0 * 1000000).into();
        Sway::mint(ref state, caller, amount);

        let receiver = starknet::contract_address_const::<'RECEIVER'>();
        let consumer = starknet::contract_address_const::<'CONSUMER'>();
        Sway::transfer_with_confirmation(ref state, receiver, 0 * 1000000, 'memo1', consumer);

        starknet::testing::set_caller_address(consumer);
        Sway::confirm_receipt(ref state, caller, receiver, 0 * 1000000, 'memo1');

        let res = Sway::balance_of(@state, receiver);
        assert(res == amount, 'receiver should be funded');
    }

    #[test]
    #[available_gas(2000000)]
    fn test_bridge_from_l1() {
        let caller = starknet::contract_address_const::<'ADMIN'>();
        starknet::testing::set_caller_address(caller);

        let mut state = Sway::contract_state_for_testing();
        Sway::constructor(ref state, 'Standard Weighted Adalian Yield', 'SWAY', 6, caller);
        Sway::add_grant(ref state, caller, Sway::roles::ADMIN);

        Sway::set_l1_bridge(ref state, 'L1_BRIDGE'.try_into().unwrap());
        Sway::handle_deposit(
            ref state, 'L1_BRIDGE', starknet::contract_address_const::<'PLAYER'>(), 42000, 0, 0x123
        );

        let balance = Sway::balance_of(@state, starknet::contract_address_const::<'PLAYER'>());
        assert(balance == 42000, 'wrong balance');
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic(expected: ('Bridge: from l1 bridge only', ))]
    fn test_bridge_from_l1_fail() {
        let caller = starknet::contract_address_const::<'ADMIN'>();
        starknet::testing::set_caller_address(caller);

        let mut state = Sway::contract_state_for_testing();
        Sway::constructor(ref state, 'Standard Weighted Adalian Yield', 'SWAY', 6, caller);
        Sway::add_grant(ref state, caller, Sway::roles::ADMIN);

        Sway::set_l1_bridge(ref state, 'L1_BRIDGE'.try_into().unwrap());
        Sway::handle_deposit(
            ref state, 'WRONG_L1_BRIDGE', starknet::contract_address_const::<'PLAYER'>(), 42000, 0, 0x123
        );

        let balance = Sway::balance_of(@state, starknet::contract_address_const::<'PLAYER'>());
        assert(balance == 42000, 'wrong balance');
    }


    #[test]
    #[available_gas(2000000)]
    fn test_bridge_withdraw() {
        let caller = starknet::contract_address_const::<'ADMIN'>();
        starknet::testing::set_caller_address(caller);

        let mut state = Sway::contract_state_for_testing();
        Sway::constructor(ref state, 'Standard Weighted Adalian Yield', 'SWAY', 6, caller);
        Sway::add_grant(ref state, caller, Sway::roles::ADMIN);
        Sway::add_grant(ref state, caller, Sway::roles::ADMIN);
        Sway::mint(ref state, starknet::contract_address_const::<'PLAYER'>(), 42000.into());

        Sway::set_l1_bridge(ref state, 'L1_BRIDGE'.try_into().unwrap());

        starknet::testing::set_caller_address(starknet::contract_address_const::<'PLAYER'>());
        Sway::initiate_withdrawal(ref state, 'L1_ACCOUNT'.try_into().unwrap(), 21000.into());

        let balance = Sway::balance_of(@state, starknet::contract_address_const::<'PLAYER'>());
        assert(balance == 21000, 'wrong balance');
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic(expected: ('SWAY: memo cannot be zero', ))]
    fn test_transfer_with_confirmation_zero_memo() {
        let caller = starknet::contract_address_const::<'ADMIN'>();
        starknet::testing::set_caller_address(caller);

        let mut state = Sway::contract_state_for_testing();
        Sway::constructor(ref state, 'Standard Weighted Adalian Yield', 'SWAY', 6, caller);
        Sway::add_grant(ref state, caller, Sway::roles::ADMIN);

        let amount: u256 = (42 * 1000000).into();
        Sway::mint(ref state, caller, amount);

        let receiver = starknet::contract_address_const::<'RECEIVER'>();
        let consumer = starknet::contract_address_const::<'CONSUMER'>();
        Sway::transfer_with_confirmation(ref state, receiver, 42 * 1000000, 0, consumer);
    }
}
