#[starknet::contract]
mod AnnotateEvent {
    use array::{Array, ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use starknet::ContractAddress;
    use traits::Into;

    use influence::{components, contracts};
    use influence::common::crew::CrewDetailsTrait;
    use influence::components::{Crew, CrewTrait, Unique, UniqueTrait};
    use influence::config::errors;
    use influence::types::{Context, Entity, EntityTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct EventAnnotated {
        transaction_hash: felt252,
        log_index: u64,
        content_hash: Span<felt252>, // IPFS content hash
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        EventAnnotated: EventAnnotated
    }

    #[external(v0)]
    fn run(
        ref self: ContractState,
        transaction_hash: felt252,
        log_index: u64,
        content_hash: Span<felt252>,
        caller_crew: Entity,
        context: Context
    ) {
        // Check that crew is delegated
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_delegated_to(context.caller);

        let mut unique_key: Array<felt252> = Default::default();
        unique_key.append(transaction_hash);
        unique_key.append(log_index.into());
        unique_key.append(*content_hash.at(0));
        unique_key.append(*content_hash.at(1));
        unique_key.append(caller_crew.into());

        // Make sure annotation hasn't already been created
        assert(components::get::<Unique>(unique_key.span()).is_none(), errors::NOT_UNIQUE);

        components::set::<Unique>(unique_key.span(), UniqueTrait::new());

        self.emit(EventAnnotated {
            transaction_hash: transaction_hash,
            log_index: log_index,
            content_hash: content_hash,
            caller_crew: caller_crew,
            caller: context.caller
        });
    }
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use traits::{Into, TryInto};
    use starknet::testing;

    use influence::components;
    use influence::components::{Control, Unique};
    use influence::types::entity::EntityTrait;
    use influence::test::{helpers, mocks};

    use super::AnnotateEvent;

    #[test]
    #[available_gas(4000000)]
    fn test_annotate() {
        let transaction_hash = 0x1234567890;
        let log_index: u64 = 42;
        let mut content_hash: Array<felt252> = Default::default();
        content_hash.append('QmPjtFx2b8gx4kBEX3xZmCafmyWdfDj');
        content_hash.append('8UkNqfQGmFvtg4U');
        let crew = mocks::delegated_crew(1, 'PLAYER');
        starknet::testing::set_block_timestamp(100);
        let context = mocks::context('PLAYER');


        let mut state = AnnotateEvent::contract_state_for_testing();
        AnnotateEvent::run(ref state, transaction_hash, log_index, content_hash.span(), crew, context);

        let mut unique_key: Array<felt252> = Default::default();
        unique_key.append(transaction_hash);
        unique_key.append(log_index.into());
        unique_key.append(*content_hash.at(0));
        unique_key.append(*content_hash.at(1));
        unique_key.append(crew.into());

        let annotation_data = components::get::<Unique>(unique_key.span()).expect('annotation not set');
    }
}
