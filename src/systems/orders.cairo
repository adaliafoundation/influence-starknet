mod cancel_sell;
mod create_buy;
mod create_sell;
mod fill_buy;
mod fill_sell;

use cancel_sell::CancelSellOrder;
use create_buy::CreateBuyOrder;
use create_sell::CreateSellOrder;
use fill_buy::FillBuyOrder;
use fill_sell::FillSellOrder;

mod helpers {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use traits::{Into, TryInto};

    use cubit::f64::{Fixed, FixedTrait, ONE};

    use influence::common::math::RoundedDivTrait;
    use influence::components::order::types as order_types;
    use influence::types::Entity;

    fn order_path(
        crew: Entity,
        exchange: Entity,
        order_type: u64,
        product: u64,
        price: u64,
        storage: Entity,
        storage_slot: u64
    ) -> Span<felt252> {
        let mut path: Array<felt252> = Default::default();
        path.append(crew.into());
        path.append(exchange.into());
        path.append(order_type.into());
        path.append(product.into());
        path.append(price.into());
        path.append(storage.into());
        path.append(storage_slot.into());
        return path.span();
    }

    // Calculates the required deposit for a limit buy order
    // Returns (deposit, adjusted_maker_fee)
    fn required_deposit(value: u64, maker_fee: u64, maker_eff: Fixed, enforce_eff: Fixed) -> (u64, u64) {
        let adjusted_maker_fee = adjusted_fee(maker_fee, maker_eff, enforce_eff);
        let maker_fees = (value * adjusted_maker_fee) / 10000;
        return (value + maker_fees, adjusted_maker_fee);
    }

    // Calculates the required withdrawals to player and exchange for filling a limit buy order (market sell)
    fn required_withdrawals(
        value: u64,
        maker_fee: u64,
        taker_fee: u64,
        taker_eff: Fixed,
        enforce_eff: Fixed
    ) -> (u64, u64) {
        let maker_fees = (value * maker_fee) / 10000;
        let taker_fees = (value * adjusted_fee(taker_fee, taker_eff, enforce_eff)) / 10000;

        // When filling a limit buy (i.e. market selling), the amount to the seller should be
        // reduced by the taker fee
        return (maker_fees + taker_fees, value - taker_fees);
    }

    // Calculates the required payments to player and exchange for filling a limit sell order (market buy)
    fn required_payments(
        value: u64,
        maker_fee: u64,
        taker_fee: u64,
        taker_eff: Fixed,
        enforce_eff: Fixed
    ) -> (u64, u64) {
        let maker_fees = (value * maker_fee) / 10000;
        let taker_fees = (value * adjusted_fee(taker_fee, taker_eff, enforce_eff)) / 10000;

        // When filling a limit sell (i.e. market buying), the amount to the seller should be
        // reduced by the maker fee
        return (maker_fees + taker_fees, value - maker_fees);
    }

    fn adjusted_fee(fee: u64, eff: Fixed, enforce_eff: Fixed) -> u64 {
        return (ONE.into() * fee.into()).div_round(net_eff(eff, enforce_eff).mag);
    }

    fn net_eff(eff: Fixed, enforce_eff: Fixed) -> Fixed {
        let one = FixedTrait::ONE();

        if eff > one && enforce_eff > one {
            return eff - ((eff - one) * (enforce_eff - one));
        } else {
            return eff;
        }
    }
}

#[cfg(test)]
mod tests {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use traits::{Into, TryInto};

    use cubit::f64::{Fixed, FixedTrait, ONE, HALF};
    use cubit::f64::test::helpers::assert_relative;

    use influence::{config, components};
    use influence::common::inventory;
    use influence::components::{Inventory, InventoryTrait, Location, LocationTrait,
        modifier_type::types as modifier_types,
        product_type::types as product_types,
        crewmate::{classes, crewmate_traits, departments},
        delivery::{statuses as delivery_statuses, Delivery},
        order::{statuses as order_statuses, types as order_types, Order}};
    use influence::config::entities;
    use influence::types::{EntityTrait, InventoryItem, InventoryItemTrait};
    use influence::test::{helpers, mocks};

    use super::{CreateSellOrder, CancelSellOrder, helpers::{adjusted_fee, required_deposit, required_payments,
        required_withdrawals, net_eff}};

    #[test]
    #[available_gas(300000)]
    fn test_net_eff() {
        let mut eff = FixedTrait::new(6442450944, false); // 1.5
        let mut enforce_eff = FixedTrait::new(7730941132, false); // 1.8
        assert_relative(net_eff(eff, enforce_eff), 4724464025, 'eff should be 1.1', Option::None(()));

        eff = FixedTrait::new(6442450944, false); // 1.5
        enforce_eff = FixedTrait::ONE();
        assert_relative(net_eff(eff, enforce_eff), 6442450944, 'eff should be 1.5', Option::None(()));

        eff = FixedTrait::new(HALF, false);
        enforce_eff = FixedTrait::new(7730941132, false); // 1.8
        assert_relative(net_eff(eff, enforce_eff), HALF.into(), 'eff should be 0.5', Option::None(()));
    }

    #[test]
    #[available_gas(300000)]
    fn test_adjusted_fee() {
        assert(adjusted_fee(200, FixedTrait::ONE(), FixedTrait::ONE()) == 200, 'wrong fee');
        assert(adjusted_fee(200, FixedTrait::ONE(), FixedTrait::new(6442450944, false)) == 200, 'wrong fee');
        assert(adjusted_fee(200, FixedTrait::new(6442450944, false), FixedTrait::ONE()) == 133, 'wrong fee');
        assert(adjusted_fee(200, FixedTrait::ONE(), FixedTrait::new(2147483648, false)) == 200, 'wrong fee');
        assert(adjusted_fee(200, FixedTrait::new(2147483648, false), FixedTrait::ONE()) == 400, 'wrong fee');
    }

    #[test]
    #[available_gas(600000)]
    fn test_calculate_fee() {
        let value = 1000 * 1000000;
        let mut taker_eff = FixedTrait::ONE();
        let mut enforce_eff = FixedTrait::ONE();
        let maker_fee = adjusted_fee(100, FixedTrait::new(6442450944, false), enforce_eff); // 1.5

        let (mut to_market, mut to_seller) = required_withdrawals(value, maker_fee, 200, taker_eff, enforce_eff);
        assert(to_market == 26700000, 'wrong marketplace payment');
        assert(to_seller == 980000000, 'wrong seller payment');

        let (mut to_market, mut to_seller) = required_payments(value, maker_fee, 200, taker_eff, enforce_eff);
        assert(to_market == 26700000, 'wrong marketplace payment');
        assert(to_seller == 993300000, 'wrong seller payment');

        taker_eff = FixedTrait::new(6442450944, false); // 1.5
        let (mut to_market, mut to_seller) = required_withdrawals(value, 100, 200, taker_eff, enforce_eff);
        assert(to_market == 23300000, 'wrong marketplace payment');
        assert(to_seller == 986700000, 'wrong seller payment');
    }

    #[test]
    #[available_gas(600000)]
    fn test_partial_fills() {
        let (total, _) = required_deposit(1000 * 1234, 100, FixedTrait::ONE(), FixedTrait::ONE());

        let (order1_to_market, order1_to_seller) = required_withdrawals(
            333 * 1234,
            100,
            200,
            FixedTrait::new(5153960755, false), // 1.2
            FixedTrait::new(5583457485, false) // 1.3
        );

        let (order2_to_market, order2_to_seller) = required_withdrawals(
            333 * 1234,
            100,
            200,
            FixedTrait::new(6442450944, false), // 1.5
            FixedTrait::new(3221225472, false) // 0.75
        );

        let (order3_to_market, order3_to_seller) = required_withdrawals(
            334 * 1234,
            100,
            200,
            FixedTrait::new(3435973837, false), // 0.8
            FixedTrait::new(4724464026, false) // 1.1
        );

        let order1 = order1_to_market + order1_to_seller;
        let order2 = order2_to_market + order2_to_seller;
        let order3 = order3_to_market + order3_to_seller;

        assert(total >= order1 + order2 + order3, 'partials too large');
        assert(total - order1 - order2 - order3 < 3, 'remainder too large');
    }

    #[test]
    #[available_gas(45000000)]
    fn test_create_and_cancel_sell_order() {
        helpers::init();
        mocks::constants();

        // Add modifier configs
        mocks::modifier_type(modifier_types::INVENTORY_MASS_CAPACITY);
        mocks::modifier_type(modifier_types::INVENTORY_VOLUME_CAPACITY);
        mocks::modifier_type(modifier_types::MARKETPLACE_FEE_ENFORCEMENT);
        mocks::modifier_type(modifier_types::MARKETPLACE_FEE_REDUCTION);
        mocks::modifier_type(modifier_types::HOPPER_TRANSPORT_TIME);
        mocks::modifier_type(modifier_types::FREE_TRANSPORT_DISTANCE);

        let asteroid = influence::test::mocks::asteroid();
        let crew = influence::test::mocks::delegated_crew(1, 'PLAYER');

        // Setup product
        mocks::product_type(product_types::WATER);

        // Setup station
        let station = influence::test::mocks::public_habitat(crew, 1);
        components::set::<Location>(station.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1)));
        components::set::<Location>(crew.path(), LocationTrait::new(station));

        // Setup marketplace
        let market = influence::test::mocks::public_marketplace(crew, 2);
        components::set::<Location>(market.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 500)));

        // Setup warehouse
        let warehouse = influence::test::mocks::public_warehouse(crew, 3);
        components::set::<Location>(warehouse.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1000)));
        let mut inventory_path: Array<felt252> = Default::default();
        inventory_path.append(warehouse.into());
        inventory_path.append(2.into());
        let mut inventory_data = components::get::<Inventory>(inventory_path.span()).unwrap();
        let mut supplies: Array<InventoryItem> = Default::default();
        supplies.append(InventoryItemTrait::new(product_types::WATER, 1000));
        inventory::add_unchecked(ref inventory_data, supplies.span());
        components::set::<Inventory>(inventory_path.span(), inventory_data);

        let mut sell_state = CreateSellOrder::contract_state_for_testing();
        CreateSellOrder::run(
            ref sell_state,
            exchange: market,
            product: product_types::WATER,
            amount: 1000,
            price: 100 * 1000000,
            storage: warehouse,
            storage_slot: 2,
            caller_crew: crew,
            context: mocks::context('PLAYER')
        );

        // Check that the order was created
        let order_path = super::helpers::order_path(
            crew,
            market,
            order_types::LIMIT_SELL,
            product_types::WATER,
            100 * 1000000,
            warehouse,
            2
        );

        let mut order_data = components::get::<Order>(order_path).unwrap();
        assert(order_data.status == order_statuses::OPEN, 'wrong status');
        assert(order_data.amount == 1000, 'wrong amount');
        assert(order_data.valid_time > 0, 'wrong valid time');

        starknet::testing::set_block_timestamp(50000);

        // Cancel order
        let mut cancel_state = CancelSellOrder::contract_state_for_testing();
        CancelSellOrder::run(
            ref cancel_state,
            seller_crew: crew,
            exchange: market,
            product: product_types::WATER,
            price: 100 * 1000000,
            storage: warehouse,
            storage_slot: 2,
            caller_crew: crew,
            context: mocks::context('PLAYER')
        );

        // Check that the order was cancelled
        order_data = components::get::<Order>(order_path).unwrap();
        assert(order_data.status == order_statuses::CANCELLED, 'wrong status');

        // Check that delivery was created
        let mut delivery_data = components::get::<Delivery>(EntityTrait::new(entities::DELIVERY, 1).path()).unwrap();
        assert(delivery_data.status == delivery_statuses::SENT, 'wrong delivery status');
        assert(delivery_data.origin == market, 'wrong origin');
        assert(delivery_data.dest == warehouse, 'wrong destination');
    }
}
