mod TheCakeIsAHalfTruth {
    use cmp::min;
    use option::OptionTrait;
    use traits::{Into, TryInto};

    use cubit::f64::{Fixed, FixedTrait};

    use influence::{components, config, contracts};
    use influence::common::crew::CrewDetails;
    use influence::components::{Crew, CrewTrait, Building, BuildingTrait,
        building_type::types as building_types};
    use influence::types::{Entity, EntityTrait};
    use influence::contracts::sway::{ISwayDispatcher, ISwayDispatcherTrait};

    const MAX_CHANCE: u64 = 3221225472; // 75%

    fn resolve(choice: u64, roll: Fixed, crew_details: CrewDetails) -> bool {
        if roll > FixedTrait::new(MAX_CHANCE * crew_details.component.action_weight / 10000, false) {
            return false;
        }

        // Make sure the target is a bioreactor
        match components::get::<Building>(crew_details.component.action_target.path()) {
            Option::Some(building_data) => {
                if building_data.building_type != building_types::BIOREACTOR {
                    return false;
                }
            },
            Option::None(_) => {
                return false;
            }
        };

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
    use influence::components::{Crew, CrewTrait, Building, BuildingTrait,
        building_type::types as building_types};
    use influence::config::entities;
    use influence::contracts::sway::{ISwayDispatcher, ISwayDispatcherTrait};
    use influence::test::helpers;
    use influence::types::{Entity, EntityTrait};

    use super::TheCakeIsAHalfTruth;

    #[test]
    #[available_gas(3000000)]
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

        // Setup target
        let target = EntityTrait::new(entities::BUILDING, 1);
        components::set::<Building>(target.path(), Building {
            status: 3,
            building_type: building_types::BIOREACTOR,
            planned_at: 1,
            finish_time: 1
        });

        let crew = EntityTrait::new(1, 1);
        let mut crew_data = CrewTrait::new(starknet::contract_address_const::<'PLAYER'>());
        crew_data.action_type = 3;
        crew_data.action_weight = 3600;
        crew_data.action_target = target;
        components::set::<Crew>(crew.path(), crew_data);
        let crew_details = CrewDetailsTrait::new(crew);

        let result = TheCakeIsAHalfTruth::resolve(1, FixedTrait::new(1, false), crew_details);
        assert(result, 'should be true');

        // Check SWAY
        let balance = sway.balance_of(starknet::contract_address_const::<'PLAYER'>());
        assert(balance == 10000 * 1000000, 'should be 10000');
    }
}
