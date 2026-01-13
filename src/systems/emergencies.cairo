mod activate_emergency;
mod collect_emergency_propellant;
mod deactivate_emergency;

use activate_emergency::ActivateEmergency;
use collect_emergency_propellant::CollectEmergencyPropellant;
use deactivate_emergency::DeactivateEmergency;

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use traits::{Into, TryInto};

    use influence::{config, components};
    use influence::common::inventory;
    use influence::components::{Control, ControlTrait, Crew, CrewTrait, Inventory, InventoryTrait, Location,
        LocationTrait, Station,
        modifier_type::types as modifier_types,
        product_type::types as product_types,
        ship::{statuses as ship_statuses, Ship, ShipTrait},
        ship_type::{types as ship_types, ShipTypeTrait}
    };
    use influence::config::entities;
    use influence::types::{Entity, EntityTrait, InventoryItem, InventoryItemTrait, InventoryContentsTrait};
    use influence::test::{helpers, mocks};

    use super::{ActivateEmergency, DeactivateEmergency, CollectEmergencyPropellant};

    #[test]
    #[available_gas(25000000)]
    fn test_activate_deactivate() {
        helpers::init();
        config::set('TIME_ACCELERATION', 24);
        starknet::testing::set_block_timestamp(1000);

        let asteroid = influence::test::mocks::asteroid();
        let crew = influence::test::mocks::delegated_crew(1, 'PLAYER');
        let ship = influence::test::mocks::controlled_light_transport(crew, 1);
        components::set::<Station>(ship.path(), Station { station_type: 1, population: 1 });

        mocks::product_type(product_types::HYDROGEN_PROPELLANT);
        mocks::modifier_type(modifier_types::INVENTORY_VOLUME_CAPACITY);

        // Deposit more than 10% propellant and some inventory items
        let prop_inv_path: Span<felt252> = array![
            ship.into(), ShipTypeTrait::by_type(ship_types::LIGHT_TRANSPORT).propellant_slot.into()
        ].span();

        let cargo_inv_path: Span<felt252> = array![
            ship.into(), ShipTypeTrait::by_type(ship_types::LIGHT_TRANSPORT).cargo_slot.into()
        ].span();

        let mut prop_inv = components::get::<Inventory>(prop_inv_path).unwrap();
        let mut cargo_inv = components::get::<Inventory>(cargo_inv_path).unwrap();

        let mut products: Array<InventoryItem> = Default::default();
        products.append(InventoryItemTrait::new(product_types::HYDROGEN_PROPELLANT, 800000));
        inventory::add_unchecked(ref prop_inv, products.span());
        components::set::<Inventory>(prop_inv_path, prop_inv);
        inventory::add_unchecked(ref cargo_inv, products.span());
        components::set::<Inventory>(cargo_inv_path, cargo_inv);

        components::set::<Location>(crew.path(), LocationTrait::new(ship));
        components::set::<Location>(ship.path(), LocationTrait::new(asteroid));

        let mut activate_state = ActivateEmergency::contract_state_for_testing();
        ActivateEmergency::run(ref activate_state, crew, mocks::context('PLAYER'));

        // Check ship and inventory
        let mut ship_data = components::get::<Ship>(ship.path()).unwrap();
        assert(ship_data.emergency_at == 1000, 'emergency not active');

        cargo_inv = components::get::<Inventory>(cargo_inv_path).unwrap();
        assert(cargo_inv.mass == 0, 'cargo not purged');

        // Deactivate
        let mut deactivate_state = DeactivateEmergency::contract_state_for_testing();
        DeactivateEmergency::run(ref deactivate_state, crew, mocks::context('PLAYER'));

        // Check ship and inventory
        ship_data = components::get::<Ship>(ship.path()).unwrap();
        assert(ship_data.emergency_at == 0, 'emergency not deactivated');

        prop_inv = components::get::<Inventory>(prop_inv_path).unwrap();
        assert(prop_inv.amount_of(product_types::HYDROGEN_PROPELLANT) == 400000, 'propellant not purged');
    }

    #[test]
    #[available_gas(20000000)]
    fn test_prop_generation() {
        helpers::init();
        mocks::constants();
        starknet::testing::set_block_timestamp(1000);

        let asteroid = mocks::asteroid();
        let crew = mocks::delegated_crew(1, 'PLAYER');
        let ship = mocks::controlled_light_transport(crew, 1);
        components::set::<Station>(ship.path(), Station { station_type: 1, population: 1 });
        components::set::<Location>(crew.path(), LocationTrait::new(ship));
        components::set::<Location>(ship.path(), LocationTrait::new(asteroid));

        mocks::product_type(product_types::HYDROGEN_PROPELLANT);
        mocks::modifier_type(modifier_types::INVENTORY_VOLUME_CAPACITY);

        // Actiate emergency and collect
        let mut activate_state = ActivateEmergency::contract_state_for_testing();
        ActivateEmergency::run(ref activate_state, crew, mocks::context('PLAYER'));

        let emergency_prop_gen_time = config::get('EMERGENCY_PROP_GEN_TIME').try_into().unwrap();
        starknet::testing::set_block_timestamp(1000 + emergency_prop_gen_time);

        let mut collect_state = CollectEmergencyPropellant::contract_state_for_testing();
        CollectEmergencyPropellant::run(ref collect_state, crew, mocks::context('PLAYER'));

        // Check prop inventory
        let prop_inv_path: Span<felt252> = array![
            ship.into(), ShipTypeTrait::by_type(ship_types::LIGHT_TRANSPORT).propellant_slot.into()
        ].span();

        let prop_inv = components::get::<Inventory>(prop_inv_path).unwrap();
        assert(prop_inv.contents.amount_of(product_types::HYDROGEN_PROPELLANT) > 0, 'propellant not generated');

        let ship_data = components::get::<Ship>(ship.path()).unwrap();
        assert(ship_data.emergency_at == 1000 + emergency_prop_gen_time, 'emergency not active');
    }
}
