#[starknet::contract]
mod RemovePrepaidMerklePolicy {
    use option::OptionTrait;
    use starknet::ContractAddress;
    use traits::Into;

    use influence::components;
    use influence::common::crew::CrewDetailsTrait;
    use influence::components::{Crew, CrewTrait, PrepaidMerklePolicy, PrepaidMerklePolicyTrait};
    use influence::config::errors;
    use influence::systems::policies::helpers::policy_path;
    use influence::types::{Context, Entity, EntityTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct PrepaidMerklePolicyRemoved {
        entity: Entity,
        permission: u64,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        PrepaidMerklePolicyRemoved: PrepaidMerklePolicyRemoved
    }

    #[external(v0)]
    fn run(ref self: ContractState, target: Entity, permission: u64, caller_crew: Entity, context: Context) {
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_delegated_to(context.caller);
        crew_details.assert_manned();
        caller_crew.assert_controls(target);

        // Check existing policy
        let path = policy_path(target, permission);
        assert(components::get::<PrepaidMerklePolicy>(path).is_some(), 'no policy set');

        // Modify to "empty" and save
        components::set::<PrepaidMerklePolicy>(path, PrepaidMerklePolicyTrait::new(0, 0, 0));
        self.emit(PrepaidMerklePolicyRemoved {
            entity: target,
            permission: permission,
            caller_crew: caller_crew,
            caller: context.caller
        });
    }
}
