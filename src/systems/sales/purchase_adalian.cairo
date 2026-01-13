#[starknet::contract]
mod PurchaseAdalian {
    use option::OptionTrait;
    use starknet::ContractAddress;
    use traits::{Into, TryInto};

    use influence::common::nft::purchase_crewmate;
    use influence::types::{Context, Entity, EntityTrait};

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
    fn run(ref self: ContractState, collection: u64, context: Context) {
        let (crewmate, crewmate_data) = purchase_crewmate(collection, context.caller);
        self.emit(CrewmatePurchased { crewmate, caller: context.caller });
    }
}

// Tested via integration tests