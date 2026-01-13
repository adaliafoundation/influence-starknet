#[starknet::contract]
mod AssignContractPolicy {
    use option::OptionTrait;
    use starknet::ContractAddress;
    use traits::Into;

    use influence::components;
    use influence::common::crew::CrewDetailsTrait;
    use influence::components::{ContractPolicy, ContractPolicyTrait, Crew, CrewTrait};
    use influence::config::errors;
    use influence::systems::policies::helpers::{assert_no_current_policy, policy_path};
    use influence::types::{Context, Entity, EntityTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct ContractPolicyAssigned {
        entity: Entity,
        permission: u64,
        contract: ContractAddress,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        ContractPolicyAssigned: ContractPolicyAssigned
    }

    #[external(v0)]
    fn run(
        ref self: ContractState,
        target: Entity,
        permission: u64,
        contract: ContractAddress,
        caller_crew: Entity,
        context: Context
    ) {
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_delegated_to(context.caller);
        crew_details.assert_manned();
        caller_crew.assert_controls(target);

        // Check that no policy assigned
        let path = policy_path(target, permission);
        assert_no_current_policy(target, path);

        // Setup and save new policy
        components::set::<ContractPolicy>(path, ContractPolicyTrait::new(contract));
        self.emit(ContractPolicyAssigned {
            entity: target,
            permission: permission,
            contract: contract,
            caller_crew: caller_crew,
            caller: context.caller
        });
    }
}
