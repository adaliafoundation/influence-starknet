use starknet::ContractAddress;

#[starknet::interface]
trait IERC721<TContractState> {
    fn approve(ref self: TContractState, to: ContractAddress, token_id: u256);
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
    fn balanceOf(self: @TContractState, account: ContractAddress) -> u256;
    fn get_approved(self: @TContractState, token_id: u256) -> ContractAddress;
    fn getApproved(self: @TContractState, token_id: u256) -> ContractAddress;
    fn exists(self: @TContractState, token_id: u256) -> bool;
    fn is_approved_for_all(self: @TContractState, owner: ContractAddress, operator: ContractAddress) -> bool;
    fn isApprovedForAll(self: @TContractState, owner: ContractAddress, operator: ContractAddress) -> bool;
    fn name(self: @TContractState) -> felt252;
    fn owner_of(self: @TContractState,token_id: u256) -> ContractAddress;
    fn ownerOf(self: @TContractState,token_id: u256) -> ContractAddress;
    fn symbol(self: @TContractState) -> felt252;
    fn safe_transfer_from(
        ref self: TContractState, from: ContractAddress, to: ContractAddress, token_id: u256, data: Span<felt252>
    );
    fn safeTransferFrom(
        ref self: TContractState, from: ContractAddress, to: ContractAddress, token_id: u256, data: Span<felt252>
    );
    fn set_approval_for_all(ref self: TContractState, operator: ContractAddress, approved: bool);
    fn setApprovalForAll(ref self: TContractState, operator: ContractAddress, approved: bool);
    fn token_uri(self: @TContractState, token_id: u256) -> Span<felt252>;
    fn tokenUri(self: @TContractState, token_id: u256) -> Span<felt252>;
    fn transfer_from(ref self: TContractState, from: ContractAddress, to: ContractAddress, token_id: u256);
    fn transferFrom(ref self: TContractState, from: ContractAddress, to: ContractAddress, token_id: u256);
}

#[starknet::interface]
trait IERC721Receiver<TContractState> {
    fn on_erc721_received(
        self: @TContractState, operator: ContractAddress, from: ContractAddress, token_id: u256, data: Span<felt252>
    ) -> felt252;
}

