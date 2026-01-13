#[starknet::contract]
mod ResupplyFoodFromExchange {
    use array::{ArrayTrait, SpanTrait};
    use cmp::min;
    use option::OptionTrait;
    use starknet::contract_address::ContractAddress;
    use traits::{Into, TryInto};

    use cubit::f64::{Fixed, FixedTrait, ONE};
    use cubit::f64::math::comp;

    use influence::{components, config, contracts};
    use influence::common::{inventory, position, crew::{CrewDetailsTrait, time_since_fed}, math::RoundedDivTrait};
    use influence::components::{Celestial, Control, Crew, CrewTrait, Exchange, Location,
        LocationTrait, Inventory, Ship, ShipTrait,
        building::{statuses as building_statuses, Building, BuildingTrait},
        modifier_type::types as modifier_types,
        product_type::types as product_types,
        delivery::{statuses as delivery_statuses, Delivery},
        order::{statuses as order_statuses, types as order_types, Order}};
    use influence::config::{entities, errors, permissions};
    use influence::contracts::sway::{ISwayDispatcher, ISwayDispatcherTrait};
    use influence::entities::next_id;
    use influence::systems::orders::helpers::{required_payments, order_path};
    use influence::types::{Context, Entity, EntityTrait, InventoryItem, InventoryItemTrait,
        SpanHashTrait, SpanTraitExt};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct SellOrderFilled {
        seller_crew: Entity,
        exchange: Entity,
        product: u64,
        amount: u64,
        price: u64,
        storage: Entity,
        storage_slot: u64,
        destination: Entity,
        destination_slot: u64,
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
        SellOrderFilled: SellOrderFilled,
        FoodSuppliedV1: FoodSuppliedV1
    }

    #[external(v0)]
    fn run(
        ref self: ContractState,
        seller_crew: Entity,
        exchange: Entity,
        amount: u64,
        price: u64,
        storage: Entity,
        storage_slot: u64,
        caller_crew: Entity,
        context: Context
    ) {
        // Check that crew is delegated, and ready
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_all_ready(context.caller, context.now);
        let mut crew_data = crew_details.component;
        caller_crew.assert_can(exchange, permissions::BUY);

        // Get the order data and validate
        let product = product_types::FOOD;
        let order_path = order_path(
            seller_crew, exchange, order_types::LIMIT_SELL, product, price, storage, storage_slot
        );

        let mut order_data = components::get::<Order>(order_path).expect(errors::ORDER_NOT_FOUND);
        assert(order_data.status == order_statuses::OPEN, errors::INCORRECT_STATUS);
        assert(order_data.amount >= amount, errors::INSUFFICIENT_AMOUNT);

        // Check that the exchange is ready
        let product_item = InventoryItemTrait::new(product, amount);
        components::get::<Building>(exchange.path()).expect(errors::BUILDING_NOT_FOUND).assert_operational();
        let mut exchange_data = components::get::<Exchange>(exchange.path()).expect(errors::EXCHANGE_NOT_FOUND);
        let (exchange_ast, exchange_lot) = exchange.to_position();

        // Check crew location and ensure no orbital transfer
        assert(crew_details.asteroid_id() == exchange_ast, errors::DIFFERENT_ASTEROIDS);
        assert((crew_details.lot_id() != 0) && (exchange_lot != 0), errors::IN_ORBIT);

        // Collect crew modifiers and calculate fees
        let taker_eff = crew_details.bonus(modifier_types::MARKETPLACE_FEE_REDUCTION, context.now);
        let market_crew = components::get::<Control>(exchange.path()).expect(errors::CONTROL_NOT_FOUND).controller;
        let mut market_crew_details = CrewDetailsTrait::new(market_crew);
        let mut market_crew_data = market_crew_details.component;
        let enforce_eff = market_crew_details.bonus(modifier_types::MARKETPLACE_FEE_ENFORCEMENT, context.now);
        let (to_marketplace, to_seller) = required_payments(
            amount * price, order_data.maker_fee, exchange_data.taker_fee, taker_eff, enforce_eff
        );

        // Confirm receipt on SWAY contract for payment to seller
        let mut seller_crew_details = CrewDetailsTrait::new(seller_crew);
        let mut seller_crew_data = seller_crew_details.component;

        ISwayDispatcher { contract_address: contracts::get('Sway') }.confirm_receipt(
            context.caller, seller_crew_data.delegated_to, to_seller.into(), order_path.hash()
        );

        // Confirm receipt on SWAY contract for fee to marketplace
        ISwayDispatcher { contract_address: contracts::get('Sway') }.confirm_receipt(
            context.caller, market_crew_data.delegated_to, to_marketplace.into(), order_path.hash()
        );

        // Reduce order amount and status if necessary
        if amount == order_data.amount {
            order_data.amount = 0;
            order_data.status = order_statuses::FILLED;
            exchange_data.orders -= 1;
            components::set::<Order>(order_path, order_data);
            components::set::<Exchange>(exchange.path(), exchange_data);
        } else {
            order_data.amount -= amount;
            components::set::<Order>(order_path, order_data);
        }

        // Reduce reservation on origin inventory
        let mut origin_path: Array<felt252> = Default::default();
        origin_path.append(storage.into());
        origin_path.append(storage_slot.into());

        let mut origin_data = components::get::<Inventory>(origin_path.span()).expect(errors::INVENTORY_NOT_FOUND);
        let mut products: Array<InventoryItem> = Default::default();
        products.append(product_item);
        inventory::unreserve(ref origin_data, products.span());
        components::set::<Inventory>(origin_path.span(), origin_data);

        // Calculate new last fed time
        let num_crewmates: u64 = crew_data.roster.len().into();
        let current_food = crew_details.current_food(context.now);
        let new_food = (current_food * num_crewmates + amount) / num_crewmates;
        assert(new_food <= config::get('CREWMATE_FOOD_PER_YEAR').try_into().unwrap(), errors::FOOD_LIMIT_REACHED);
        let last_fed = context.now - min(time_since_fed(new_food, crew_details.consume_mod()), context.now);

        // Calculate the crew and hopper transfer times
        let asteroid = EntityTrait::new(entities::ASTEROID, crew_details.asteroid_id());
        let celestial_data = components::get::<Celestial>(asteroid.path()).expect(errors::CELESTIAL_NOT_FOUND);

        // No efficiency penalty for food resupply
        let eff = comp::max(crew_details.bonus(modifier_types::HOPPER_TRANSPORT_TIME, context.now), FixedTrait::ONE());
        let dist_eff = crew_details.bonus(modifier_types::FREE_TRANSPORT_DISTANCE, context.now);
        let crew_to_lot = position::hopper_travel_time(
            crew_details.lot_id(), exchange_lot, celestial_data.radius, eff, dist_eff
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

        self.emit(SellOrderFilled {
            seller_crew: seller_crew,
            exchange: exchange,
            product: product,
            amount: amount,
            price: price,
            storage: storage,
            storage_slot: storage_slot,
            destination: caller_crew,
            destination_slot: 0,
            caller_crew: caller_crew,
            caller: context.caller
        });

        self.emit(FoodSuppliedV1 {
            food: amount,
            last_fed: last_fed,
            origin: exchange,
            origin_slot: 0,
            caller_crew: caller_crew,
            caller: context.caller
        });
    }
}

// Tests --------------------------------------------------------------------------------------------------------------

use influence::types::{Context, Entity};

#[starknet::interface]
trait IResupplyFoodFromExchange<TContractState> {
    fn run(
        ref self: TContractState,
        seller_crew: Entity,
        exchange: Entity,
        amount: u64,
        price: u64,
        storage: Entity,
        storage_slot: u64,
        caller_crew: Entity,
        context: Context
    );
}

#[cfg(test)]
mod tests {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use traits::{Into, TryInto};
    use result::ResultTrait;
    use starknet::{deploy_syscall, ClassHash};

    use cubit::f64::{Fixed, FixedTrait, ONE, HALF};
    use cubit::f64::test::helpers::assert_relative;

    use influence::{config, components, contracts};
    use influence::common::inventory;
    use influence::components::{Control, ControlTrait, Crew, CrewTrait, Inventory, InventoryTrait, Location,
        LocationTrait,
        modifier_type::types as modifier_types,
        product_type::types as product_types,
        order::{statuses as order_statuses, types as order_types, Order}};
    use influence::config::entities;
    use influence::contracts::sway::{Sway, ISwayDispatcher, ISwayDispatcherTrait};
    use influence::systems::orders::helpers::{order_path};
    use influence::types::{EntityTrait, InventoryItem, InventoryItemTrait, SpanHashTrait};
    use influence::test::{helpers, mocks};

    use super::{
        ResupplyFoodFromExchange,
        IResupplyFoodFromExchangeLibraryDispatcher,
        IResupplyFoodFromExchangeDispatcherTrait
    };

    #[test]
    #[available_gas(41000000)]
    fn test_resupply_from_exchange() {
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        helpers::init();
        mocks::constants();
        starknet::testing::set_block_timestamp(2000000); // far enough food is depleted

        // Deploy SWAY
        let sway_address = helpers::deploy_sway();
        let amount: u256 = (100 * 2000000).into();
        starknet::testing::set_contract_address(starknet::contract_address_const::<'ADMIN'>());
        ISwayDispatcher { contract_address: sway_address }.mint(starknet::contract_address_const::<'PLAYER'>(), amount);
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());

        // Create entities
        let asteroid = influence::test::mocks::asteroid();
        let crew = influence::test::mocks::delegated_crew(1, 'PLAYER');
        let seller_crew = influence::test::mocks::delegated_crew(2, 'SELLER');
        let market_crew = influence::test::mocks::delegated_crew(3, 'MARKET');

        // Setup configs
        mocks::product_type(product_types::FOOD);
        mocks::modifier_type(modifier_types::HOPPER_TRANSPORT_TIME);
        mocks::modifier_type(modifier_types::FREE_TRANSPORT_DISTANCE);
        mocks::modifier_type(modifier_types::MARKETPLACE_FEE_REDUCTION);
        mocks::modifier_type(modifier_types::MARKETPLACE_FEE_ENFORCEMENT);

        // Setup station
        let station = influence::test::mocks::public_habitat(market_crew, 1);
        components::set::<Location>(station.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1)));
        components::set::<Location>(crew.path(), LocationTrait::new(station));
        components::set::<Location>(seller_crew.path(), LocationTrait::new(station));
        components::set::<Location>(market_crew.path(), LocationTrait::new(station));

        // Setup marketplace
        let market = influence::test::mocks::public_marketplace(market_crew, 2);
        components::set::<Location>(market.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 500)));
        components::set::<Control>(market.path(), ControlTrait::new(market_crew));

        // Setup warehouse
        let warehouse = influence::test::mocks::public_warehouse(crew, 3);
        components::set::<Location>(warehouse.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1000)));
        components::set::<Control>(warehouse.path(), ControlTrait::new(crew));
        let inventory_path = array![warehouse.into(), 2].span();
        let mut inventory_data = components::get::<Inventory>(inventory_path).unwrap();
        let supplies = array![InventoryItemTrait::new(product_types::FOOD, 1000)].span();
        inventory::reserve(ref inventory_data, supplies, FixedTrait::ONE(), FixedTrait::ONE());
        components::set::<Inventory>(inventory_path, inventory_data);

        // Setup order
        let order_path = order_path(
            seller_crew, market, order_types::LIMIT_SELL, product_types::FOOD, 100000, warehouse, 2
        );

        components::set::<Order>(order_path, Order {
            status: order_statuses::OPEN,
            amount: 2000,
            valid_time: 0,
            maker_fee: 100
        });

        components::set::<Control>(order_path, ControlTrait::new(seller_crew));

        // Send payments
        starknet::testing::set_contract_address(starknet::contract_address_const::<'PLAYER'>());
        ISwayDispatcher { contract_address: sway_address }.transfer_with_confirmation(
            starknet::contract_address_const::<'SELLER'>(),
            99000000,
            order_path.hash(),
            starknet::contract_address_const::<'DISPATCHER'>()
        );

        ISwayDispatcher { contract_address: sway_address }.transfer_with_confirmation(
            starknet::contract_address_const::<'MARKET'>(),
            7670000,
            order_path.hash(),
            starknet::contract_address_const::<'DISPATCHER'>()
        );

        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        let class_hash: ClassHash = ResupplyFoodFromExchange::TEST_CLASS_HASH.try_into().unwrap();
        IResupplyFoodFromExchangeLibraryDispatcher { class_hash: class_hash }.run(
            seller_crew: seller_crew,
            exchange: market,
            amount: 1000,
            price: 100000,
            storage: warehouse,
            storage_slot: 2,
            caller_crew: crew,
            context: mocks::context('PLAYER')
        );

        // Check order
        let order_data = components::get::<Order>(order_path).unwrap();
        assert(order_data.amount == 1000, 'wrong order amount');

         // Check crew
        let crew_data = components::get::<Crew>(crew.path()).unwrap();
        assert(crew_data.last_fed == 2000000, 'wrong last fed');
    }
}
