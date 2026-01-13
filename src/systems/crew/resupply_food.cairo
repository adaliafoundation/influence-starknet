#[starknet::contract]
mod ResupplyFood {
    use array::{Array, ArrayTrait, SpanTrait};
    use cmp::min;
    use option::OptionTrait;
    use starknet::contract_address::ContractAddress;
    use traits::{Into, TryInto};

    use cubit::f64::FixedTrait;
    use cubit::f64::math::comp;

    use influence::common::{inventory, position, crew::{CrewDetailsTrait, time_since_fed}};
    use influence::{components, config};
    use influence::components::{Celestial, CelestialTrait, Crew, CrewTrait, Inventory, InventoryTrait, Location,
        LocationTrait, Ship, ShipTrait,
        modifier_type::types as modifier_types,
        product_type::types as product_types};
    use influence::config::{entities, errors, permissions};
    use influence::types::context::Context;
    use influence::types::entity::{Entity, EntityIntoFelt252, EntityTrait};
    use influence::types::inventory_item::{InventoryItem, InventoryItemTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct FoodSupplied {
        food: u64,
        last_fed: u64,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[derive(Copy, Drop, starknet::Event)]
    struct FoodSuppliedV1 {
        food: u64,
        last_fed: u64,
        origin: Entity,
        origin_slot: u64,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        FoodSupplied: FoodSupplied,
        FoodSuppliedV1: FoodSuppliedV1
    }

    // Supply food to the crew
    // @param origin The origin scoped entity holding the food product
    // @param food The amount of food to supply (in kg)
    // @param crew The crew to supply food to
    #[external(v0)]
    fn run(
        ref self: ContractState,
        origin: Entity,
        origin_slot: u64,
        food: u64,
        caller_crew: Entity,
        context: Context
    ) {
        // Check that crew is delegated, and ready (allowed during emergencies)
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_all_ready(context.caller, context.now);
        let mut crew_data = crew_details.component;

        // Check permissions
        caller_crew.assert_can(origin, permissions::REMOVE_PRODUCTS);

        // Check crew location
        let (origin_ast, origin_lot) = origin.to_position();
        assert(crew_details.asteroid_id() == origin_ast, errors::DIFFERENT_ASTEROIDS);

        // Check if the crew location is same as origin, otherwise ensure there's not orbital transfer
        let location_data = components::get::<Location>(caller_crew.path()).expect(errors::LOCATION_NOT_FOUND);
        if location_data.location != origin {
            assert((crew_details.lot_id() != 0) && (origin_lot != 0), errors::IN_ORBIT);
        }

        // Get origin inventory and reduce food amount
        let mut origin_keys: Array<felt252> = Default::default();
        origin_keys.append(origin.into());
        origin_keys.append(origin_slot.into());
        let mut inv_data = components::get::<Inventory>(origin_keys.span()).expect(errors::INVENTORY_NOT_FOUND);
        let mut items: Array<InventoryItem> = Default::default();
        items.append(InventoryItemTrait::new(product_types::FOOD, food));
        inventory::remove(ref inv_data, items.span());
        components::set::<Inventory>(origin_keys.span(), inv_data);

        // Calculate new last fed time
        let num_crewmates: u64 = crew_data.roster.len().into();
        let current_food = crew_details.current_food(context.now);
        let new_food = (current_food * num_crewmates + food) / num_crewmates;
        assert(new_food <= config::get('CREWMATE_FOOD_PER_YEAR').try_into().unwrap(), errors::FOOD_LIMIT_REACHED);
        let last_fed = context.now - min(time_since_fed(new_food, crew_details.consume_mod()), context.now);

        // Calculate the crew and hopper transfer times
        let asteroid = EntityTrait::new(entities::ASTEROID, crew_details.asteroid_id());
        let celestial_data = components::get::<Celestial>(asteroid.path()).expect(errors::CELESTIAL_NOT_FOUND);

        // No efficiency penalty for food resupply
        let eff = comp::max(crew_details.bonus(modifier_types::HOPPER_TRANSPORT_TIME, context.now), FixedTrait::ONE());
        let dist_eff = crew_details.bonus(modifier_types::FREE_TRANSPORT_DISTANCE, context.now);
        let crew_to_lot = position::hopper_travel_time(
            crew_details.lot_id(), origin_lot, celestial_data.radius, eff, dist_eff
        );

        // Update the crew & ship
        crew_data.last_fed = last_fed;
        crew_data.add_busy(context.now, crew_to_lot);
        components::set::<Crew>(caller_crew.path(), crew_data);

        let (station_ship, mut station_ship_data) = crew_details.ship();
        if caller_crew != station_ship {
            station_ship_data.extend_ready(crew_data.ready_at);
            components::set::<Ship>(station_ship.path(), station_ship_data);
        }

        self.emit(FoodSuppliedV1 {
            food: food,
            last_fed: last_fed,
            origin: origin,
            origin_slot: origin_slot,
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
    use traits::Into;

    use influence::{config, components};
    use influence::common::inventory;
    use influence::components::{Control, ControlTrait, Crew, CrewTrait, Inventory, InventoryTrait, Location,
        LocationTrait, PrepaidAgreement, Station,
        modifier_type::types as modifier_types,
        product_type::types as product_types
    };
    use influence::config::entities;
    use influence::types::{Entity, EntityTrait, InventoryItem, InventoryItemTrait, InventoryContentsTrait};
    use influence::test::{helpers, mocks};

    use super::ResupplyFood;

    #[test]
    #[available_gas(25000000)]
    fn test_resupply_food() {
        helpers::init();
        mocks::constants();
        starknet::testing::set_block_timestamp(2000000); // far enough food is depleted

        let asteroid = influence::test::mocks::asteroid();
        let crew = influence::test::mocks::delegated_crew(1, 'PLAYER');
        let habitat = mocks::public_habitat(crew, 1);

        components::set::<Location>(crew.path(), LocationTrait::new(habitat));
        components::set::<Location>(habitat.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 25)));

        // Add configs
        mocks::product_type(product_types::FOOD);
        mocks::modifier_type(modifier_types::HOPPER_TRANSPORT_TIME);
        mocks::modifier_type(modifier_types::FREE_TRANSPORT_DISTANCE);

        // Setup warehouse with food
        let warehouse = mocks::public_warehouse(crew, 2);
        components::set::<Location>(warehouse.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 24)));
        let mut inv_data = components::get::<components::Inventory>(array![warehouse.into(), 2.into()].span()).unwrap();
        let mut products: Array<InventoryItem> = Default::default();
        products.append(InventoryItemTrait::new(product_types::FOOD, 1000));
        inventory::add_unchecked(ref inv_data, products.span());
        components::set::<Inventory>(array![warehouse.into(), 2.into()].span(), inv_data);

        let mut state = ResupplyFood::contract_state_for_testing();
        ResupplyFood::run(ref state, warehouse, 2, 1000, crew, mocks::context('PLAYER'));

        // Check crew
        let crew_data = components::get::<Crew>(crew.path()).unwrap();
        assert(crew_data.last_fed == 2000000, 'wrong last fed');

        // Check origin inventory
        inv_data = components::get::<Inventory>(array![warehouse.into(), 2.into()].span()).unwrap();
        assert(inv_data.contents.amount_of(product_types::FOOD) == 0, 'wrong food amount');
    }
}
