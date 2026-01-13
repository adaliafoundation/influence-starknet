#[starknet::contract]
mod ListDepositForSale {
    use array::{Array, ArrayTrait};
    use option::OptionTrait;
    use starknet::ContractAddress;
    use traits::Into;

    use influence::components;
    use influence::common::crew::CrewDetailsTrait;
    use influence::components::{PrivateSale, PrivateSaleTrait,
        deposit::{statuses as deposit_statuses, Deposit, DepositTrait}};
    use influence::config::errors;
    use influence::types::{Context, Entity, EntityTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct DepositListedForSale {
        deposit: Entity,
        price: u64,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        DepositListedForSale: DepositListedForSale
    }

    #[external(v0)]
    fn run(ref self: ContractState, deposit: Entity, price: u64, caller_crew: Entity, context: Context) {
        // Check that crew is delegated
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_all_but_ready(context.caller, context.now);
        caller_crew.assert_controls(deposit);

        // Check that crew is on the same asteroid
        let (deposit_ast, _) = deposit.to_position();
        let (crew_ast, _) = caller_crew.to_position();
        assert(deposit_ast == crew_ast, errors::DIFFERENT_ASTEROIDS);

        // Ensure deposit is in the right state
        let mut deposit_data = components::get::<Deposit>(deposit.path()).expect(errors::DEPOSIT_NOT_FOUND);
        assert(deposit_data.status >= deposit_statuses::SAMPLED, errors::INCORRECT_STATUS);

        components::set::<PrivateSale>(deposit.path(), PrivateSaleTrait::new(price));
        self.emit(DepositListedForSale {
            deposit: deposit,
            price: price,
            caller_crew: caller_crew,
            caller: context.caller
        });
    }
}
