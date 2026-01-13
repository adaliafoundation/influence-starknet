mod accept_contract;
mod accept_prepaid;
mod accept_prepaid_merkle;
mod cancel_prepaid;
mod extend_prepaid;
mod remove_from_whitelist;
mod remove_account_from_whitelist;
mod transfer_prepaid;
mod whitelist;
mod whitelist_account;

use whitelist::Whitelist;
use remove_from_whitelist::RemoveFromWhitelist;

mod helpers {
    use array::{ArrayTrait, SpanTrait};
    use traits::Into;

    use influence::config::{entities, permissions};
    use influence::types::Entity;

    fn agreement_path(target: Entity, permission: u64, permitted: felt252) -> Span<felt252> {
        if target.label == entities::ASTEROID {
            assert(permission == permissions::USE_LOT, 'invalid permission');
        } else if target.label == entities::LOT {
            assert(permission == permissions::USE_LOT, 'invalid permission');
        } else if target.label == entities::BUILDING {
            assert(
                permission == permissions::RUN_PROCESS ||
                permission == permissions::ADD_PRODUCTS ||
                permission == permissions::REMOVE_PRODUCTS ||
                permission == permissions::STATION_CREW ||
                permission == permissions::RECRUIT_CREWMATE ||
                permission == permissions::DOCK_SHIP ||
                permission == permissions::BUY ||
                permission == permissions::SELL ||
                permission == permissions::LIMIT_BUY ||
                permission == permissions::LIMIT_SELL ||
                permission == permissions::EXTRACT_RESOURCES ||
                permission == permissions::ASSEMBLE_SHIP,
                'invalid permission'
            );
        } else if target.label == entities::SHIP {
            assert(
                permission == permissions::ADD_PRODUCTS ||
                permission == permissions::REMOVE_PRODUCTS ||
                permission == permissions::STATION_CREW,
                'invalid permission'
            );
        } else {
            assert(false, 'invalid permission');
        }

        let mut path: Array<felt252> = Default::default();
        path.append(target.into());
        path.append(permission.into());
        path.append(permitted);
        return path.span();
    }
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use array::{Array, ArrayTrait, SpanTrait};
    use clone::Clone;
    use option::OptionTrait;
    use traits::Into;

    use influence::config::{entities, permissions};
    use influence::components;
    use influence::components::{Control, ControlTrait, Crew, CrewTrait, Location, LocationTrait,
        WhitelistAgreement, WhitelistAgreementTrait};
    use influence::types::{Context, Entity, EntityTrait};
    use influence::test::{helpers, mocks};

    use super::{helpers::agreement_path, RemoveFromWhitelist, Whitelist};

    #[test]
    #[available_gas(10000000)]
    fn test_grant_permission() {
        let asteroid = mocks::asteroid();
        let entity = EntityTrait::new(entities::BUILDING, 1);
        let permission = permissions::STATION_CREW;
        let crew = mocks::delegated_crew(2, 'PLAYER2');
        let caller_crew = mocks::delegated_crew(3, 'PLAYER');

        // Set controller and location
        components::set::<Control>(entity.path(), ControlTrait::new(caller_crew));
        components::set::<Location>(caller_crew.path(), LocationTrait::new(asteroid));
        components::set::<Location>(entity.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1)));

        let mut state = Whitelist::contract_state_for_testing();
        Whitelist::run(ref state, entity, permission, crew, caller_crew, mocks::context('PLAYER'));

        let agreement = components::get::<WhitelistAgreement>(agreement_path(entity, permission, crew.into()));
        assert(agreement.is_some(), 'agreement not set');
    }

    #[test]
    #[available_gas(10000000)]
    fn test_revoke_permission() {
        let asteroid = mocks::asteroid();
        let entity = EntityTrait::new(entities::BUILDING, 1);
        let permission = permissions::STATION_CREW;
        let crew = mocks::delegated_crew(2, 'PLAYER2');
        let caller_crew = mocks::delegated_crew(3, 'PLAYER');

        // Delegate and set caller to owner
        components::set::<Control>(entity.path(), ControlTrait::new(caller_crew));
        components::set::<Location>(caller_crew.path(), LocationTrait::new(asteroid));
        components::set::<Location>(entity.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1)));

        let mut state = Whitelist::contract_state_for_testing();
        Whitelist::run(ref state, entity, permission, crew, caller_crew, mocks::context('PLAYER'));
        let mut state = RemoveFromWhitelist::contract_state_for_testing();
        RemoveFromWhitelist::run(ref state, entity, permission, crew, caller_crew, mocks::context('PLAYER'));

        let agreement = components::get::<WhitelistAgreement>(agreement_path(entity, permission, crew.into()));
        assert(agreement.is_none(), 'agreement set');
    }
}
