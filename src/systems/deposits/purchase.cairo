#[starknet::contract]
mod PurchaseDeposit {
    use array::{Array, ArrayTrait};
    use option::OptionTrait;
    use starknet::ContractAddress;
    use traits::Into;

    use influence::{components, contracts};
    use influence::common::crew::CrewDetailsTrait;
    use influence::components::{Control, ControlTrait, Crew, CrewTrait,
        deposit::{statuses as deposit_statuses, Deposit, DepositTrait},
        private_sale::{statuses as sale_statuses, PrivateSale, PrivateSaleTrait}};
    use influence::config::errors;
    use influence::contracts::sway::{ISwayDispatcher, ISwayDispatcherTrait};
    use influence::types::{Context, Entity, EntityTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct DepositPurchased {
        deposit: Entity,
        price: u64,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[derive(Copy, Drop, starknet::Event)]
    struct DepositPurchasedV1 {
        deposit: Entity,
        price: u64,
        seller_crew: Entity,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        DepositPurchased: DepositPurchased,
        DepositPurchasedV1: DepositPurchasedV1
    }

    #[external(v0)]
    fn run(ref self: ContractState, deposit: Entity, caller_crew: Entity, context: Context) {
        // Check that crew is delegated
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_all_but_ready(context.caller, context.now);

        // Check that crew is on the same asteroid
        let (deposit_ast, _) = deposit.to_position();
        let (crew_ast, _) = caller_crew.to_position();
        assert(deposit_ast == crew_ast, errors::DIFFERENT_ASTEROIDS);

        // Make sure deposit isn't in process of sampling
        let mut deposit_data = components::get::<Deposit>(deposit.path()).expect(errors::DEPOSIT_NOT_FOUND);
        assert(deposit_data.status != deposit_statuses::SAMPLING, errors::INCORRECT_STATUS);

        // Get sale information and validate
        let mut sale_data = components::get::<PrivateSale>(deposit.path()).expect(errors::PRIVATE_SALE_NOT_FOUND);
        assert(sale_data.status == sale_statuses::OPEN, errors::SALE_NOT_ACTIVE);

        // Confirm receipt on SWAY contract for fee to marketplace
        let seller_crew = components::get::<Control>(deposit.path()).expect(errors::CONTROL_NOT_FOUND).controller;
        let seller_address = components::get::<Crew>(seller_crew.path()).expect(errors::CREW_NOT_FOUND).delegated_to;

        ISwayDispatcher { contract_address: contracts::get('Sway') }.confirm_receipt(
            context.caller, seller_address, sale_data.amount.into(), deposit.into()
        );

        // Transfer control and update private sale info
        components::set::<Control>(deposit.path(), ControlTrait::new(caller_crew));
        components::set::<PrivateSale>(deposit.path(), PrivateSale { status: 0, amount: 0 });

        self.emit(DepositPurchasedV1 {
            deposit: deposit,
            price: sale_data.amount,
            seller_crew: seller_crew,
            caller_crew: caller_crew,
            caller: context.caller
        });
    }
}