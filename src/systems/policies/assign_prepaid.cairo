#[starknet::contract]
mod AssignPrepaidPolicy {
    use option::OptionTrait;
    use starknet::ContractAddress;
    use traits::{Into, TryInto};

    use influence::{components, config};
    use influence::common::crew::CrewDetailsTrait;
    use influence::components::{Crew, CrewTrait, PrepaidPolicy, PrepaidPolicyTrait};
    use influence::config::errors;
    use influence::systems::policies::helpers::{assert_no_current_policy, policy_path};
    use influence::types::{Context, Entity, EntityTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct PrepaidPolicyAssigned {
        entity: Entity,
        permission: u64,
        rate: u64,
        initial_term: u64,
        notice_period: u64,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        PrepaidPolicyAssigned: PrepaidPolicyAssigned
    }

    #[external(v0)]
    fn run(
        ref self: ContractState,
        target: Entity,
        permission: u64,
        rate: u64,
        initial_term: u64,
        notice_period: u64,
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

        assert(
            initial_term + notice_period <= config::get('MAX_POLICY_DURATION').try_into().unwrap(),
            'policy too long'
        );

        // Setup and save new policy
        components::set::<PrepaidPolicy>(path, PrepaidPolicyTrait::new(rate, initial_term, notice_period));
        self.emit(PrepaidPolicyAssigned {
            entity: target,
            permission: permission,
            rate: rate,
            initial_term: initial_term,
            notice_period: notice_period,
            caller_crew: caller_crew,
            caller: context.caller
        });
    }
}
