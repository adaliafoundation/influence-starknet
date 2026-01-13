#[starknet::contract]
mod Whitelist {
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
    struct AddedToWhitelist {
        entity: Entity,
        permission: u64,
        target: Entity,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[derive(Copy, Drop, starknet::Event)]
    struct AddedToWhitelistV1 {
        target: Entity,
        permission: u64,
        permitted: Entity,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        AddedToWhitelist: AddedToWhitelist,
        AddedToWhitelistV1: AddedToWhitelistV1
    }

    #[external(v0)]
    fn run(
        ref self: ContractState,
        target: Entity,
        permission: u64,
        permitted: Entity,
        caller_crew: Entity,
        context: Context
    ) {
        // Check that crew is delegated
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_delegated_to(context.caller);
        caller_crew.assert_controls(target);

        // Update crew in whitelist
        let path = agreement_path(target, permission, permitted.into());
        components::set::<WhitelistAgreement>(path, WhitelistAgreementTrait::new(true));
        self.emit(AddedToWhitelistV1 {
            target: target,
            permission: permission,
            permitted: permitted,
            caller_crew: caller_crew,
            caller: context.caller
        });
    }
}
