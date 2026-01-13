mod AlwaysLeaveANote {
    use cmp::min;
    use option::OptionTrait;
    use traits::{Into, TryInto};

    use cubit::f64::{Fixed, FixedTrait};

    use influence::{config, contracts};
    use influence::common::crew::{CrewDetails, CrewDetailsTrait};
    use influence::components::{Crew, CrewTrait};
    use influence::config::entities;
    use influence::contracts::sway::{ISwayDispatcher, ISwayDispatcherTrait};
    use influence::types::{Entity, EntityTrait};

    const MAX_CHANCE: u64 = 3221225472; // 75%

    fn resolve(choice: u64, roll: Fixed, mut crew_details: CrewDetails) -> bool {
        if roll > FixedTrait::new(MAX_CHANCE * crew_details.component.action_weight / 10000, false) {
            return false;
        }

        // Make sure transit is non-emergency and away from Adalia Prime
        let (_, ship_data) = crew_details.ship();
        let adalia_prime = EntityTrait::new(entities::ASTEROID, 1);

        if ship_data.emergency_at != 0 || ship_data.transit_origin != adalia_prime {
            return false;
        }

        // Calculate the amount of SWAY to send
        let sway = ISwayDispatcher { contract_address: contracts::get('Sway') };
        let balance: u128 = sway.balance_of(starknet::info::get_contract_address()).try_into().unwrap();
        let amount = min(config::get('EVENT_SWAY').try_into().unwrap(), balance / 1000);

        // Send SWAY to the crew delegate
        if amount > 0 && choice == 1 {
            sway.transfer(crew_details.component.delegated_to, amount.into());
            return true;
        }

        return true;
    }
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use traits::Into;
    use cubit::f64::FixedTrait;

    use influence::{components, config};
    use influence::common::crew::CrewDetailsTrait;
    use influence::components::{Crew, CrewTrait, Location, LocationTrait, Ship, ShipTrait};
    use influence::config::entities;
    use influence::contracts::sway::{ISwayDispatcher, ISwayDispatcherTrait};
    use influence::test::helpers;
    use influence::types::{Entity, EntityTrait};

    use super::AlwaysLeaveANote;

    #[test]
    #[available_gas(5000000)]
    fn test_event() {
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        config::set('EVENT_SWAY', 10000000000);

        // Deploy SWAY
        let sway_address = helpers::deploy_sway();
        let amount: u256 = 100000000 * 1000000;
        starknet::testing::set_contract_address(starknet::contract_address_const::<'ADMIN'>());
        let sway = ISwayDispatcher { contract_address: sway_address };
        sway.mint(starknet::contract_address_const::<'DISPATCHER'>(), amount);
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());

        // Setup ship
        let ship = EntityTrait::new(entities::SHIP, 1);
        components::set::<Ship>(ship.path(), Ship {
            ship_type: 2,
            status: 1,
            ready_at: 0,
            emergency_at: 0,
            variant: 1,
            transit_origin: EntityTrait::new(entities::ASTEROID, 1),
            transit_departure: 1,
            transit_destination: EntityTrait::new(entities::ASTEROID, 2),
            transit_arrival: 2
        });

        let crew = EntityTrait::new(1, 1);
        let mut crew_data = CrewTrait::new(starknet::contract_address_const::<'PLAYER'>());
        crew_data.action_type = 5;
        crew_data.action_weight = 3600;
        components::set::<Crew>(crew.path(), crew_data);

        components::set::<Location>(crew.path(), LocationTrait::new(ship));
        components::set::<Location>(ship.path(), LocationTrait::new(EntityTrait::new(entities::SPACE, 1)));

        let crew_details = CrewDetailsTrait::new(crew);

        let result = AlwaysLeaveANote::resolve(1, FixedTrait::new(1, false), crew_details);
        assert(result, 'should be true');

        let balance = sway.balance_of(starknet::contract_address_const::<'PLAYER'>());
        assert(balance == 10000 * 1000000, 'should be 10000');
    }
}
