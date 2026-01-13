mod accept;
mod cancel;
mod dump;
mod package;
mod receive;
mod send;

use accept::AcceptDelivery;
use cancel::CancelDelivery;
use dump::DumpDelivery;
use package::PackageDelivery;
use receive::ReceiveDelivery;
use send::SendDelivery;

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use traits::Into;

    use influence::{components, config};
    use influence::common::inventory;
    use influence::components::{Crew, CrewTrait, Delivery, Location, LocationTrait, Inventory, InventoryTrait,
        building_type::{types as buildings, BuildingType},
        modifier_type::types as modifier_types,
        product_type::types as product_types,
        crewmate::{classes, departments, crewmate_traits}};
    use influence::config::entities;
    use influence::test::{helpers, mocks};
    use influence::types::{Entity, EntityTrait, InventoryItem, InventoryItemTrait};

    use super::{AcceptDelivery, CancelDelivery, DumpDelivery, PackageDelivery, ReceiveDelivery, SendDelivery};

    fn add_modifiers() {
        mocks::modifier_type(modifier_types::INVENTORY_MASS_CAPACITY);
        mocks::modifier_type(modifier_types::INVENTORY_VOLUME_CAPACITY);
        mocks::modifier_type(modifier_types::HOPPER_TRANSPORT_TIME);
        mocks::modifier_type(modifier_types::FREE_TRANSPORT_DISTANCE);
    }

    #[test]
    #[available_gas(30000000)]
    fn test_send_delivery() {
        helpers::init();
        mocks::constants();
        add_modifiers();

        let asteroid = influence::test::mocks::asteroid();
        let crew = influence::test::mocks::delegated_crew(1, 'PLAYER');

        // Setup station
        let station = influence::test::mocks::public_habitat(crew, 1);
        components::set::<Location>(station.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1)));
        components::set::<Location>(crew.path(), LocationTrait::new(station));

        // Setup warehouse 1
        let warehouse1 = influence::test::mocks::public_warehouse(crew, 3);
        components::set::<Location>(
            warehouse1.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1000))
        );

        // Setup product
        mocks::product_type(product_types::WATER);

        let inventory_path = array![warehouse1.into(), 2].span();
        let mut inventory_data = components::get::<Inventory>(inventory_path).unwrap();
        let supplies = array![InventoryItemTrait::new(product_types::WATER, 1000)].span();
        inventory::add_unchecked(ref inventory_data, supplies);
        components::set::<Inventory>(inventory_path, inventory_data);

        // Setup warehouse 2
        let warehouse2 = influence::test::mocks::public_warehouse(crew, 4);
        components::set::<Location>(
            warehouse2.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1000))
        );

        let mut state = SendDelivery::contract_state_for_testing();
        let mut products: Array<InventoryItem> = Default::default();
        products.append(InventoryItemTrait::new(product_types::WATER, 1000));

        SendDelivery::run(
            ref state,
            origin: warehouse1,
            origin_slot: 2,
            products: products.span(),
            dest: warehouse2,
            dest_slot: 2,
            caller_crew: crew,
            context: mocks::context('PLAYER')
        );

        let delivery_data = components::get::<Delivery>(EntityTrait::new(entities::DELIVERY, 1).path()).unwrap();
        assert(delivery_data.status == 4, 'delivery not started');
        assert(delivery_data.origin == warehouse1, 'origin not set');
        assert(delivery_data.origin_slot == 2, 'origin slot not set');
        assert(delivery_data.dest == warehouse2, 'dest not set');
        assert(delivery_data.dest_slot == 2, 'dest slot not set');
    }

    #[test]
    #[available_gas(35000000)]
    fn test_receive_delivery() {
        helpers::init();
        mocks::constants();
        add_modifiers();

        let asteroid = influence::test::mocks::asteroid();
        let crew = influence::test::mocks::delegated_crew(1, 'PLAYER');

        // Setup station
        let station = influence::test::mocks::public_habitat(crew, 1);
        components::set::<Location>(station.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1)));
        components::set::<Location>(crew.path(), LocationTrait::new(station));

        // Setup product
        mocks::product_type(product_types::WATER);

        // Setup warehouse 1
        let warehouse1 = influence::test::mocks::public_warehouse(crew, 3);
        components::set::<Location>(
            warehouse1.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1000))
        );

        let inventory_path = array![warehouse1.into(), 2].span();
        let mut inventory_data = components::get::<Inventory>(inventory_path).unwrap();
        let supplies = array![InventoryItemTrait::new(product_types::WATER, 1000)].span();
        inventory::add_unchecked(ref inventory_data, supplies);
        components::set::<Inventory>(inventory_path, inventory_data);

        // Setup warehouse 2
        let warehouse2 = influence::test::mocks::public_warehouse(crew, 4);
        components::set::<Location>(
            warehouse2.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1000))
        );

        let mut start_state = SendDelivery::contract_state_for_testing();
        let mut products: Array<InventoryItem> = Default::default();
        products.append(InventoryItemTrait::new(product_types::WATER, 1000));

        SendDelivery::run(
            ref start_state,
            origin: warehouse1,
            origin_slot: 2,
            products: products.span(),
            dest: warehouse2,
            dest_slot: 2,
            caller_crew: crew,
            context: mocks::context('PLAYER')
        );

        let mut finish_state = ReceiveDelivery::contract_state_for_testing();
        ReceiveDelivery::run(
            ref finish_state,
            delivery: EntityTrait::new(entities::DELIVERY, 1),
            caller_crew: crew,
            context: mocks::context('PLAYER')
        );

        let warehouse1_data = components::get::<Inventory>(array![warehouse1.into(), 2].span()).unwrap();
        assert(warehouse1_data.mass == 0, 'wrong mass');
        assert(warehouse1_data.volume == 0, 'wrong volume 0');

        let warehouse2_data = components::get::<Inventory>(array![warehouse2.into(), 2].span()).unwrap();
        assert(warehouse2_data.mass == 1000000, 'wrong mass');
        assert(warehouse2_data.volume == 971000, 'wrong volume');
    }

    #[test]
    #[available_gas(45000000)]
    fn test_cancel_delivery() {
        helpers::init();
        mocks::constants();
        add_modifiers();

        let asteroid = influence::test::mocks::asteroid();
        let crew = influence::test::mocks::delegated_crew(1, 'PLAYER');

        // Setup station
        let station = influence::test::mocks::public_habitat(crew, 1);
        components::set::<Location>(station.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1)));
        components::set::<Location>(crew.path(), LocationTrait::new(station));

        // Setup product
        mocks::product_type(product_types::WATER);

        // Setup warehouse 1
        let warehouse1 = influence::test::mocks::public_warehouse(crew, 3);
        components::set::<Location>(
            warehouse1.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1000))
        );

        let inventory_path = array![warehouse1.into(), 2].span();
        let mut inventory_data = components::get::<Inventory>(inventory_path).unwrap();
        let supplies = array![InventoryItemTrait::new(product_types::WATER, 1000)].span();
        inventory::add_unchecked(ref inventory_data, supplies);
        components::set::<Inventory>(inventory_path, inventory_data);

        // Setup warehouse 2
        let warehouse2 = influence::test::mocks::public_warehouse(crew, 4);
        components::set::<Location>(
            warehouse2.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1000))
        );

        let mut start_state = SendDelivery::contract_state_for_testing();
        let mut products: Array<InventoryItem> = Default::default();
        products.append(InventoryItemTrait::new(product_types::WATER, 1000));

        SendDelivery::run(
            ref start_state,
            origin: warehouse1,
            origin_slot: 2,
            products: products.span(),
            dest: warehouse2,
            dest_slot: 2,
            caller_crew: crew,
            context: mocks::context('PLAYER')
        );

        let mut cancel_state = CancelDelivery::contract_state_for_testing();
        CancelDelivery::run(
            ref cancel_state,
            delivery: EntityTrait::new(entities::DELIVERY, 1),
            caller_crew: crew,
            context: mocks::context('PLAYER')
        );

        let warehouse1_data = components::get::<Inventory>(array![warehouse1.into(), 2].span()).unwrap();
        assert(warehouse1_data.mass == 1000000, 'wrong mass');
        assert(warehouse1_data.volume == 971000, 'wrong volume 0');

        let warehouse2_data = components::get::<Inventory>(array![warehouse2.into(), 2].span()).unwrap();
        assert(warehouse2_data.mass == 0, 'wrong mass');
        assert(warehouse2_data.volume == 0, 'wrong volume');
    }

    #[test]
    #[available_gas(30000000)]
    fn test_dump_delivery() {
        helpers::init();
        mocks::constants();
        add_modifiers();

        let asteroid = influence::test::mocks::asteroid();
        let crew = influence::test::mocks::delegated_crew(1, 'PLAYER');

        // Setup station
        let station = influence::test::mocks::public_habitat(crew, 1);
        components::set::<Location>(station.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1)));
        components::set::<Location>(crew.path(), LocationTrait::new(station));

        // Setup warehouse 1
        let warehouse1 = influence::test::mocks::public_warehouse(crew, 3);
        components::set::<Location>(
            warehouse1.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1000))
        );

        // Setup product
        mocks::product_type(product_types::WATER);

        let inventory_path = array![warehouse1.into(), 2].span();
        let mut inventory_data = components::get::<Inventory>(inventory_path).unwrap();
        let supplies = array![InventoryItemTrait::new(product_types::WATER, 1000)].span();
        inventory::add_unchecked(ref inventory_data, supplies);
        components::set::<Inventory>(inventory_path, inventory_data);

        let mut state = DumpDelivery::contract_state_for_testing();
        let mut products: Array<InventoryItem> = Default::default();
        products.append(InventoryItemTrait::new(product_types::WATER, 1000));

        DumpDelivery::run(
            ref state,
            origin: warehouse1,
            origin_slot: 2,
            products: products.span(),
            caller_crew: crew,
            context: mocks::context('PLAYER')
        );

        // Check that the inventory is empty
        let inventory_data = components::get::<Inventory>(inventory_path).unwrap();
        assert(inventory_data.mass == 0, 'wrong mass');
        assert(inventory_data.volume == 0, 'wrong volume');
    }
}
