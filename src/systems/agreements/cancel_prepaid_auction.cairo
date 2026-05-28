#[starknet::contract]
mod CancelPrepaidAgreementAuction {
    use option::OptionTrait;
    use starknet::ContractAddress;

    use influence::components::{PrepaidAgreementAuction, PrepaidAgreementAuctionTrait};
    use influence::{components};
    use influence::common::crew::CrewDetailsTrait;
    use influence::config::{entities, errors};
    use influence::types::{Context, Entity, EntityTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct PrepaidAgreementAuctionCancelled {
        lot: Entity,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        PrepaidAgreementAuctionCancelled: PrepaidAgreementAuctionCancelled
    }

    #[external(v0)]
    fn run(ref self: ContractState, lot: Entity, caller_crew: Entity, context: Context) {
        assert(lot.label == entities::LOT, errors::INCORRECT_ENTITY_TYPE);

        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_delegated_to(context.caller);
        crew_details.assert_manned();

        let (asteroid_id, _) = lot.to_position();
        let asteroid = EntityTrait::new(entities::ASTEROID, asteroid_id);
        caller_crew.assert_controls(asteroid);

        components::get::<PrepaidAgreementAuction>(lot.path()).expect(errors::PREPAID_AUCTION_NOT_FOUND);
        components::set::<PrepaidAgreementAuction>(lot.path(), PrepaidAgreementAuctionTrait::inactive());

        self.emit(PrepaidAgreementAuctionCancelled {
            lot: lot,
            caller_crew: caller_crew,
            caller: context.caller
        });
    }
}
