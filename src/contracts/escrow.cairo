use array::ArrayTrait;
use starknet::ContractAddress;

trait ArrayTraitExt<T> {
    fn append_all(ref self: Array<T>, ref arr: Array<T>);
}

impl ArrayExtImpl<T, impl TCopy: Copy<T>, impl TDrop: Drop<T>> of ArrayTraitExt<T> {
    fn append_all(ref self: Array<T>, ref arr: Array<T>) {
        match arr.pop_front() {
            Option::Some(v) => {
                self.append(v);
                self.append_all(ref arr);
            },
            Option::None(()) => (),
        }
    }
}

#[starknet::interface]
trait IERC20<TContractState> {
    fn balanceOf(ref self: TContractState, owner: ContractAddress) -> u256;
    fn mint(ref self: TContractState, recipient: ContractAddress, amount: u256);
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256);
    fn transferFrom(ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256);
}

#[derive(Copy, Drop, Serde)]
struct Hook {
    contract: ContractAddress,
    entry_point_selector: felt252,
    calldata: Span<felt252>
}

#[derive(Copy, Drop, Serde)]
struct Withdrawal {
    recipient: ContractAddress,
    amount: u256
}

// A fully immutable contract that allows users to set an approving contract for their escrowed tokens
#[starknet::contract]
mod Escrow {
    use array::{ArrayTrait, SpanTrait};
    use clone::Clone;
    use option::OptionTrait;
    use starknet::{ContractAddress, call_contract_syscall, replace_class_syscall, ClassHash};
    use traits::{Into, TryInto};
    use zeroable::Zeroable;

    use super::{ArrayTraitExt, Hook, IERC20Dispatcher, IERC20DispatcherTrait, Withdrawal};

    mod hook_type {
        const DEPOSIT: u64 = 1;
        const WITHDRAW: u64 = 2;
    }

    trait HookTrait {
        fn is_non_zero(self: Hook) -> bool;
    }

    impl HookImpl of HookTrait {
        fn is_non_zero(self: Hook) -> bool {
            return self.contract.is_non_zero() && self.entry_point_selector.is_non_zero();
        }
    }

    #[storage]
    struct Storage {
        balances: LegacyMap::<felt252, u256>,
        forced_withdrawal: LegacyMap::<felt252, u64>,
        reentrancy_guard: bool
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Deposited: Deposited,
        Withdrawn: Withdrawn,
        ForcedWithdrawStarted: ForcedWithdrawStarted,
        ForcedWithdrawFinished: ForcedWithdrawFinished
    }

    #[derive(Drop, starknet::Event)]
    struct Deposited {
        order_id: felt252,
        caller: ContractAddress,
        token: ContractAddress,
        amount: u256,
        deposit_hook: Hook,
        withdraw_hook: Hook
    }

    #[derive(Drop, starknet::Event)]
    struct Withdrawn {
        order_id: felt252,
        caller: ContractAddress,
        withdrawals: Span<Withdrawal>,
        withdraw_hook: Hook
    }

    #[derive(Drop, starknet::Event)]
    struct ForcedWithdrawStarted {
        order_id: felt252,
        caller: ContractAddress,
        finish_time: u64
    }

    #[derive(Drop, starknet::Event)]
    struct ForcedWithdrawFinished {
        order_id: felt252,
        caller: ContractAddress
    }

    #[external(v0)]
    fn balance_of(self: @ContractState, order_id: felt252) -> u256 {
        return self.balances.read(order_id);
    }

    #[external(v0)]
    fn deposit(
        ref self: ContractState,
        token: ContractAddress,
        amount: u256,
        withdraw_hook: Hook,
        deposit_hook: Hook, // optional hook to call when the deposit is received (pass 0, 0, 0 for no hook)
    ) -> felt252 {
        assert(!self.reentrancy_guard.read(), 'reentrancy guard');
        self.reentrancy_guard.write(true);

        let caller = starknet::get_caller_address();

        // Make sure a withdraw hook has been set
        assert(withdraw_hook.is_non_zero(), 'no withdraw hook');

        // Notify the validator contract (if needed)
        if deposit_hook.is_non_zero() {
            let mut calldata: Array<felt252> = deposit_hook.calldata.snapshot.clone();
            calldata.append(caller.into());
            calldata.append(hook_type::DEPOSIT.into());
            calldata.append(token.into());
            serde::Serde::<u256>::serialize(@amount, ref calldata);
            call_contract_syscall(deposit_hook.contract, deposit_hook.entry_point_selector, calldata.span())
                .unwrap_syscall();
        }

        // Transfer tokens from the caller to the escrow contract (must be pre-approved)
        let escrow_contract = starknet::get_contract_address();
        IERC20Dispatcher { contract_address: token }.transferFrom(caller, escrow_contract, amount);

        // Record the order
        let order_id = get_order_id(caller, token, withdraw_hook);
        self.balances.write(order_id, self.balances.read(order_id) + amount);

        self.emit(Deposited {
            order_id: order_id,
            caller: caller,
            token: token,
            amount: amount,
            deposit_hook: deposit_hook,
            withdraw_hook: withdraw_hook
        });

        self.reentrancy_guard.write(false);
        return order_id;
    }

    // Withdraws tokens from the escrow contract and sends them to the recipients
    #[external(v0)]
    fn withdraw(
        ref self: ContractState,
        original_caller: ContractAddress,
        token: ContractAddress,
        withdraw_hook: Hook,
        mut withdraw_calldata: Array<felt252>, // additional calldata to pass to withdraw hook
        withdrawals: Span<Withdrawal>
    ) {
        assert(!self.reentrancy_guard.read(), 'reentrancy guard');
        self.reentrancy_guard.write(true);

        let caller = starknet::get_caller_address();
        let order_id = get_order_id(original_caller, token, withdraw_hook);

        // Check that the order is not locked for forced withdrawal
        assert(self.forced_withdrawal.read(order_id).is_zero(), 'locked for forced withdrawal');

        // Transfer tokens to each recipient
        let escrow_contract = starknet::get_contract_address();
        let erc20 = IERC20Dispatcher { contract_address: token };

        let mut iter = 0;
        let mut total_amount = 0;

        loop {
            if iter >= withdrawals.len() { break; }

            let amount = *withdrawals.at(iter).amount;
            total_amount += amount;
            erc20.transfer(*withdrawals.at(iter).recipient, amount);

            iter += 1;
        };

        // Ensure there's enough balance in the order to cover the withdrawals
        assert(self.balances.read(order_id) >= total_amount, 'insufficient balance');

        // Call the withdraw hook (will assert if the hook fails to validate withdraw)
        let mut calldata: Array<felt252> = withdraw_hook.calldata.snapshot.clone();
        calldata.append_all(ref withdraw_calldata);
        calldata.append(caller.into());
        calldata.append(hook_type::WITHDRAW.into());
        calldata.append(token.into());
        serde::Serde::<Span<Withdrawal>>::serialize(@withdrawals, ref calldata);
        call_contract_syscall(withdraw_hook.contract, withdraw_hook.entry_point_selector, calldata.span())
            .unwrap_syscall();

        // Update the balance
        self.balances.write(order_id, self.balances.read(order_id) - total_amount);

        self.reentrancy_guard.write(false);
        self.emit(Withdrawn {
            order_id: order_id,
            caller: caller,
            withdrawals: withdrawals,
            withdraw_hook: withdraw_hook
        });
    }

    #[external(v0)]
    fn start_force_withdraw(
        ref self: ContractState,
        token: ContractAddress,
        withdraw_hook: Hook
    ) {
        let caller = starknet::get_caller_address();
        let order_id = get_order_id(caller, token, withdraw_hook); // ensures only caller can withdraw

        // Check that the order is not already locked for forced withdrawal
        assert(self.balances.read(order_id).is_non_zero(), 'insufficient balance');
        assert(self.forced_withdrawal.read(order_id).is_zero(), 'locked for forced withdrawal');

        // Lock the order for forced withdrawal
        let finish_time = starknet::get_block_timestamp() + 604800; // 7 days
        self.forced_withdrawal.write(order_id, finish_time); // 7 days

        self.emit(ForcedWithdrawStarted {
            order_id: order_id,
            caller: caller,
            finish_time: finish_time
        });
    }

    #[external(v0)]
    fn finish_force_withdraw(
        ref self: ContractState,
        token: ContractAddress,
        withdraw_hook: Hook
    ) {
        assert(!self.reentrancy_guard.read(), 'reentrancy guard');
        self.reentrancy_guard.write(true);

        let caller = starknet::get_caller_address();
        let order_id = get_order_id(caller, token, withdraw_hook); // ensures only caller can withdraw

        // Check that the order is locked for forced withdrawal
        assert(self.forced_withdrawal.read(order_id).is_non_zero(), 'forced withdrawal not started');

        // Check that the order is ready for forced withdrawal
        let now = starknet::get_block_timestamp();
        assert(now >= self.forced_withdrawal.read(order_id), 'forced withdrawal not ready');

        // Send the tokens to the original caller
        let amount = self.balances.read(order_id);
        let escrow_contract = starknet::get_contract_address();
        IERC20Dispatcher { contract_address: token }.transfer(caller, amount);

        // Update the balance
        self.balances.write(order_id, 0);

        self.reentrancy_guard.write(false);
        self.emit(ForcedWithdrawFinished {
            order_id: order_id,
            caller: caller
        });
    }

    // Calculate identifier hash
    fn get_order_id(caller: ContractAddress, token: ContractAddress, withdraw_hook: Hook) -> felt252 {
        let mut to_hash: Array<felt252> = Default::default();
        serde::Serde::<ContractAddress>::serialize(@caller.into(), ref to_hash);
        serde::Serde::<ContractAddress>::serialize(@token.into(), ref to_hash);
        serde::Serde::<Hook>::serialize(@withdraw_hook, ref to_hash);
        return poseidon::poseidon_hash_span(to_hash.span());
    }
}

// Tests --------------------------------------------------------------------------------------------------------------

// Mock ERC20
#[starknet::contract]
mod ERC20 {
    use starknet::ContractAddress;

    #[storage]
    struct Storage {
        balances: LegacyMap::<ContractAddress, u256>
    }

    #[external(v0)]
    fn balanceOf(ref self: ContractState, owner: ContractAddress) -> u256 {
        return self.balances.read(owner);
    }

    #[external(v0)]
    fn mint(ref self: ContractState, recipient: ContractAddress, amount: u256) {
        self.balances.write(recipient, self.balances.read(recipient) + amount);
    }

    #[external(v0)]
    fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) {
        let sender = starknet::get_caller_address();
        self.balances.write(sender, self.balances.read(sender) - amount);
        self.balances.write(recipient, self.balances.read(recipient) + amount);
    }

    #[external(v0)]
    fn transferFrom(ref self: ContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256) {
        assert(self.balances.read(sender) >= amount, 'insufficient balance');
        self.balances.write(sender, self.balances.read(sender) - amount);
        self.balances.write(recipient, self.balances.read(recipient) + amount);
    }
}

// Mock validator contract
#[starknet::contract]
mod Validator {
    use starknet::ContractAddress;

    use super::Withdrawal;

    #[storage]
    struct Storage {}

    // 0x46162993b8bb024f7e7e2204ca530ac20e65f2a52fe47c806c5177d75a0185
    #[external(v0)]
    fn validate_deposit(
        ref self: ContractState,
        should_pass: bool,
        caller: ContractAddress,
        hook_type: u64,
        token: ContractAddress,
        amount: u256
    ) {
        assert(should_pass, 'deposit invalid');
    }

    // 0xd94b48d0227e86a3172c3fd817380031a21337ef04aab05a50276afb99b8c9
    #[external(v0)]
    fn validate_withdraw(
        ref self: ContractState,
        should_pass: bool,
        caller: ContractAddress,
        hook_type: u64,
        token: ContractAddress,
        withdrawals: Span<Withdrawal>
    ) {
        assert(should_pass, 'withdraw invalid');
    }
}

#[cfg(test)]
mod tests {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use starknet::{ClassHash, ContractAddress, deploy_syscall};
    use result::ResultTrait;
    use traits::{Into, TryInto};

    use super::{Escrow, ERC20, Hook, IERC20Dispatcher, IERC20DispatcherTrait, Validator, Withdrawal};

    fn default_setup() -> (ContractAddress, ContractAddress, Hook, Hook) {
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DEPLOYER'>());
        let constructor_data: Array<felt252> = Default::default();

        // Deploy mock erc20
        let (erc20_address, _) = deploy_syscall(
            ERC20::TEST_CLASS_HASH.try_into().unwrap(), 0, constructor_data.span(), false
        ).unwrap();

        let erc20 = IERC20Dispatcher { contract_address: erc20_address };

        // Deploy mock validator
        let (validator_address, _) = deploy_syscall(
            Validator::TEST_CLASS_HASH.try_into().unwrap(), 0, constructor_data.span(), false
        ).unwrap();

        // Setup hooks
        let mut calldata: Array<felt252> = Default::default();
        calldata.append(1);

        let withdraw_hook = Hook {
            contract: validator_address,
            entry_point_selector: 0xd94b48d0227e86a3172c3fd817380031a21337ef04aab05a50276afb99b8c9,
            calldata: calldata.span()
        };

        let deposit_hook = Hook {
            contract: validator_address,
            entry_point_selector: 0x46162993b8bb024f7e7e2204ca530ac20e65f2a52fe47c806c5177d75a0185,
            calldata: calldata.span()
        };

        return (erc20_address, validator_address, withdraw_hook, deposit_hook);
    }

    #[test]
    #[available_gas(5000000)]
    fn test_deposit_withdraw_force() {
        let (erc20_address, _, withdraw_hook, deposit_hook) = default_setup();
        let erc20 = IERC20Dispatcher { contract_address: erc20_address };

        // Test the deposit
        let depositor = starknet::contract_address_const::<'DEPOSITOR'>();
        erc20.mint(depositor, 100);
        starknet::testing::set_caller_address(depositor);
        let mut state = Escrow::contract_state_for_testing();
        let order_id = Escrow::deposit(ref state, erc20_address, 100, withdraw_hook, deposit_hook);
        assert(Escrow::balance_of(@state, order_id) == 100, 'wrong balance');

        // Test a withdraw
        let withdrawer = starknet::contract_address_const::<'WITHDRAWER'>();
        let recipient2 = starknet::contract_address_const::<'RECIPIENT2'>();
        starknet::testing::set_caller_address(withdrawer);
        let mut withdrawals: Array<Withdrawal> = Default::default();
        withdrawals.append(Withdrawal { recipient: withdrawer, amount: 40 });
        withdrawals.append(Withdrawal { recipient: recipient2, amount: 20 });
        let extra_calldata: Array<felt252> = Default::default();
        Escrow::withdraw(ref state, depositor, erc20_address, withdraw_hook, extra_calldata, withdrawals.span());

        assert(Escrow::balance_of(@state, order_id) == 40, 'wrong balance');
        assert(erc20.balanceOf(withdrawer) == 40, 'wrong balance');
        assert(erc20.balanceOf(recipient2) == 20, 'wrong balance');

        // Test force withdraw
        starknet::testing::set_caller_address(depositor);
        starknet::testing::set_block_timestamp(1);
        Escrow::start_force_withdraw(ref state, erc20_address, withdraw_hook);
        starknet::testing::set_block_timestamp(604801);
        Escrow::finish_force_withdraw(ref state, erc20_address, withdraw_hook);
        assert(Escrow::balance_of(@state, order_id) == 0, 'wrong balance');
        assert(erc20.balanceOf(depositor) == 40, 'wrong balance');
    }

    #[test]
    #[available_gas(5000000)]
    #[should_panic(expected: ('insufficient balance', 'ENTRYPOINT_FAILED'))]
    fn test_insufficient_deposit() {
        let (erc20_address, _, withdraw_hook, deposit_hook) = default_setup();

        // Test the deposit
        let depositor = starknet::contract_address_const::<'DEPOSITOR'>();
        let mut state = Escrow::contract_state_for_testing();
        Escrow::deposit(ref state, erc20_address, 100, withdraw_hook, deposit_hook);
    }

    #[test]
    #[available_gas(5000000)]
    #[should_panic(expected: ('no withdraw hook', ))]
    fn test_no_withdraw_hook() {
        let (erc20_address, _, _, deposit_hook) = default_setup();

        let withdraw_hook = Hook {
            contract: starknet::contract_address_const::<0>(),
            entry_point_selector: 0,
            calldata: Default::default().span()
        };

        // Test the deposit
        let depositor = starknet::contract_address_const::<'DEPOSITOR'>();
        let mut state = Escrow::contract_state_for_testing();
        Escrow::deposit(ref state, erc20_address, 100, withdraw_hook, deposit_hook);
    }

    #[test]
    #[available_gas(5000000)]
    #[should_panic(expected: ('deposit invalid', 'ENTRYPOINT_FAILED'))]
    fn test_deposit_validate_fail() {
        let (erc20_address, validator_address, withdraw_hook, _) = default_setup();

        let mut calldata: Array<felt252> = Default::default();
        calldata.append(0); // will cause a validation failure
        let deposit_hook = Hook {
            contract: validator_address,
            entry_point_selector: 0x46162993b8bb024f7e7e2204ca530ac20e65f2a52fe47c806c5177d75a0185,
            calldata: calldata.span()
        };

        // Test the deposit
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DEPLOYER'>());
        let depositor = starknet::contract_address_const::<'DEPOSITOR'>();
        let mut state = Escrow::contract_state_for_testing();
        Escrow::deposit(ref state, erc20_address, 100, withdraw_hook, deposit_hook);
    }

    #[test]
    #[available_gas(5000000)]
    #[should_panic(expected: ('withdraw invalid', 'ENTRYPOINT_FAILED'))]
    fn test_withdraw_validate_fail() {
        let (erc20_address, validator_address, _, deposit_hook) = default_setup();
        let erc20 = IERC20Dispatcher { contract_address: erc20_address };

        let mut calldata: Array<felt252> = Default::default();
        calldata.append(0); // will cause a validation failure
        let withdraw_hook = Hook {
            contract: validator_address,
            entry_point_selector: 0xd94b48d0227e86a3172c3fd817380031a21337ef04aab05a50276afb99b8c9,
            calldata: calldata.span()
        };

        let depositor = starknet::contract_address_const::<'DEPOSITOR'>();
        erc20.mint(depositor, 100);
        starknet::testing::set_caller_address(depositor);
        let mut state = Escrow::contract_state_for_testing();
        Escrow::deposit(ref state, erc20_address, 100, withdraw_hook, deposit_hook);

        // Test the withdraw
        let withdrawer = starknet::contract_address_const::<'WITHDRAWER'>();
        starknet::testing::set_caller_address(withdrawer);
        let mut withdrawals: Array<Withdrawal> = Default::default();
        withdrawals.append(Withdrawal { recipient: withdrawer, amount: 60 });
        let extra_calldata: Array<felt252> = Default::default();
        Escrow::withdraw(ref state, depositor, erc20_address, withdraw_hook, extra_calldata, withdrawals.span());
    }

    #[test]
    #[available_gas(5000000)]
    #[should_panic(expected: ('CONTRACT_NOT_DEPLOYED', ))]
    fn test_validate_contract_no_exist() {
        let (erc20_address, _, withdraw_hook, mut deposit_hook) = default_setup();
        let erc20 = IERC20Dispatcher { contract_address: erc20_address };

        deposit_hook.contract = starknet::contract_address_const::<42>(); // incorrect / undeployed address

        let depositor = starknet::contract_address_const::<'DEPOSITOR'>();
        erc20.mint(depositor, 100);
        starknet::testing::set_caller_address(depositor);
        let mut state = Escrow::contract_state_for_testing();
        Escrow::deposit(ref state, erc20_address, 100, withdraw_hook, deposit_hook);
    }

    #[test]
    #[available_gas(5000000)]
    #[should_panic(expected: ('insufficient balance', ))]
    fn test_insufficient_withdraw() {
        let (erc20_address, _, withdraw_hook, deposit_hook) = default_setup();
        let erc20 = IERC20Dispatcher { contract_address: erc20_address };

        let depositor = starknet::contract_address_const::<'DEPOSITOR'>();
        erc20.mint(depositor, 100);
        starknet::testing::set_caller_address(depositor);
        let mut state = Escrow::contract_state_for_testing();
        Escrow::deposit(ref state, erc20_address, 100, withdraw_hook, deposit_hook);

        // Add extra funds to ensure that withdraw fails due to the order's balance rather than the escrow
        // contract's erc20 balance
        let depositor2 = starknet::contract_address_const::<'DEPOSITOR2'>();
        erc20.mint(depositor2, 100);
        starknet::testing::set_caller_address(depositor2);
        Escrow::deposit(ref state, erc20_address, 100, withdraw_hook, deposit_hook);

        // Test a withdraw
        let withdrawer = starknet::contract_address_const::<'WITHDRAWER'>();
        starknet::testing::set_caller_address(withdrawer);
        let mut withdrawals: Array<Withdrawal> = Default::default();
        withdrawals.append(Withdrawal { recipient: withdrawer, amount: 101 });
        let extra_calldata: Array<felt252> = Default::default();
        Escrow::withdraw(ref state, depositor, erc20_address, withdraw_hook, extra_calldata, withdrawals.span());
    }

    #[test]
    #[available_gas(5000000)]
    fn test_force_withdraw_with_bad_hook() {
        let (erc20_address, validator_address, _, deposit_hook) = default_setup();
        let erc20 = IERC20Dispatcher { contract_address: erc20_address };

        let mut calldata: Array<felt252> = Default::default();
        calldata.append(0); // will cause a validation failure
        let withdraw_hook = Hook {
            contract: validator_address,
            entry_point_selector: 0xd94b48d0227e86a3172c3fd817380031a21337ef04aab05a50276afb99b8c9,
            calldata: calldata.span()
        };

        let depositor = starknet::contract_address_const::<'DEPOSITOR'>();
        erc20.mint(depositor, 100);
        starknet::testing::set_caller_address(depositor);
        let mut state = Escrow::contract_state_for_testing();
        let order_id = Escrow::deposit(ref state, erc20_address, 100, withdraw_hook, deposit_hook);

        // Test force withdraw
        starknet::testing::set_caller_address(depositor);
        starknet::testing::set_block_timestamp(1);
        Escrow::start_force_withdraw(ref state, erc20_address, withdraw_hook);
        starknet::testing::set_block_timestamp(604801);
        Escrow::finish_force_withdraw(ref state, erc20_address, withdraw_hook);
        assert(Escrow::balance_of(@state, order_id) == 0, 'wrong balance');
        assert(erc20.balanceOf(depositor) == 100, 'wrong balance');
    }

    #[test]
    #[available_gas(5000000)]
    #[should_panic(expected: ('insufficient balance', ))]
    fn test_force_withdraw_insufficient() {
        let (erc20_address, _, withdraw_hook, deposit_hook) = default_setup();
        let erc20 = IERC20Dispatcher { contract_address: erc20_address };

        let depositor = starknet::contract_address_const::<'DEPOSITOR'>();
        erc20.mint(depositor, 100);
        starknet::testing::set_caller_address(depositor);
        let mut state = Escrow::contract_state_for_testing();
        Escrow::deposit(ref state, erc20_address, 100, withdraw_hook, deposit_hook);

        let withdrawer = starknet::contract_address_const::<'WITHDRAWER'>();
        starknet::testing::set_caller_address(withdrawer);
        let mut withdrawals: Array<Withdrawal> = Default::default();
        withdrawals.append(Withdrawal { recipient: withdrawer, amount: 100 });
        let extra_calldata: Array<felt252> = Default::default();
        Escrow::withdraw(ref state, depositor, erc20_address, withdraw_hook, extra_calldata, withdrawals.span());

        // Test force withdraw
        starknet::testing::set_caller_address(depositor);
        Escrow::start_force_withdraw(ref state, erc20_address, withdraw_hook);
    }

    #[test]
    #[available_gas(5000000)]
    #[should_panic(expected: ('insufficient balance', ))]
    fn test_force_withdraw_wrong_caller() {
        let (erc20_address, _, withdraw_hook, deposit_hook) = default_setup();
        let erc20 = IERC20Dispatcher { contract_address: erc20_address };

        let depositor = starknet::contract_address_const::<'DEPOSITOR'>();
        erc20.mint(depositor, 100);
        starknet::testing::set_caller_address(depositor);
        let mut state = Escrow::contract_state_for_testing();
        Escrow::deposit(ref state, erc20_address, 100, withdraw_hook, deposit_hook);

        // Test force withdraw
        starknet::testing::set_caller_address(starknet::contract_address_const::<'WRONG_CALLER'>());
        Escrow::start_force_withdraw(ref state, erc20_address, withdraw_hook);
    }

    #[test]
    #[available_gas(5000000)]
    #[should_panic(expected: ('forced withdrawal not started', ))]
    fn test_finish_force_withdraw_fail() {
        let (erc20_address, _, withdraw_hook, deposit_hook) = default_setup();
        let erc20 = IERC20Dispatcher { contract_address: erc20_address };

        let depositor = starknet::contract_address_const::<'DEPOSITOR'>();
        erc20.mint(depositor, 100);
        starknet::testing::set_caller_address(depositor);
        let mut state = Escrow::contract_state_for_testing();
        Escrow::deposit(ref state, erc20_address, 100, withdraw_hook, deposit_hook);

        // Test force withdraw
        starknet::testing::set_caller_address(depositor);
        Escrow::finish_force_withdraw(ref state, erc20_address, withdraw_hook);
    }

    #[test]
    #[available_gas(5000000)]
    #[should_panic(expected: ('locked for forced withdrawal', ))]
    fn test_withdraw_fail_after_force_started() {
        let (erc20_address, _, withdraw_hook, deposit_hook) = default_setup();
        let erc20 = IERC20Dispatcher { contract_address: erc20_address };

        let depositor = starknet::contract_address_const::<'DEPOSITOR'>();
        erc20.mint(depositor, 100);
        starknet::testing::set_caller_address(depositor);
        let mut state = Escrow::contract_state_for_testing();
        Escrow::deposit(ref state, erc20_address, 100, withdraw_hook, deposit_hook);

        // Test force withdraw
        starknet::testing::set_caller_address(depositor);
        Escrow::start_force_withdraw(ref state, erc20_address, withdraw_hook);

        // Test a withdraw
        let withdrawer = starknet::contract_address_const::<'WITHDRAWER'>();
        starknet::testing::set_caller_address(withdrawer);
        let mut withdrawals: Array<Withdrawal> = Default::default();
        withdrawals.append(Withdrawal { recipient: withdrawer, amount: 40 });
        let extra_calldata: Array<felt252> = Default::default();
        Escrow::withdraw(ref state, depositor, erc20_address, withdraw_hook, extra_calldata, withdrawals.span());
    }
}
