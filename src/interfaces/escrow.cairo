use starknet::ContractAddress;

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

#[starknet::interface]
trait IEscrow<TContractState> {
    fn balance_of(self: @TContractState, order_id: felt252) -> u256;
    fn deposit(
        ref self: TContractState, token: ContractAddress, amount: u256, withdraw_hook: Hook, deposit_hook: Hook
    ) -> felt252;
    fn withdraw(
        ref self: TContractState,
        original_caller: ContractAddress,
        token: ContractAddress,
        withdraw_hook: Hook,
        withdraw_calldata: Array<felt252>,
        withdrawals: Span<Withdrawal>
    );
    fn start_force_withdraw(
        ref self: TContractState,
        token: ContractAddress,
        withdraw_hook: Hook
    );
    fn finish_force_withdraw(
        ref self: TContractState,
        token: ContractAddress,
        withdraw_hook: Hook
    );
}
