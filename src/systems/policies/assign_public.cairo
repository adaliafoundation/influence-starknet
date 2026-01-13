#[starknet::contract]
mod AssignPublicPolicy {
    use option::OptionTrait;
    use starknet::ContractAddress;
    use traits::Into;

    use influence::components;
    use influence::common::crew::CrewDetailsTrait;
    use influence::components::{Crew, CrewTrait, PublicPolicy, PublicPolicyTrait};
    use influence::config::errors;
    use influence::systems::policies::helpers::{assert_no_current_policy, policy_path};
    use influence::types::{Context, Entity, EntityTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct PublicPolicyAssigned {
        entity: Entity,
        permission: u64,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        PublicPolicyAssigned: PublicPolicyAssigned
    }

    #[external(v0)]
    fn run(ref self: ContractState, target: Entity, permission: u64, caller_crew: Entity, context: Context) {
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_delegated_to(context.caller);
        crew_details.assert_manned();
        caller_crew.assert_controls(target);

        // Check that no policy is assigned
        let path = policy_path(target, permission);
        assert_no_current_policy(target, path);

        // Store new policy
        components::set::<PublicPolicy>(path, PublicPolicyTrait::new(true));
        self.emit(PublicPolicyAssigned {
            entity: target,
            permission: permission,
            caller_crew: caller_crew,
            caller: context.caller
        });
    }
}
