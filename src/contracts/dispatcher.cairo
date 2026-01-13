#[starknet::contract]
mod Dispatcher {
    use array::{ArrayTrait, ArrayTCloneImpl, SpanTrait};
    use clone::Clone;
    use serde::Serde;
    use option::{Option, OptionTrait};
    use starknet::{ClassHash, ContractAddress};
    use starknet::class_hash::Felt252TryIntoClassHash;
    use starknet::syscalls::{library_call_syscall, replace_class_syscall};
    use traits::{Into, TryInto};

    use influence::{components, systems};
    use influence::common::{packed, random};
    use influence::types::{Entity, EntityTrait};

    mod roles {
        const ADMIN: u64 = 1;
    }

    #[storage]
    struct Storage {
        admin: ContractAddress,
        constants: LegacyMap::<felt252, felt252>, // name -> constant (game constants)
        contract_registry: LegacyMap::<felt252, ContractAddress>,
        role_grants: LegacyMap::<(ContractAddress, u64), bool>,
        system_registry: LegacyMap::<felt252, ClassHash>
    }

    #[derive(Copy, Drop, starknet::Event)]
    struct ConstantRegistered {
        name: felt252,
        value: felt252
    }

    #[derive(Copy, Drop, starknet::Event)]
    struct ContractRegistered {
        name: felt252,
        address: ContractAddress
    }

    #[derive(Copy, Drop, starknet::Event)]
    struct SystemRegistered {
        name: felt252,
        class_hash: ClassHash
    }

    #[derive(Copy, Drop, starknet::Event)]
    struct EntropyGenerated {
        entropy: felt252,
        round: u64
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        ConstantRegistered: ConstantRegistered,
        ContractRegistered: ContractRegistered,
        SystemRegistered: SystemRegistered,
        EntropyGenerated: EntropyGenerated
    }

    #[constructor]
    fn constructor(ref self: ContractState, admin: ContractAddress) {
        self.admin.write(admin);
        self.role_grants.write((admin, roles::ADMIN), true);
    }

    #[external(v0)]
    fn set_admin(ref self: ContractState, admin: ContractAddress) {
        assert_admin(@self);
        self.admin.write(admin);
    }

    #[external(v0)]
    fn add_grant(ref self: ContractState, account: ContractAddress, role: u64) {
        assert_admin(@self);
        self.role_grants.write((account, role), true);
    }

    #[external(v0)]
    fn has_grant(self: @ContractState, account: ContractAddress, role: u64) -> bool {
        return self.role_grants.read((account, role));
    }

    #[external(v0)]
    fn revoke_grant(ref self: ContractState, account: ContractAddress, role: u64) {
        assert_admin(@self);
        self.role_grants.write((account, role), false);
    }

    #[external(v0)]
    fn upgrade(ref self: ContractState, class_hash: ClassHash) {
        assert_admin(@self);
        replace_class_syscall(class_hash);
    }

    // Manage game constants
    #[external(v0)]
    fn constant(self: @ContractState, name: felt252) -> felt252 {
        return self.constants.read(name);
    }

    #[external(v0)]
    fn register_constant(ref self: ContractState, name: felt252, value: felt252) {
        assert_admin(@self);
        self.emit(ConstantRegistered { name: name, value: value });
        return self.constants.write(name, value);
    }

    // Manage external contracts (NFTs / SWAY / ETH)
    #[external(v0)]
    fn contract(self: @ContractState, name: felt252) -> ContractAddress {
        return self.contract_registry.read(name);
    }

    #[external(v0)]
    fn register_contract(ref self: ContractState, name: felt252, address: ContractAddress) {
        assert_admin(@self);
        self.emit(ContractRegistered { name: name, address: address });
        return self.contract_registry.write(name, address);
    }

    // Manage systems
    #[external(v0)]
    fn system(self: @ContractState, name: felt252) -> ClassHash {
        return self.system_registry.read(name);
    }

    #[external(v0)]
    fn register_system(ref self: ContractState, name: felt252, class_hash: ClassHash) {
        assert_admin(@self);
        self.emit(SystemRegistered { name: name, class_hash: class_hash });
        return self.system_registry.write(name, class_hash);
    }

    // Run systems
    #[external(v0)]
    fn run_system(ref self: ContractState, name: felt252, mut calldata: Array<felt252>) -> Span<felt252> {
        // Check if entropy should be generated and do it if needed
        let (generated, round) = random::entropy::generate();

        // Emit event if entropy was generated
        if (generated != 0) {
            self.emit(EntropyGenerated {
                entropy: generated,
                round: round
            });
        }

        // Add the caller address to Context
        calldata.append(starknet::get_caller_address().into()); // caller
        calldata.append(starknet::get_block_timestamp().into()); // now
        calldata.append(0); // payment_to
        calldata.append(0); // PAYMENT_AMOUNT

        let class_hash = self.system_registry.read(name);
        let entrypoint = 0x17655d3ec0a25c443f877d52bb6b36e9e6aaf8fbeb43608c3b9423bdc0822be; // run
        return library_call_syscall(class_hash.into(), entrypoint, calldata.span()).unwrap_syscall();
    }

    #[external(v0)]
    fn run_system_with_payment(
        ref self: ContractState, name: felt252, mut calldata: Array<felt252>, payment: Array<felt252>
    ) -> Span<felt252> {
        // Check that call originates from SWAY contract
        assert(starknet::get_caller_address() == contract(@self, 'SWAY'), 'must be called from SWAY');

        // Check if entropy should be generated and do it if needed
        random::entropy::generate();

        // Add the sender as caller, and payment details to Context
        calldata.append(*payment.at(0)); // caller
        calldata.append(starknet::get_block_timestamp().into()); // now
        calldata.append(*payment.at(1)); // payment_to
        calldata.append(*payment.at(2)); // payment_amount

        let class_hash = self.system_registry.read(name);
        let entrypoint = 0x17655d3ec0a25c443f877d52bb6b36e9e6aaf8fbeb43608c3b9423bdc0822be; // run
        return library_call_syscall(class_hash.into(), entrypoint, calldata.span()).unwrap_syscall();
    }

    fn assert_admin(self: @ContractState) {
        let role_admin = self.role_grants.read((starknet::get_caller_address(), roles::ADMIN));
        let legacy_admin = starknet::get_caller_address() == self.admin.read();
        assert(role_admin || legacy_admin, 'must be admin');
    }
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use array::{ArrayTrait, SpanTrait};
    use serde::Serde;
    use traits::{Into, TryInto};

    use influence::config::entities;
    use influence::components;
    use influence::components::{Control, ControlTrait, Crew, CrewTrait, Name};
    use influence::systems::change_name::ChangeName;
    use influence::systems::read_component::ReadComponent;
    use influence::types::{Entity, EntityTrait, String, StringTrait};
    use influence::test::{helpers, mocks};

    use super::Dispatcher;

    #[test]
    #[available_gas(5000000)]
    fn test_run_system() {
        helpers::deploy_system('ChangeName', ChangeName::TEST_CLASS_HASH);

        let entity = EntityTrait::new(entities::ASTEROID, 1);
        let crew = EntityTrait::new(entities::CREW, 1);
        components::set::<Crew>(crew.path(), CrewTrait::new(starknet::contract_address_const::<'PLAYER'>()));
        components::set::<Control>(entity.path(), ControlTrait::new(crew));

        // Build up calldata
        let mut run_calldata = Default::default();
        Serde::<Entity>::serialize(@entity, ref run_calldata);
        run_calldata.append('Austin Powers');
        Serde::<Entity>::serialize(@crew, ref run_calldata);

        starknet::testing::set_caller_address(starknet::contract_address_const::<'PLAYER'>());
        let mut state = Dispatcher::contract_state_for_testing();
        let res = Dispatcher::run_system(ref state, 'ChangeName', run_calldata);
    }

    #[test]
    #[available_gas(5000000)]
    fn test_run_system_with_payment() {
        helpers::deploy_system('ChangeName', ChangeName::TEST_CLASS_HASH);

        let entity = EntityTrait::new(entities::ASTEROID, 1);
        let crew = EntityTrait::new(entities::CREW, 1);
        components::set::<Crew>(crew.path(), CrewTrait::new(starknet::contract_address_const::<'PLAYER'>()));
        components::set::<Control>(entity.path(), ControlTrait::new(crew));

        // Build up calldata
        let mut run_calldata = Default::default();
        Serde::<Entity>::serialize(@entity, ref run_calldata);
        run_calldata.append('Austin Powers');
        Serde::<Entity>::serialize(@crew, ref run_calldata);

        // Payment info
        let payment: Array<felt252> = array!['PLAYER', 5678, 1000];

        let mut state = Dispatcher::contract_state_for_testing();
        Dispatcher::constructor(ref state, starknet::contract_address_const::<'ADMIN'>());

        starknet::testing::set_caller_address(starknet::contract_address_const::<'ADMIN'>());
        Dispatcher::register_contract(ref state, 'SWAY', starknet::contract_address_const::<'SWAY'>());

        // Switch to call from SWAY contract context
        starknet::testing::set_caller_address(starknet::contract_address_const::<'SWAY'>());
        let res = Dispatcher::run_system_with_payment(ref state, 'ChangeName', run_calldata, payment);
    }

    #[test]
    #[available_gas(5000000)]
    fn test_read_component() {
        helpers::deploy_system('ChangeName', ChangeName::TEST_CLASS_HASH);
        helpers::deploy_system('ReadComponent', ReadComponent::TEST_CLASS_HASH);

        let entity = EntityTrait::new(entities::ASTEROID, 1);
        let crew = EntityTrait::new(entities::CREW, 1);
        components::set::<Crew>(crew.path(), CrewTrait::new(starknet::contract_address_const::<'PLAYER'>()));
        components::set::<Control>(entity.path(), ControlTrait::new(crew));

        // Build up calldata
        let mut run_calldata = Default::default();
        Serde::<Entity>::serialize(@entity, ref run_calldata);
        run_calldata.append('Austin Powers');
        Serde::<Entity>::serialize(@crew, ref run_calldata);

        starknet::testing::set_caller_address(starknet::contract_address_const::<'PLAYER'>());
        let mut state = Dispatcher::contract_state_for_testing();
        Dispatcher::run_system(ref state, 'ChangeName', run_calldata);

        let mut read_calldata: Array<felt252> = array!['Name'];
        Serde::<Span<felt252>>::serialize(@entity.path(), ref read_calldata);
        let mut res = Dispatcher::run_system(ref state, 'ReadComponent', read_calldata);
        assert(*res.at(1) == 'Austin Powers', 'read component wrong');
    }
}