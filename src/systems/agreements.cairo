mod accept_contract;
mod accept_prepaid;
mod accept_prepaid_merkle;
mod cancel_prepaid_auction;
mod cancel_prepaid;
mod configure_prepaid_auction;
mod extend_prepaid;
mod remove_from_whitelist;
mod remove_account_from_whitelist;
mod start_prepaid_auction;
mod transfer_prepaid;
mod whitelist;
mod whitelist_account;

use whitelist::Whitelist;
use remove_from_whitelist::RemoveFromWhitelist;

mod helpers {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use traits::{Into, TryInto};

    use influence::components;
    use influence::components::{PrepaidAgreementAuctionSettings, PrepaidAgreementAuctionSettingsTrait};
    use influence::config::{entities, permissions};
    use influence::types::{Entity, EntityTrait};

    const AUCTION_STEPS: u64 = 168;

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

    fn use_lot_path(lot: Entity) -> Span<felt252> {
        let mut path: Array<felt252> = Default::default();
        path.append('UseLot');
        path.append(lot.into());
        return path.span();
    }

    fn lot_use_path(lot: Entity) -> Span<felt252> {
        let mut path: Array<felt252> = Default::default();
        path.append('LotUse');
        path.append(lot.into());
        return path.span();
    }

    fn auction_settings(asteroid: Entity) -> PrepaidAgreementAuctionSettings {
        match components::get::<PrepaidAgreementAuctionSettings>(asteroid.path()) {
            Option::Some(settings) => settings,
            Option::None(_) => PrepaidAgreementAuctionSettingsTrait::defaults()
        }
    }

    fn auction_price(settings: PrepaidAgreementAuctionSettings, elapsed: u64) -> u64 {
        if elapsed < settings.initial_period {
            return settings.max_price;
        }

        let descending_elapsed = elapsed - settings.initial_period;
        if descending_elapsed >= settings.descending_period {
            return settings.min_price;
        }

        let step = (descending_elapsed * AUCTION_STEPS) / settings.descending_period;
        if step >= AUCTION_STEPS {
            return settings.min_price;
        }

        if step == 0 {
            return settings.max_price;
        }

        let steps = AUCTION_STEPS - 1;
        let delta = settings.max_price - settings.min_price;
        let reduction = (delta / steps) * step + ((delta % steps) * step) / steps;
        return settings.max_price - reduction;
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
