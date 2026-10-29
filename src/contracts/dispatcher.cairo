#[starknet::contract]
mod Dispatcher {
    use array::{ArrayTrait, ArrayTCloneImpl, SpanTrait};
    use clone::Clone;
    use serde::Serde;
    use option::{Option, OptionTrait};
    use result::ResultTrait;
    use starknet::{ClassHash, ContractAddress, SyscallResultTrait};
    use starknet::class_hash::Felt252TryIntoClassHash;
    use starknet::storage::Map;
    use starknet::syscalls::{library_call_syscall, replace_class_syscall};
    use traits::{Into, TryInto};

    use influence::{components, systems};
    use influence::common::{packed, random};
    use influence::config::roles;
    use influence::types::{Entity, EntityTrait};

    #[storage]
    struct Storage {
        admin: ContractAddress,
        constants: Map::<felt252, felt252>, // name -> constant (game constants)
        contract_registry: Map::<felt252, ContractAddress>,
        role_grants: Map::<(ContractAddress, u64), bool>,
        system_registry: Map::<felt252, ClassHash>,
        observation_tx: felt252,
        observation_account: ContractAddress,
        observation_system: felt252,
        observation_args: felt252,
        observation_caller: ContractAddress,
        observation_policy: ClassHash,
        observation_active: bool,
        observation_executing: bool,
        observation_data_len: u32,
        observation_data: Map::<u32, felt252>
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
        replace_class_syscall(class_hash).unwrap_syscall();
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

    // Arm one exact native invocation within this account transaction.
    #[external(v0)]
    fn begin_observation(
        ref self: ContractState,
        policy: felt252,
        name: felt252,
        arguments_hash: felt252,
        expected_caller: ContractAddress,
        policy_data: Span<felt252>
    ) {
        let tx = starknet::get_tx_info().unbox();
        assert(
            starknet::get_caller_address() == tx.account_contract_address, 'only account may arm'
        );
        assert(!self.observation_executing.read(), 'observer reentry');
        assert(
            !(self.observation_active.read() && self.observation_tx.read() == tx.transaction_hash),
            'already armed'
        );
        let class = self.system_registry.read(policy);
        assert(class.into() != 0, 'unknown policy');
        self.observation_tx.write(tx.transaction_hash);
        // Keep the old storage fields in the layout, but bind the invocation in one slot.
        self
            .observation_args
            .write(
                poseidon::poseidon_hash_span(
                    array![name, arguments_hash, expected_caller.into()].span()
                )
            );
        assert(policy_data.len() <= 16, 'observation data too long');
        self.observation_data_len.write(policy_data.len());
        let mut i = 0;
        for value in policy_data {
            self.observation_data.write(i, *value);
            i += 1;
        };
        self.observation_policy.write(class);
        self.observation_active.write(true);
    }

    // The final multicall step prevents an unmatched arm from silently losing evidence.
    #[external(v0)]
    fn end_observation(ref self: ContractState) {
        let tx = starknet::get_tx_info().unbox();
        assert(starknet::get_caller_address() == tx.account_contract_address, 'account only');
        assert(self.observation_tx.read() == tx.transaction_hash, 'no observation');
        assert(
            !self.observation_active.read() && !self.observation_executing.read(),
            'observation not consumed'
        );
    }

    fn dispatch(
        ref self: ContractState, name: felt252, arguments: Span<felt252>, calldata: Span<felt252>
    ) -> Span<felt252> {
        let tx = starknet::get_tx_info().unbox();
        // Most transactions have no observation: one storage read, no policy lookup.
        if self.observation_tx.read() != tx.transaction_hash {
            return library_call_syscall(self.system_registry.read(name), selector!("run"), calldata)
                .unwrap_syscall();
        }
        assert(!self.observation_executing.read(), 'observer reentry');
        let observed = self.observation_active.read()
            && self
                .observation_args
                .read() == poseidon::poseidon_hash_span(
                    array![
                        name,
                        poseidon::poseidon_hash_span(arguments),
                        starknet::get_caller_address().into()
                    ]
                        .span()
                );
        let mut snapshot = array![].span();
        let policy = self.observation_policy.read();
        if observed {
            self.observation_active.write(false);
            self.observation_executing.write(true);
            let mut input = array![name];
            Serde::serialize(@calldata, ref input);
            let mut policy_data = array![];
            let length = self.observation_data_len.read();
            let mut i = 0;
            loop {
                if i == length {
                    break;
                }
                policy_data.append(self.observation_data.read(i));
                i += 1;
            };
            Serde::serialize(@policy_data, ref input);
            let mut output = library_call_syscall(policy, selector!("before"), input.span())
                .unwrap_syscall();
            snapshot = Serde::<Span<felt252>>::deserialize(ref output).unwrap();
            assert(output.is_empty(), 'invalid pre response');
        }
        let result = library_call_syscall(
            self.system_registry.read(name), selector!("run"), calldata
        )
            .unwrap_syscall();
        if observed {
            let mut input = array![name];
            Serde::serialize(@calldata, ref input);
            Serde::serialize(@snapshot, ref input);
            Serde::serialize(@result, ref input);
            library_call_syscall(policy, selector!("after"), input.span()).unwrap_syscall();
            self.observation_executing.write(false);
        }
        result
    }

    // Run systems
    #[external(v0)]
    fn run_system(
        ref self: ContractState, name: felt252, mut calldata: Array<felt252>
    ) -> Span<felt252> {
        // Check if entropy should be generated and do it if needed
        let (generated, round) = random::entropy::generate();

        // Emit event if entropy was generated
        if (generated != 0) {
            self.emit(EntropyGenerated { entropy: generated, round: round });
        }

        let arguments = calldata.span();
        // Add the caller address to Context
        calldata.append(starknet::get_caller_address().into()); // caller
        calldata.append(starknet::get_block_timestamp().into()); // now
        calldata.append(0); // payment_to
        calldata.append(0); // PAYMENT_AMOUNT

        dispatch(ref self, name, arguments, calldata.span())
    }

    #[external(v0)]
    fn run_system_with_payment(
        ref self: ContractState,
        name: felt252,
        mut calldata: Array<felt252>,
        payment: Array<felt252>
    ) -> Span<felt252> {
        // Check that call originates from SWAY contract
        assert(
            starknet::get_caller_address() == contract(@self, 'SWAY'), 'must be called from SWAY'
        );

        // Check if entropy should be generated and do it if needed
        random::entropy::generate();

        let arguments = calldata.span();
        // Add the sender as caller, and payment details to Context
        calldata.append(*payment.at(0)); // caller
        calldata.append(starknet::get_block_timestamp().into()); // now
        calldata.append(*payment.at(1)); // payment_to
        calldata.append(*payment.at(2)); // payment_amount

        dispatch(ref self, name, arguments, calldata.span())
    }

    fn assert_admin(self: @ContractState) {
        let role_admin = self.role_grants.read((starknet::get_caller_address(), roles::ADMIN));
        let legacy_admin = starknet::get_caller_address() == self.admin.read();
        assert(role_admin || legacy_admin, 'must be admin');
    }
}

// Tests
// --------------------------------------------------------------------------------------------------------------

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
        components::set::<
            Crew
        >(crew.path(), CrewTrait::new(starknet::contract_address_const::<'PLAYER'>()));
        components::set::<Control>(entity.path(), ControlTrait::new(crew));

        // Build up calldata
        let mut run_calldata = Default::default();
        Serde::<Entity>::serialize(@entity, ref run_calldata);
        run_calldata.append('Austin Powers');
        Serde::<Entity>::serialize(@crew, ref run_calldata);

        starknet::testing::set_caller_address(starknet::contract_address_const::<'PLAYER'>());
        let mut state = Dispatcher::contract_state_for_testing();
        let _res = Dispatcher::run_system(ref state, 'ChangeName', run_calldata);
    }

    #[test]
    #[available_gas(5000000)]
    fn test_run_system_with_payment() {
        helpers::deploy_system('ChangeName', ChangeName::TEST_CLASS_HASH);

        let entity = EntityTrait::new(entities::ASTEROID, 1);
        let crew = EntityTrait::new(entities::CREW, 1);
        components::set::<
            Crew
        >(crew.path(), CrewTrait::new(starknet::contract_address_const::<'PLAYER'>()));
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
        Dispatcher::register_contract(
            ref state, 'SWAY', starknet::contract_address_const::<'SWAY'>()
        );

        // Switch to call from SWAY contract context
        starknet::testing::set_caller_address(starknet::contract_address_const::<'SWAY'>());
        let _res = Dispatcher::run_system_with_payment(
            ref state, 'ChangeName', run_calldata, payment
        );
    }

    #[test]
    #[available_gas(5000000)]
    fn test_read_component() {
        helpers::deploy_system('ChangeName', ChangeName::TEST_CLASS_HASH);
        helpers::deploy_system('ReadComponent', ReadComponent::TEST_CLASS_HASH);

        let entity = EntityTrait::new(entities::ASTEROID, 1);
        let crew = EntityTrait::new(entities::CREW, 1);
        components::set::<
            Crew
        >(crew.path(), CrewTrait::new(starknet::contract_address_const::<'PLAYER'>()));
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
