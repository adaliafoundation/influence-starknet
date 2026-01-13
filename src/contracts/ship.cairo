use starknet::{ContractAddress, EthAddress};

#[starknet::interface]
trait IShip<TContractState> {
    fn add_grant(ref self: TContractState, account: ContractAddress, role: u64);
    fn has_grant(self: @TContractState, account: ContractAddress, role: u64) -> bool;
    fn revoke_grant(ref self: TContractState, account: ContractAddress, role: u64);

    fn current_token(self: @TContractState) -> u256;
    fn mint_with_auto_id(ref self: TContractState, to: ContractAddress) -> u256;
    fn get_l1_bridge_address(self: @TContractState) -> EthAddress;
    fn set_l1_bridge_address(ref self: TContractState, address: EthAddress);
    fn bridge_to_l1(ref self: TContractState, to_address: EthAddress, token_ids: Array<u128>);

    // On-contract sell order book
    fn set_sway_address(ref self: TContractState, address: ContractAddress);
    fn get_sell_order(self: @TContractState, token_id: u256) -> u128;
    fn set_sell_order(ref self: TContractState, token_id: u256, price: u128);
    fn fill_sell_order(ref self: TContractState, token_id: u256);

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

#[starknet::contract]
mod Ship {
    use array::{ArrayTrait, SpanTrait};
    use option::{OptionTrait};
    use starknet::{ClassHash, ContractAddress, get_caller_address};
    use starknet::eth_address::{EthAddress};
    use starknet::info::{get_contract_address};
    use starknet::syscalls::{send_message_to_l1_syscall, replace_class_syscall};
    use traits::{Into, TryInto};
    use zeroable::{Zeroable};

    use influence::contracts::sway::{ISwayDispatcher, ISwayDispatcherTrait};
    use influence::interfaces::erc165::{
        IERC165Dispatcher, IERC165DispatcherTrait, IACCOUNT_ID, IERC165_ID, IERC721_ID, IERC721_METADATA_ID,
        IERC721_RECEIVER_ID
    };
    use influence::interfaces::erc721::{IERC721ReceiverDispatcher, IERC721ReceiverDispatcherTrait};
    use influence::types::{ArrayHashTrait, StoreArray, stringify_u256};

    mod roles {
        const ADMIN: u64 = 1;
        const MINTER: u64 = 2;
    }

    #[storage]
    struct Storage {
        _name: felt252,
        _symbol: felt252,
        _token_uri: LegacyMap::<u256, felt252>,
        balances: LegacyMap::<ContractAddress, u256>,
        base_uri: Array<felt252>,
        l1_bridge_address: EthAddress,
        operator_approvals: LegacyMap::<(ContractAddress, ContractAddress), bool>,
        owners: LegacyMap::<u256, ContractAddress>,
        role_grants: LegacyMap::<(ContractAddress, u64), bool>,
        sell_orders: LegacyMap::<u256, u128>,
        sway_address: ContractAddress,
        token_approvals: LegacyMap::<u256, ContractAddress>,
        token_tracker: u256
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Approval: Approval,
        ApprovalForAll: ApprovalForAll,
        BridgedFromL1: BridgedFromL1,
        BridgedToL1: BridgedToL1,
        Transfer: Transfer,
        SellOrderSet: SellOrderSet,
        SellOrderFilled: SellOrderFilled
    }

    #[derive(Drop, starknet::Event)]
    struct Approval {
        owner: ContractAddress,
        approved: ContractAddress,
        token_id: u256
    }

    #[derive(Drop, starknet::Event)]
    struct ApprovalForAll {
        owner: ContractAddress,
        operator: ContractAddress,
        approved: bool
    }

    #[derive(Drop, starknet::Event)]
    struct BridgedFromL1 {
        token_id: u256,
        to_address: ContractAddress
    }

    #[derive(Drop, starknet::Event)]
    struct BridgedToL1 {
        token_id: u256,
        from_address: ContractAddress,
        to_address: EthAddress
    }

    #[derive(Drop, starknet::Event)]
    struct Transfer {
        from: ContractAddress,
        to: ContractAddress,
        token_id: u256
    }

    #[derive(Drop, starknet::Event)]
    struct SellOrderSet {
        token_id: u256,
        price: u128
    }

    #[derive(Drop, starknet::Event)]
    struct SellOrderFilled {
        token_id: u256,
        price: u128
    }

    #[constructor]
    fn constructor(ref self: ContractState, name: felt252, symbol: felt252, admin: ContractAddress) {
        self._name.write(name);
        self._symbol.write(symbol);
        self.token_tracker.write(1);
        self.role_grants.write((admin, roles::ADMIN), true);
    }

    #[external(v0)]
    fn upgrade(ref self: ContractState, class_hash: ClassHash) {
        assert(self.role_grants.read((get_caller_address(), roles::ADMIN)), 'ERC721: must be admin');
        replace_class_syscall(class_hash);
    }

    #[external(v0)]
    fn current_token(self: @ContractState) -> u256 {
        return self.token_tracker.read();
    }

    #[external(v0)]
    fn mint_with_auto_id(ref self: ContractState, to: ContractAddress) -> u256 {
        assert(self.role_grants.read((get_caller_address(), roles::MINTER)), 'ERC721: must be minter');
        let token_id = current_token(@self);
        _mint(ref self, to, token_id);
        self.token_tracker.write(self.token_tracker.read() + 1);
        return token_id;
    }

    // Permissions ----------------------------------------------------------------------------------------------------

    #[external(v0)]
    fn add_grant(ref self: ContractState, account: ContractAddress, role: u64) {
        assert(self.role_grants.read((get_caller_address(), roles::ADMIN)), 'ERC721: must be admin');
        self.role_grants.write((account, role), true);
    }

    #[external(v0)]
    fn has_grant(self: @ContractState, account: ContractAddress, role: u64) -> bool {
        return self.role_grants.read((account, role));
    }

    #[external(v0)]
    fn revoke_grant(ref self: ContractState, account: ContractAddress, role: u64) {
        assert(self.role_grants.read((get_caller_address(), roles::ADMIN)), 'ERC721: must be admin');
        self.role_grants.write((account, role), false);
    }

    // On-contract sell order book ------------------------------------------------------------------------------------

    #[external(v0)]
    fn set_sway_address(ref self: ContractState, address: ContractAddress) {
        assert(self.role_grants.read((get_caller_address(), roles::ADMIN)), 'ERC721: must be admin');
        self.sway_address.write(address);
    }

    #[external(v0)]
    fn get_sell_order(self: @ContractState, token_id: u256) -> u128 {
        return self.sell_orders.read(token_id);
    }

    #[external(v0)]
    fn set_sell_order(ref self: ContractState, token_id: u256, price: u128) {
        assert(self.owners.read(token_id) == get_caller_address(), 'ERC721: caller is not owner');

        self.sell_orders.write(token_id, price);
        self.emit(SellOrderSet {
            token_id: token_id,
            price: price
        });
    }

    #[external(v0)]
    fn fill_sell_order(ref self: ContractState, token_id: u256) {
        assert(self.sell_orders.read(token_id) != 0, 'ERC721: no sell order for token');

        let seller = self.owners.read(token_id);
        let buyer = get_caller_address();
        let price = self.sell_orders.read(token_id);

        // Ensure that a matching SWAY receipt is confirmed
        let mut memo: Array<felt252> = Default::default();
        memo.append('Ship'.into());
        memo.append(token_id.low.into());
        memo.append(token_id.high.into());
        ISwayDispatcher { contract_address: self.sway_address.read() }.confirm_receipt(
            buyer, seller, price, memo.hash()
        );

        // Clear order and transfer ownership
        self.sell_orders.write(token_id, 0);
        _transfer(ref self, seller, buyer, token_id);
        self.emit(SellOrderFilled {
            token_id: token_id,
            price: price
        });
    }

    // ERC165 ---------------------------------------------------------------------------------------------------------

    #[external(v0)]
    fn supports_interface(self: @ContractState, interface_id: felt252) -> bool {
        return interface_id == IERC165_ID || interface_id == IERC721_ID || interface_id == IERC721_METADATA_ID;
    }

    #[external(v0)]
    fn supportsInterface(self: @ContractState, interface_id: felt252) -> bool {
        return supports_interface(self, interface_id);
    }

    // ERC721 ---------------------------------------------------------------------------------------------------------

    #[external(v0)]
    fn approve(ref self: ContractState, to: ContractAddress, token_id: u256) {
        let owner = self.owners.read(token_id);
        let caller = get_caller_address();
        assert(owner != to, 'ERC721: approval to owner');

        let approved_for_all = is_approved_for_all(@self, owner, caller);
        assert(owner == caller || approved_for_all , 'ERC721: unauthorized caller');

        self.token_approvals.write(token_id, to);
        self.emit(Approval { owner, approved: to, token_id });
    }

    #[external(v0)]
    fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
        assert(!account.is_zero(), 'ERC721: invalid account');
        return self.balances.read(account);
    }

    #[external(v0)]
    fn balanceOf(self: @ContractState, account: ContractAddress) -> u256 {
        return balance_of(self, account);
    }

    #[external(v0)]
    fn exists(self: @ContractState, token_id: u256) -> bool {
        return _exists(self, token_id);
    }

    #[external(v0)]
    fn get_approved(self: @ContractState, token_id: u256) -> ContractAddress {
        assert(_exists(self, token_id), 'ERC721: invalid token ID');
        return self.token_approvals.read(token_id);
    }

    #[external(v0)]
    fn getApproved(self: @ContractState, token_id: u256) -> ContractAddress {
        return get_approved(self, token_id);
    }

    #[external(v0)]
    fn is_approved_for_all(self: @ContractState, owner: ContractAddress, operator: ContractAddress) -> bool {
        return self.operator_approvals.read((owner, operator));
    }

    #[external(v0)]
    fn isApprovedForAll(self: @ContractState, owner: ContractAddress, operator: ContractAddress) -> bool {
        return is_approved_for_all(self, owner, operator);
    }

    #[external(v0)]
    fn name(self: @ContractState) -> felt252 {
        return self._name.read();
    }

    #[external(v0)]
    fn owner_of(self: @ContractState, token_id: u256) -> ContractAddress {
        return self.owners.read(token_id);
    }

    #[external(v0)]
    fn ownerOf(self: @ContractState, token_id: u256) -> ContractAddress {
        return owner_of(self, token_id);
    }

    #[external(v0)]
    fn safe_transfer_from(
        ref self: ContractState, from: ContractAddress, to: ContractAddress, token_id: u256, data: Span<felt252>
    ) {
        assert(_is_approved_or_owner(@self, get_caller_address(), token_id), 'ERC721: unauthorized caller');
        _transfer(ref self, from, to, token_id);
        assert(_check_on_erc721_received(@self, from, to, token_id, data), 'ERC721: safe transfer failed');
    }

    #[external(v0)]
    fn safeTransferFrom(
        ref self: ContractState, from: ContractAddress, to: ContractAddress, token_id: u256, data: Span<felt252>
    ) {
        safe_transfer_from(ref self, from, to, token_id, data);
    }

    #[external(v0)]
    fn set_approval_for_all(ref self: ContractState, operator: ContractAddress, approved: bool) {
        let owner = get_caller_address();
        assert(owner != operator, 'ERC721: self approval');
        self.operator_approvals.write((owner, operator), approved);
        self.emit(ApprovalForAll { owner, operator, approved });
    }

    #[external(v0)]
    fn setApprovalForAll(ref self: ContractState, operator: ContractAddress, approved: bool) {
        set_approval_for_all(ref self, operator, approved);
    }

    // Sets the base URI for token metadata
    #[external(v0)]
    fn set_base_uri(ref self: ContractState, uri: Array<felt252>) {
        assert(self.role_grants.read((get_caller_address(), roles::ADMIN)), 'ERC721: must be admin');
        self.base_uri.write(uri);
    }

    #[external(v0)]
    fn symbol(self: @ContractState) -> felt252 {
        return self._symbol.read();
    }

    #[external(v0)]
    fn token_uri(self: @ContractState, token_id: u256) -> Span<felt252> {
        assert(_exists(self, token_id), 'ERC721: invalid token ID');
        let mut token_uri = self.base_uri.read();
        token_uri.append(stringify_u256(token_id).try_into().unwrap());
        return token_uri.span();
    }

    #[external(v0)]
    fn tokenUri(self: @ContractState, token_id: u256) -> Span<felt252> {
        return token_uri(self, token_id);
    }

    #[external(v0)]
    fn transfer_from(ref self: ContractState, from: ContractAddress, to: ContractAddress, token_id: u256) {
        assert(_is_approved_or_owner(@self, get_caller_address(), token_id), 'ERC721: unauthorized caller');
        _transfer(ref self, from, to, token_id);
    }

    #[external(v0)]
    fn transferFrom(ref self: ContractState, from: ContractAddress, to: ContractAddress, token_id: u256) {
        transfer_from(ref self, from, to, token_id);
    }

    // Bridging -------------------------------------------------------------------------------------------------------

    #[external(v0)]
    fn set_l1_bridge_address(ref self: ContractState, address: EthAddress) {
        assert(self.role_grants.read((get_caller_address(), roles::ADMIN)), 'ERC721: must be admin');
        self.l1_bridge_address.write(address);
    }

    #[external(v0)]
    fn get_l1_bridge_address(self: @ContractState) -> EthAddress {
        return self.l1_bridge_address.read();
    }

    #[external(v0)]
    fn bridge_to_l1(ref self: ContractState, to_address: EthAddress, token_ids: Array<u128>) {
        assert(!to_address.is_zero(), 'invalid to address');
        assert(token_ids.len() <= 25, 'too many tokens');

        let l1_bridge_address: felt252 = (self.l1_bridge_address.read()).into();
        assert(l1_bridge_address != 0, 'l1 bridge not set');

        let contract_address: ContractAddress = get_contract_address();
        let caller: ContractAddress = get_caller_address();

        let mut payload: Array<felt252> = Default::default();
        payload.append(1); // BRIDGE_MODE_WITHDRAW
        payload.append(contract_address.into());
        payload.append(caller.into());
        payload.append(to_address.into());

        let mut iter = 0;
        loop {
            if iter >= token_ids.len() {
                break ();
            }

            let token_id: felt252 = (*token_ids[iter]).into();
            let token_id_u256: u256 = token_id.into();
            payload.append(token_id);

            // Transfer ownership to self
            // Note: _transfer will verify the caller is the current owner of the specified token
            _transfer(ref self, caller, contract_address, token_id_u256);

            self.emit(BridgedToL1 { token_id: token_id_u256, from_address: caller, to_address });
            iter += 1;
        };

        send_message_to_l1_syscall(to_address: l1_bridge_address, payload: payload.span());
    }

    #[l1_handler]
    fn bridge_from_l1(
        ref self: ContractState,
        from_address: felt252,
        to_address: ContractAddress,
        sender: EthAddress,
        token_ids: Array<felt252>
    ) {
        assert(from_address == (self.l1_bridge_address.read()).into(), 'invalid from address');
        let contract_address: ContractAddress = get_contract_address();
        let mut iter = 0;

        loop {
            if iter >= token_ids.len() { break (); }

            let token_id_u256: u256 = (*token_ids[iter]).into();
            let exists = _exists(@self, token_id_u256);

            // check if token exists, if so, transfer else mint
            if (exists == true) {
                _transfer(ref self, contract_address, to_address, token_id_u256);
            } else {
                _mint(ref self, to_address, token_id_u256);
            }

            self.emit(BridgedFromL1 { token_id: token_id_u256, to_address: to_address });
            iter += 1;
        };
    }

    // Private --------------------------------------------------------------------------------------------------------

    fn _check_on_erc721_received(
        self: @ContractState, from: ContractAddress, to: ContractAddress, token_id: u256, data: Span<felt252>
    ) -> bool {
        if (IERC165Dispatcher {contract_address: to}.supports_interface(IERC721_RECEIVER_ID)) {
            IERC721ReceiverDispatcher {contract_address: to}
                .on_erc721_received(get_caller_address(), from, token_id, data) == IERC721_RECEIVER_ID
        } else {
            IERC165Dispatcher {contract_address: to}.supports_interface(IACCOUNT_ID)
        }
    }

    fn _exists(self: @ContractState, token_id: u256) -> bool {
        !self.owners.read(token_id).is_zero()
    }

    fn _is_approved_or_owner(self: @ContractState, spender: ContractAddress, token_id: u256) -> bool {
        let owner = owner_of(self, token_id);
        let approved = get_approved(self, token_id);
        let is_approved_for_all = is_approved_for_all(self, owner, spender);
        return owner == spender || is_approved_for_all || spender == approved;
    }

    fn _mint(ref self: ContractState, to: ContractAddress, token_id: u256) {
        assert(!to.is_zero(), 'ERC721: invalid receiver');
        assert(!_exists(@self, token_id), 'ERC721: token already minted');

        // Update balances
        self.balances.write(to, self.balances.read(to) + 1.into());

        // Update token_id owner
        self.owners.write(token_id, to);

        // Emit event
        self.emit(Transfer { from: Zeroable::zero(), to, token_id });
    }

    fn _transfer(ref self: ContractState, from: ContractAddress, to: ContractAddress, token_id: u256) {
        assert(!to.is_zero(), 'ERC721: invalid receiver');
        let owner = owner_of(@self, token_id);
        assert(from == owner, 'ERC721: wrong sender');

        // Implicit clear approvals, no need to emit an event
        self.token_approvals.write(token_id, Zeroable::zero());

        // Update balances
        self.balances.write(from, balance_of(@self, from) - 1.into());
        self.balances.write(to, balance_of(@self, to) + 1.into());

        // Update token_id owner
        self.owners.write(token_id, to);

        // Emit event
        self.emit(Transfer { from, to, token_id });
    }
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use result::ResultTrait;
    use starknet::{ClassHash, EthAddress, deploy_syscall};
    use traits::{Into, TryInto};

    use influence::contracts::sway::{Sway, ISwayDispatcher, ISwayDispatcherTrait};
    use influence::test::helpers;
    use influence::types::ArrayHashTrait;

    use super::{Ship, IShipDispatcher, IShipDispatcherTrait};

    #[test]
    #[available_gas(1000000)]
    fn test_constructor() {
        let caller = starknet::contract_address_const::<'ADMIN'>();
        starknet::testing::set_caller_address(caller);

        let mut state = Ship::contract_state_for_testing();
        Ship::constructor(ref state, 'Influence Ships', 'INFSHP', caller);
        let res = Ship::has_grant(@state, caller, Ship::roles::ADMIN);

        assert(res, 'deployer should be admin');
    }

    #[test]
    #[available_gas(1000000)]
    fn test_grants() {
        let caller = starknet::contract_address_const::<'ADMIN'>();
        starknet::testing::set_caller_address(caller);

        let mut state = Ship::contract_state_for_testing();
        Ship::constructor(ref state, 'Influence Ships', 'INFSHP', caller);

        Ship::add_grant(ref state, caller, Ship::roles::MINTER);
        let res = Ship::has_grant(@state, caller, Ship::roles::MINTER);
        assert(res, 'caller should be minter');

        Ship::revoke_grant(ref state, caller, Ship::roles::MINTER);
        let res = Ship::has_grant(@state, caller, Ship::roles::MINTER);
        assert(!res, 'caller should not be minter');
    }

    #[test]
    #[available_gas(1000000)]
    #[should_panic(expected: ('ERC721: must be minter', ))]
    fn test_mint_without_grant() {
        let caller = starknet::contract_address_const::<'ADMIN'>();
        starknet::testing::set_caller_address(caller);

        let mut state = Ship::contract_state_for_testing();
        Ship::constructor(ref state, 'Influence Ships', 'INFSHP', caller);

        Ship::mint_with_auto_id(ref state, caller);
    }

    #[test]
    #[available_gas(1000000)]
    fn test_mint() {
        let caller = starknet::contract_address_const::<'ADMIN'>();
        starknet::testing::set_caller_address(caller);

        let mut state = Ship::contract_state_for_testing();
        Ship::constructor(ref state, 'Influence Ships', 'INFSHP', caller);
        Ship::add_grant(ref state, caller, Ship::roles::MINTER);

        let token_id = Ship::mint_with_auto_id(ref state, caller);
        let res = Ship::ownerOf(@state, token_id);
        assert(res == caller, 'caller should be owner');
    }

    #[test]
    #[available_gas(2000000)]
    fn test_transfer() {
        let caller = starknet::contract_address_const::<'ADMIN'>();
        starknet::testing::set_caller_address(caller);

        let mut state = Ship::contract_state_for_testing();
        Ship::constructor(ref state, 'Influence Ships', 'INFSHP', caller);
        Ship::add_grant(ref state, caller, Ship::roles::MINTER);

        let token_id = Ship::mint_with_auto_id(ref state, caller);
        let receiver = starknet::contract_address_const::<'RECEIVER'>();
        Ship::transfer_from(ref state, caller, receiver, token_id);
        let res = Ship::ownerOf(@state, token_id);
        assert(res == receiver, 'receiver should be owner');
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic(expected: ('ERC721: unauthorized caller', ))]
    fn test_transfer_wrong_caller() {
        let caller = starknet::contract_address_const::<'ADMIN'>();
        starknet::testing::set_caller_address(caller);

        let mut state = Ship::contract_state_for_testing();
        Ship::constructor(ref state, 'Influence Ships', 'INFSHP', caller);
        Ship::add_grant(ref state, caller, Ship::roles::MINTER);

        let token_id = Ship::mint_with_auto_id(ref state, caller);
        let receiver = starknet::contract_address_const::<'RECEIVER'>();
        let wrong_sender = starknet::contract_address_const::<'WRONG_SENDER'>();
        starknet::testing::set_caller_address(wrong_sender);
        Ship::transfer_from(ref state, caller, receiver, token_id);
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic(expected: ('ERC721: wrong sender', ))]
    fn test_transfer_wrong_sender() {
        let caller = starknet::contract_address_const::<'ADMIN'>();
        starknet::testing::set_caller_address(caller);

        let mut state = Ship::contract_state_for_testing();
        Ship::constructor(ref state, 'Influence Ships', 'INFSHP', caller);
        Ship::add_grant(ref state, caller, Ship::roles::MINTER);

        let token_id = Ship::mint_with_auto_id(ref state, caller);
        let receiver = starknet::contract_address_const::<'RECEIVER'>();
        let wrong_sender = starknet::contract_address_const::<'WRONG_SENDER'>();
        Ship::transfer_from(ref state, wrong_sender, receiver, token_id);
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic(expected: ('ERC721: invalid receiver', ))]
    fn test_transfer_invalid_receiver() {
        let caller = starknet::contract_address_const::<'ADMIN'>();
        starknet::testing::set_caller_address(caller);

        let mut state = Ship::contract_state_for_testing();
        Ship::constructor(ref state, 'Influence Ships', 'INFSHP', caller);
        Ship::add_grant(ref state, caller, Ship::roles::MINTER);

        let token_id = Ship::mint_with_auto_id(ref state, caller);
        let invalid_receiver = starknet::contract_address_const::<0>();
        Ship::transfer_from(ref state, caller, invalid_receiver, token_id);
    }

    #[test]
    #[available_gas(2000000)]
    fn test_approve_other_sender() {
        let caller = starknet::contract_address_const::<'ADMIN'>();
        starknet::testing::set_caller_address(caller);
        let other_sender = starknet::contract_address_const::<'OTHER_SENDER'>();

        let mut state = Ship::contract_state_for_testing();
        Ship::constructor(ref state, 'Influence Ships', 'INFSHP', caller);
        Ship::add_grant(ref state, caller, Ship::roles::MINTER);

        let token_id = Ship::mint_with_auto_id(ref state, caller);
        Ship::approve(ref state, other_sender, token_id);
        let res = Ship::getApproved(@state, token_id);
        assert(res == other_sender, 'other sender should be approved');
    }

    #[test]
    #[available_gas(2000000)]
    fn test_send_with_approval() {
        let caller = starknet::contract_address_const::<'ADMIN'>();
        starknet::testing::set_caller_address(caller);
        let other_sender = starknet::contract_address_const::<'OTHER_SENDER'>();

        let mut state = Ship::contract_state_for_testing();
        Ship::constructor(ref state, 'Influence Ships', 'INFSHP', caller);
        Ship::add_grant(ref state, caller, Ship::roles::MINTER);

        let token_id = Ship::mint_with_auto_id(ref state, caller);
        Ship::approve(ref state, other_sender, token_id);
        starknet::testing::set_caller_address(other_sender);
        Ship::transfer_from(ref state, caller, other_sender, token_id);
        let res = Ship::ownerOf(@state, token_id);
        assert(res == other_sender, 'sender should be new owner');
    }

    #[test]
    #[available_gas(2000000)]
    fn test_token_uri() {
        let caller = starknet::contract_address_const::<'ADMIN'>();
        starknet::testing::set_caller_address(caller);

        let mut state = Ship::contract_state_for_testing();
        Ship::constructor(ref state, 'Influence Ships', 'INFSHP', caller);
        Ship::add_grant(ref state, caller, Ship::roles::MINTER);

        let mut base_uri: Array<felt252> = Default::default();
        base_uri.append('https://api.influenceth.io/');
        base_uri.append('metadata/ships/');
        Ship::set_base_uri(ref state, base_uri);

        let token_id = Ship::mint_with_auto_id(ref state, caller);
        let res = Ship::token_uri(@state, token_id);
        assert(*res.at(0) == 'https://api.influenceth.io/', 'wrong base uri');
        assert(*res.at(1) == 'metadata/ships/', 'wrong base uri');
        assert(*res.at(2) == '1', 'wrong base uri');
    }

    #[test]
    #[available_gas(2000000)]
    fn test_bridge_from_l1() {
        let caller = starknet::contract_address_const::<'ADMIN'>();
        starknet::testing::set_caller_address(caller);

        let mut state = Ship::contract_state_for_testing();
        Ship::constructor(ref state, 'Influence Ships', 'INFSHP', caller);
        Ship::add_grant(ref state, caller, Ship::roles::MINTER);

        Ship::set_l1_bridge_address(ref state, 'L1_BRIDGE'.try_into().unwrap());
        let token_ids = array![42];
        Ship::bridge_from_l1(
            ref state,
            'L1_BRIDGE',
            starknet::contract_address_const::<'PLAYER'>(),
            'L1_SENDER'.try_into().unwrap(),
            token_ids
        );

        let owner = Ship::ownerOf(@state, 42);
        assert(owner == starknet::contract_address_const::<'PLAYER'>(), 'wrong owner');
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic(expected: ('invalid from address', ))]
    fn test_bridge_from_l1_fail() {
        let caller = starknet::contract_address_const::<'ADMIN'>();
        starknet::testing::set_caller_address(caller);

        let mut state = Ship::contract_state_for_testing();
        Ship::constructor(ref state, 'Influence Ships', 'INFSHP', caller);
        Ship::add_grant(ref state, caller, Ship::roles::MINTER);

        Ship::set_l1_bridge_address(ref state, 'L1_BRIDGE'.try_into().unwrap());
        let token_ids = array![42];
        Ship::bridge_from_l1(
            ref state,
            'INCORRECT_L1_BRIDGE',
            starknet::contract_address_const::<'PLAYER'>(),
            'L1_SENDER'.try_into().unwrap(),
            token_ids
        );
    }

    #[test]
    #[available_gas(2000000)]
    fn test_erc165_response() {
        let caller = starknet::contract_address_const::<'ADMIN'>();
        starknet::testing::set_caller_address(caller);
        let mut state = Ship::contract_state_for_testing();
        Ship::constructor(ref state, 'Influence Ships', 'INFSHP', caller);

        let mut res = Ship::supports_interface(@state, 0x01ffc9a7);
        assert(res, 'should support erc165');

        res = Ship::supports_interface(@state, 0x80ac58cd);
        assert(res, 'should support erc721');

        res = Ship::supports_interface(@state, 0x5b5e139f);
        assert(res, 'should support erc721 metadata');
    }

    #[test]
    #[available_gas(2000000)]
    fn test_set_sell_order() {
        let caller = starknet::contract_address_const::<'ADMIN'>();
        starknet::testing::set_caller_address(caller);

        let mut state = Ship::contract_state_for_testing();
        Ship::constructor(ref state, 'Influence Ships', 'INFSHP', caller);
        Ship::add_grant(ref state, caller, Ship::roles::MINTER);

        let token_id = 1_u256;
        let price = 1000_u128;
        Ship::mint_with_auto_id(ref state, caller);
        Ship::set_sell_order(ref state, token_id, price);
        assert(Ship::get_sell_order(@state, token_id) == price, 'wrong price');

        Ship::set_sell_order(ref state, token_id, 0);
        assert(Ship::get_sell_order(@state, token_id) == 0, 'wrong price');
    }

    #[test]
    #[available_gas(10000000)]
    fn test_fill_sell_order() {
        let ast_class_hash: ClassHash = Ship::TEST_CLASS_HASH.try_into().unwrap();
        let mut constructor_data: Array<felt252> = Default::default();
        constructor_data.append('Influence Ships');
        constructor_data.append('INFSHP');
        constructor_data.append('ADMIN');
        let (ship_address, _) = deploy_syscall(ast_class_hash, 0, constructor_data.span(), false).unwrap();
        let ship = IShipDispatcher { contract_address: ship_address };

        let caller = starknet::contract_address_const::<'ADMIN'>();
        starknet::testing::set_caller_address(caller);

        // Deploy SWAY
        let sway_address = helpers::deploy_sway();
        let amount: u256 = 100 * 1000000;
        starknet::testing::set_contract_address(starknet::contract_address_const::<'ADMIN'>());
        let sway = ISwayDispatcher { contract_address: sway_address };
        sway.mint(starknet::contract_address_const::<'BUYER'>(), amount);

        ship.set_sway_address(sway_address);
        ship.add_grant(caller, Ship::roles::MINTER);

        let token_id = 1_u256;
        let price = 1000_u128;
        ship.mint_with_auto_id(caller);
        ship.set_sell_order(token_id, price);

        let buyer = starknet::contract_address_const::<'BUYER'>();
        starknet::testing::set_contract_address(starknet::contract_address_const::<'BUYER'>());

        // Remove when compiler is fixed
        internal::revoke_ap_tracking();

        // Send payment
        let mut memo: Array<felt252> = Default::default();
        memo.append('Ship');
        memo.append(token_id.low.into());
        memo.append(token_id.high.into());

        sway.transfer_with_confirmation(
            starknet::contract_address_const::<'ADMIN'>(),
            price,
            memo.hash(),
            ship_address
        );

        ship.fill_sell_order(token_id);
        assert(ship.get_sell_order(token_id) == 0, 'wrong price');
        assert(ship.owner_of(token_id) == buyer, 'wrong owner');
    }
}
