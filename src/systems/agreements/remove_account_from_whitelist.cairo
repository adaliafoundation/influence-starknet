#[starknet::contract]
mod RemoveAccountFromWhitelist {
    use option::OptionTrait;
    use starknet::ContractAddress;
    use traits::Into;

    use influence::components;
    use influence::common::crew::CrewDetailsTrait;
    use influence::components::{WhitelistAgreement, WhitelistAgreementTrait};
    use influence::systems::agreements::helpers::agreement_path;
    use influence::types::{Context, Entity, EntityTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct RemovedAccountFromWhitelist {
        target: Entity,
        permission: u64,
        permitted: ContractAddress,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        RemovedAccountFromWhitelist: RemovedAccountFromWhitelist
    }

    #[external(v0)]
    fn run(
        ref self: ContractState,
        target: Entity,
        permission: u64,
        permitted: ContractAddress,
        caller_crew: Entity,
        context: Context
    ) {
        // Check that crew is delegated
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_delegated_to(context.caller);
        caller_crew.assert_controls(target);

        // Remove crew from whitelist
        let path = agreement_path(target, permission, permitted.into());
        components::set::<WhitelistAgreement>(path, WhitelistAgreementTrait::new(false));
        self.emit(RemovedAccountFromWhitelist {
            target: target,
            permission: permission,
            permitted: permitted,
            caller_crew: caller_crew,
            caller: context.caller
        });
    }
}
