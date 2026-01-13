#[starknet::contract]
mod UnlistDepositForSale {
    use array::{Array, ArrayTrait};
    use option::OptionTrait;
    use starknet::ContractAddress;
    use traits::Into;

    use influence::components;
    use influence::common::crew::CrewDetailsTrait;
    use influence::components::{PrivateSale, PrivateSaleTrait};
    use influence::config::errors;
    use influence::types::{Context, Entity, EntityTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct DepositUnlistedForSale {
        deposit: Entity,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        DepositUnlistedForSale: DepositUnlistedForSale
    }

    #[external(v0)]
    fn run(ref self: ContractState, deposit: Entity, caller_crew: Entity, context: Context) {
        // Check that crew is delegated
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_all_but_ready(context.caller, context.now);
        caller_crew.assert_controls(deposit);

        // Check that crew is on the same asteroid
        let (deposit_ast, _) = deposit.to_position();
        let (crew_ast, _) = caller_crew.to_position();
        assert(deposit_ast == crew_ast, errors::DIFFERENT_ASTEROIDS);

        components::set::<PrivateSale>(deposit.path(), PrivateSale { status: 0, amount: 0 });
        self.emit(DepositUnlistedForSale {
            deposit: deposit,
            caller_crew: caller_crew,
            caller: context.caller
        });
    }
}