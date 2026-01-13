const IERC165_ID: felt252 = 0x01ffc9a7;
const INVALID_ID: felt252 = 0xffffffff;

const IACCOUNT_ID: felt252 = 0xa66bd575;
const IERC721_ID: felt252 = 0x80ac58cd;
const IERC721_METADATA_ID: felt252 = 0x5b5e139f;
const IERC721_RECEIVER_ID: felt252 = 0x150b7a02;

#[starknet::interface]
trait IERC165<TContractState> {
    fn supports_interface(self: @TContractState, interface_id: felt252) -> bool;
    fn supportsInterface(self: @TContractState, interface_id: felt252) -> bool;
}
