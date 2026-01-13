#[starknet::contract]
mod GrantAdalians {
    use option::OptionTrait;
    use starknet::ContractAddress;
    use traits::{Into, TryInto};

    use influence::{contracts, components};
    use influence::components::{Crew, CrewTrait, crewmate::{Crewmate, CrewmateTrait, collections}};
    use influence::config::{entities, errors};
    use influence::contracts::crewmate::{ICrewmateDispatcher, ICrewmateDispatcherTrait};
    use influence::types::{Context, ContextTrait, Entity, EntityTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct CrewmatePurchased {
        crewmate: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        CrewmatePurchased: CrewmatePurchased
    }

    #[external(v0)]
    fn run(ref self: ContractState, recipient: ContractAddress, count: u64, context: Context) {
        // Check the caller is the admin
        assert(context.is_admin(), 'only admin can write');

        let mut iter = 0;
        loop {
            if iter >= count { break; };
            let id = ICrewmateDispatcher { contract_address: contracts::get('Crewmate') }.mint_with_auto_id(recipient);
            let crewmate = EntityTrait::new(entities::CREWMATE, id.try_into().unwrap());
            let crewmate_data = CrewmateTrait::new(collections::ADALIAN);
            components::set::<Crewmate>(crewmate.path(), crewmate_data);
            self.emit(CrewmatePurchased { crewmate, caller: context.caller });
            iter += 1;
        };
    }
}
