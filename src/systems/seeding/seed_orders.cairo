#[starknet::contract]
mod SeedOrders {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use starknet::contract_address::ContractAddress;
    use traits::{Into, TryInto};

    use cubit::f64::{Fixed, FixedTrait, ONE};

    use influence::{components, config, contracts, entities::next_id};
    use influence::common::inventory;
    use influence::components::{Crew, CrewTrait, Exchange, ExchangeTrait, Location, LocationTrait, Unique, UniqueTrait,
        building::{statuses as building_statuses, Building, BuildingTrait},
        building_type::types as building_types,
        exchange_type::types as exchange_types,
        inventory_type::types as inventory_types,
        inventory::{statuses as inventory_statuses, Inventory, InventoryTrait},
        order::{types as order_types, statuses as order_statuses, Order}};
    use influence::config::{entities, errors};
    use influence::systems::orders::helpers::order_path;
    use influence::types::{Context, ContextTrait, Entity, EntityTrait, InventoryItem};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct SellOrderCreated {
        exchange: Entity,
        product: u64,
        amount: u64,
        price: u64,
        storage: Entity,
        storage_slot: u64,
        valid_time: u64,
        maker_fee: u64,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        SellOrderCreated: SellOrderCreated
    }

    #[derive(Copy, Drop)]
    struct OrderSettings {
        warehouse_lot: u64,
        product: u64, // product id
        amount: u64, // amount in units
        price: u64, // price in SWAY
        laddered: bool
    }

    #[external(v0)]
    fn run(ref self: ContractState, market_lot: u64, warehouse_lot: u64, context: Context) {
        // Check the caller is the admin
        assert(context.is_admin(), 'only admin can seed');

        let asteroid = EntityTrait::new(entities::ASTEROID, 1);
        let crew = EntityTrait::new(entities::CREW, 1);

        // Get the marketplace building via Unique
        let market_lot_entity = EntityTrait::from_position(1, market_lot);
        let mut unique_path: Array<felt252> = Default::default();
        unique_path.append('LotUse');
        unique_path.append(market_lot_entity.into());
        let exchange: Entity = components::get::<Unique>(unique_path.span()).unwrap().unique.try_into().unwrap();

        // Get the orders
        let orders = get_orders(market_lot, warehouse_lot);
        let mut iter = 0;

        loop {
            if iter >= orders.len() { break; }

            // Lookup the warehouse building via Unique
            let storage_lot_entity = EntityTrait::from_position(1, warehouse_lot);
            unique_path = Default::default();
            unique_path.append('LotUse');
            unique_path.append(storage_lot_entity.into());
            let storage: Entity = components::get::<Unique>(unique_path.span()).unwrap().unique.try_into().unwrap();

            let product = (*orders.at(iter)).product;
            let amount = (*orders.at(iter)).amount;
            let price = (*orders.at(iter)).price;
            let laddered = (*orders.at(iter)).laddered;

            // Create the orders (returns the actual amount that needs to be reserved)
            let actual_amount = create_orders(
                ref self, crew, exchange, storage, product, amount, price, laddered, context, context.caller
            );

            // Reserve space in warehouse
            let mut inv_path: Array<felt252> = Default::default();
            inv_path.append(storage.into());
            inv_path.append(2);
            let mut inventory_data = components::get::<Inventory>(inv_path.span()).unwrap();

            let mut products: Array<InventoryItem> = Default::default();
            products.append(InventoryItem { product: product, amount: actual_amount });
            inventory::reserve_unchecked(ref inventory_data, products.span());
            components::set::<Inventory>(inv_path.span(), inventory_data);

            iter += 1;
        };
    }

    // Returns the actual amount that needs to be reserved
    fn create_orders(
        ref self: ContractState,
        crew: Entity,
        exchange: Entity,
        storage: Entity,
        product: u64,
        amount: u64,
        price: u64,
        laddered: bool,
        context: Context,
        caller: ContractAddress
    ) -> u64 {
        let mut iter = 1;
        let mut total_amount: u64 = 0;

        loop {
            if iter > 20 { break; }

            let (adjusted_amount, adjusted_price) = calculate_order(amount, price, iter, laddered);
            if adjusted_amount == 0 {
                iter += 1;
                continue;
            } // Skip if the amount is 0

            total_amount += adjusted_amount;

            let order_path = order_path(crew, exchange, order_types::LIMIT_SELL, product, adjusted_price, storage, 2);
            let mut order_data = Order {
                status: order_statuses::OPEN,
                amount: adjusted_amount,
                valid_time: context.now,
                maker_fee: 0
            };

            components::set::<Order>(order_path, order_data);

            // Update the exchange
            let mut exchange_data = components::get::<Exchange>(exchange.path()).unwrap();
            exchange_data.orders += 1;
            components::set::<Exchange>(exchange.path(), exchange_data);

            self.emit(SellOrderCreated {
                exchange: exchange,
                product: product,
                amount: adjusted_amount,
                price: adjusted_price,
                storage: storage,
                storage_slot: 2,
                valid_time: context.now,
                maker_fee: 0,
                caller_crew: crew,
                caller: context.caller
            });

            iter += 1;
        };

        return total_amount;
    }

    fn calculate_order(amount: u64, price: u64, iter: u64, laddered: bool) -> (u64, u64) {
        if !laddered {
            return (amount / 20, price + iter - 1);
        }

        let fixed_iter = FixedTrait::new_unscaled(iter, false);
        let a_mod = (FixedTrait::new(88046829568, false) - fixed_iter) / FixedTrait::new(858993459200, false);
        let adjusted_amount_u128: u128 = amount.into() * a_mod.mag.into();
        let adjusted_amount = FixedTrait::new(adjusted_amount_u128.try_into().unwrap(), false).round();

        let ten = FixedTrait::new(42949672960, false);
        let adjusted_price: u128 = (price.into() * ten.pow(fixed_iter / ten).mag.into()) / ONE.into();
        return (adjusted_amount.try_into().unwrap(), adjusted_price.try_into().unwrap());
    }

    fn get_orders(market_lot: u64, warehouse_lot: u64) -> Span<OrderSettings> {
        let mut orders: Array<OrderSettings> = Default::default();

        // Arkos
        if market_lot == 1598369 && warehouse_lot == 1597382 {
            orders.append(OrderSettings { warehouse_lot: 1597382, product: 2, amount: 9530000000, price: 75035, laddered: true });
            orders.append(OrderSettings { warehouse_lot: 1597382, product: 3, amount: 1610000000, price: 72961, laddered: true });
        } else if market_lot == 1598369 && warehouse_lot == 1596395 {
            orders.append(OrderSettings { warehouse_lot: 1596395, product: 4, amount: 186000000, price: 14480, laddered: true });
            orders.append(OrderSettings { warehouse_lot: 1596395, product: 5, amount: 4500000000, price: 71074, laddered: true });
            orders.append(OrderSettings { warehouse_lot: 1596395, product: 24, amount: 84600000000, price: 15052, laddered: false });
        } else if market_lot == 1598369 && warehouse_lot == 1595408 {
            orders.append(OrderSettings { warehouse_lot: 1595408, product: 180, amount: 73700000000, price: 29121, laddered: false });
        } else if market_lot == 1597759 && warehouse_lot == 1593434 {
            orders.append(OrderSettings { warehouse_lot: 1593434, product: 12, amount: 766000000, price: 14480, laddered: true });
            orders.append(OrderSettings { warehouse_lot: 1593434, product: 13, amount: 2170000000, price: 14480, laddered: true });
        } else if market_lot == 1597759 && warehouse_lot == 1592447 {
            orders.append(OrderSettings { warehouse_lot: 1592447, product: 14, amount: 3240000000, price: 14480, laddered: true });
            orders.append(OrderSettings { warehouse_lot: 1592447, product: 19, amount: 200000000, price: 14480, laddered: true });
            orders.append(OrderSettings { warehouse_lot: 1592447, product: 18, amount: 1330000000, price: 14480, laddered: true });
            orders.append(OrderSettings { warehouse_lot: 1592447, product: 20, amount: 5120000000, price: 14480, laddered: true });
            orders.append(OrderSettings { warehouse_lot: 1592447, product: 21, amount: 959000000, price: 14480, laddered: true });
        } else if market_lot == 1597759 && warehouse_lot == 1591460 {
            orders.append(OrderSettings { warehouse_lot: 1591460, product: 17, amount: 1110000000, price: 14480, laddered: true });
            orders.append(OrderSettings { warehouse_lot: 1591460, product: 16, amount: 78300000, price: 14480, laddered: true });
            orders.append(OrderSettings { warehouse_lot: 1591460, product: 15, amount: 945000000, price: 14480, laddered: true });
            orders.append(OrderSettings { warehouse_lot: 1591460, product: 22, amount: 39500000, price: 14480, laddered: true });
        } else if market_lot == 1615648 && warehouse_lot == 1610713 {
            orders.append(OrderSettings { warehouse_lot: 1610713, product: 175, amount: 551650000, price: 45565800, laddered: false });
            orders.append(OrderSettings { warehouse_lot: 1610713, product: 170, amount: 79101000000, price: 95710, laddered: false });
            orders.append(OrderSettings { warehouse_lot: 1610713, product: 129, amount: 10565500000, price: 326556, laddered: false });
        } else if market_lot == 1615648 && warehouse_lot == 1608129 {
            orders.append(OrderSettings { warehouse_lot: 1608129, product: 56, amount: 31900000000, price: 26452, laddered: false });
        } else if market_lot == 1615648 && warehouse_lot == 1607142 {
            orders.append(OrderSettings { warehouse_lot: 1607142, product: 74, amount: 68500000000, price: 75786, laddered: false });
        } else if market_lot == 1616025 && warehouse_lot == 1613962 {
            orders.append(OrderSettings { warehouse_lot: 1613962, product: 104, amount: 839000, price: 522736000, laddered: false });
        } else if market_lot == 1616025 && warehouse_lot == 1612742 {
            orders.append(OrderSettings { warehouse_lot: 1612742, product: 41, amount: 27000000000, price: 151768, laddered: false });
        } else if market_lot == 1614428 && warehouse_lot == 1614805 {
            orders.append(OrderSettings { warehouse_lot: 1614805, product: 69, amount: 84600000000, price: 58957, laddered: false });
        } else if market_lot == 1614428 && warehouse_lot == 1614195 {
            orders.append(OrderSettings { warehouse_lot: 1614195, product: 70, amount: 84600000000, price: 58964, laddered: false });
            orders.append(OrderSettings { warehouse_lot: 1614195, product: 101, amount: 84600000000, price: 59521, laddered: false });
        } else if market_lot == 1614428 && warehouse_lot == 1615182 {
            orders.append(OrderSettings { warehouse_lot: 1615182, product: 44, amount: 84600000000, price: 1042, laddered: false });
        } else if market_lot == 1592769 && warehouse_lot == 1590706 {
            orders.append(OrderSettings { warehouse_lot: 1590706, product: 133, amount: 2970000, price: 118193000, laddered: false });
        } else if market_lot == 1592769 && warehouse_lot == 1591083 {
            orders.append(OrderSettings { warehouse_lot: 1591083, product: 125, amount: 4720000000, price: 161738, laddered: false });
        } else if market_lot == 1593989 && warehouse_lot == 1595586 {
            orders.append(OrderSettings { warehouse_lot: 1595586, product: 235, amount: 2574000, price: 8420100000, laddered: false });
            orders.append(OrderSettings { warehouse_lot: 1595586, product: 237, amount: 1320800, price: 1251590000, laddered: false });
            orders.append(OrderSettings { warehouse_lot: 1595586, product: 238, amount: 3447600, price: 766412000, laddered: false });
            orders.append(OrderSettings { warehouse_lot: 1595586, product: 239, amount: 116480, price: 211647000, laddered: false });
        } else if market_lot == 1593989 && warehouse_lot == 1597183 {
            orders.append(OrderSettings { warehouse_lot: 1597183, product: 240, amount: 52160000, price: 798379000, laddered: false });
            orders.append(OrderSettings { warehouse_lot: 1597183, product: 241, amount: 593972, price: 12421100000, laddered: false });
            orders.append(OrderSettings { warehouse_lot: 1597183, product: 242, amount: 938880, price: 3032330000, laddered: false });
            orders.append(OrderSettings { warehouse_lot: 1597183, product: 243, amount: 70416000, price: 1687590000, laddered: false });
            orders.append(OrderSettings { warehouse_lot: 1597183, product: 244, amount: 42054000, price: 260269000, laddered: false });
        } else if market_lot == 1593989 && warehouse_lot == 1598780 {
            orders.append(OrderSettings { warehouse_lot: 1598780, product: 245, amount: 1540000, price: 199090000000, laddered: false });
        } else if market_lot == 1594976 && warehouse_lot == 1601974 {
            orders.append(OrderSettings { warehouse_lot: 1601974, product: 145, amount: 2335500, price: 130616000, laddered: false });
            orders.append(OrderSettings { warehouse_lot: 1601974, product: 146, amount: 4650240, price: 2704620000, laddered: false });
            orders.append(OrderSettings { warehouse_lot: 1601974, product: 147, amount: 217980, price: 4499470000, laddered: false });
            orders.append(OrderSettings { warehouse_lot: 1601974, product: 148, amount: 2408160, price: 22353300000, laddered: false });
        } else if market_lot == 1594976 && warehouse_lot == 1602961 {
            orders.append(OrderSettings { warehouse_lot: 1602961, product: 150, amount: 2138400, price: 15669100000, laddered: false });
            orders.append(OrderSettings { warehouse_lot: 1602961, product: 167, amount: 17334, price: 35959300000, laddered: false });
        }

        // Ya'axche
        if market_lot == 449470 && warehouse_lot == 448860 {
            orders.append(OrderSettings { warehouse_lot: 448860, product: 2, amount: 6350000000, price: 75035, laddered: true });
            orders.append(OrderSettings { warehouse_lot: 448860, product: 3, amount: 1070000000, price: 72961, laddered: true });
        } else if market_lot == 449470 && warehouse_lot == 448250 {
            orders.append(OrderSettings { warehouse_lot: 448250, product: 4, amount: 124000000, price: 14480, laddered: true });
            orders.append(OrderSettings { warehouse_lot: 448250, product: 5, amount: 3000000000, price: 71074, laddered: true });
            orders.append(OrderSettings { warehouse_lot: 448250, product: 24, amount: 84600000000, price: 15052, laddered: false });
        } else if market_lot == 449470 && warehouse_lot == 446653 {
            orders.append(OrderSettings { warehouse_lot: 446653, product: 180, amount: 49100000000, price: 29121, laddered: false });
        } else if market_lot == 450080 && warehouse_lot == 454871 {
            orders.append(OrderSettings { warehouse_lot: 454871, product: 12, amount: 510000000, price: 14480, laddered: true });
            orders.append(OrderSettings { warehouse_lot: 454871, product: 13, amount: 1450000000, price: 14480, laddered: true });
        } else if market_lot == 450080 && warehouse_lot == 453274 {
            orders.append(OrderSettings { warehouse_lot: 453274, product: 14, amount: 2160000000, price: 14480, laddered: true });
            orders.append(OrderSettings { warehouse_lot: 453274, product: 19, amount: 133000000, price: 14480, laddered: true });
            orders.append(OrderSettings { warehouse_lot: 453274, product: 18, amount: 891000000, price: 14480, laddered: true });
            orders.append(OrderSettings { warehouse_lot: 453274, product: 20, amount: 3410000000, price: 14480, laddered: true });
            orders.append(OrderSettings { warehouse_lot: 453274, product: 21, amount: 639000000, price: 14480, laddered: true });
        } else if market_lot == 450080 && warehouse_lot == 451677 {
            orders.append(OrderSettings { warehouse_lot: 451677, product: 17, amount: 742000000, price: 14480, laddered: true });
            orders.append(OrderSettings { warehouse_lot: 451677, product: 16, amount: 52200000, price: 14480, laddered: true });
            orders.append(OrderSettings { warehouse_lot: 451677, product: 15, amount: 630000000, price: 14480, laddered: true });
            orders.append(OrderSettings { warehouse_lot: 451677, product: 22, amount: 26300000, price: 14480, laddered: true });
        } else if market_lot == 464830 && warehouse_lot == 456468 {
            orders.append(OrderSettings { warehouse_lot: 456468, product: 175, amount: 375708000, price: 45565800, laddered: false });
            orders.append(OrderSettings { warehouse_lot: 456468, product: 170, amount: 80877600000, price: 95710, laddered: false });
            orders.append(OrderSettings { warehouse_lot: 456468, product: 129, amount: 7208240000, price: 326556, laddered: false });
        } else if market_lot == 464830 && warehouse_lot == 462246 {
            orders.append(OrderSettings { warehouse_lot: 462246, product: 56, amount: 21200000000, price: 26452, laddered: false });
        } else if market_lot == 464830 && warehouse_lot == 469998 {
            orders.append(OrderSettings { warehouse_lot: 469998, product: 74, amount: 45700000000, price: 75786, laddered: false });
        } else if market_lot == 448949 && warehouse_lot == 443781 {
            orders.append(OrderSettings { warehouse_lot: 443781, product: 104, amount: 559000, price: 522736000, laddered: false });
        } else if market_lot == 448949 && warehouse_lot == 448572 {
            orders.append(OrderSettings { warehouse_lot: 448572, product: 41, amount: 18000000000, price: 151768, laddered: false });
        } else if market_lot == 452143 && warehouse_lot == 453363 {
            orders.append(OrderSettings { warehouse_lot: 453363, product: 69, amount: 84600000000, price: 58957, laddered: false });
        } else if market_lot == 452143 && warehouse_lot == 452376 {
            orders.append(OrderSettings { warehouse_lot: 452376, product: 70, amount: 84600000000, price: 58964, laddered: false });
            orders.append(OrderSettings { warehouse_lot: 452376, product: 101, amount: 84600000000, price: 59521, laddered: false });
        } else if market_lot == 452143 && warehouse_lot == 447585 {
            orders.append(OrderSettings { warehouse_lot: 447585, product: 44, amount: 84600000000, price: 1042, laddered: false });
        }

        // Saline
        if market_lot == 1089343 && warehouse_lot == 1085539 {
            orders.append(OrderSettings { warehouse_lot: 1085539, product: 2, amount: 3170000000, price: 75035, laddered: true });
            orders.append(OrderSettings { warehouse_lot: 1085539, product: 3, amount: 538000000, price: 72961, laddered: true });
        } else if market_lot == 1089343 && warehouse_lot == 1088733 {
            orders.append(OrderSettings { warehouse_lot: 1088733, product: 4, amount: 62000000, price: 14480, laddered: true });
            orders.append(OrderSettings { warehouse_lot: 1088733, product: 5, amount: 1500000000, price: 71074, laddered: true });
            orders.append(OrderSettings { warehouse_lot: 1088733, product: 24, amount: 84600000000, price: 15052, laddered: false });
        } else if market_lot == 1089343 && warehouse_lot == 1091927 {
            orders.append(OrderSettings { warehouse_lot: 1091927, product: 180, amount: 24500000000, price: 29121, laddered: false });
        } else if market_lot == 1092304 && warehouse_lot == 1088500 {
            orders.append(OrderSettings { warehouse_lot: 1088500, product: 12, amount: 255000000, price: 14480, laddered: true });
            orders.append(OrderSettings { warehouse_lot: 1088500, product: 13, amount: 725000000, price: 14480, laddered: true });
        } else if market_lot == 1092304 && warehouse_lot == 1091694 {
            orders.append(OrderSettings { warehouse_lot: 1091694, product: 14, amount: 1080000000, price: 14480, laddered: true });
            orders.append(OrderSettings { warehouse_lot: 1091694, product: 19, amount: 66900000, price: 14480, laddered: true });
            orders.append(OrderSettings { warehouse_lot: 1091694, product: 18, amount: 445000000, price: 14480, laddered: true });
            orders.append(OrderSettings { warehouse_lot: 1091694, product: 20, amount: 1700000000, price: 14480, laddered: true });
            orders.append(OrderSettings { warehouse_lot: 1091694, product: 21, amount: 319000000, price: 14480, laddered: true });
        } else if market_lot == 1092304 && warehouse_lot == 1094888 {
            orders.append(OrderSettings { warehouse_lot: 1094888, product: 17, amount: 371000000, price: 14480, laddered: true });
            orders.append(OrderSettings { warehouse_lot: 1094888, product: 16, amount: 26100000, price: 14480, laddered: true });
            orders.append(OrderSettings { warehouse_lot: 1094888, product: 15, amount: 315000000, price: 14480, laddered: true });
            orders.append(OrderSettings { warehouse_lot: 1094888, product: 22, amount: 13100000, price: 14480, laddered: true });
        } else if market_lot == 1104148 && warehouse_lot == 1100344 {
            orders.append(OrderSettings { warehouse_lot: 1100344, product: 175, amount: 191688000, price: 45565800, laddered: false });
            orders.append(OrderSettings { warehouse_lot: 1100344, product: 170, amount: 82738800000, price: 95710, laddered: false });
            orders.append(OrderSettings { warehouse_lot: 1100344, product: 129, amount: 3687060000, price: 326556, laddered: false });
        } else if market_lot == 1104148 && warehouse_lot == 1106732 {
            orders.append(OrderSettings { warehouse_lot: 1106732, product: 56, amount: 10600000000, price: 26452, laddered: false });
        } else if market_lot == 1104148 && warehouse_lot == 1109926 {
            orders.append(OrderSettings { warehouse_lot: 1109926, product: 74, amount: 22800000000, price: 75786, laddered: false });
        }

        return orders.span();
    }
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use traits::Into;

    use cubit::{f64, f128};

    use influence::{components, config};
    use influence::components::{Location, LocationTrait, Orbit, ProductType, Unique,
        celestial::{types as celestial_types, statuses as celestial_statuses, Celestial},
        product_type::types as product_types,
        inventory::{types as inventory_types, Inventory, InventoryTrait},
        order::{statuses as order_statuses, types as order_types, Order}};
    use influence::config::entities;
    use influence::systems::orders::helpers::order_path;
    use influence::test::{helpers, mocks};
    use influence::types::{Entity, EntityTrait, Context, ContextTrait};

    use super::SeedOrders;

    #[test]
    #[available_gas(10000000)]
    fn test_calculate() {
        let (mut amount, mut price) = SeedOrders::calculate_order(100000, 100000, 1, true);
        assert(amount == 9750, 'amount should be 9750');
        assert(price == 125892, 'price should be 125892');

        let (mut amount, mut price) = SeedOrders::calculate_order(100000, 100000, 10, true);
        assert(amount == 5250, 'amount should be 5250');
        assert(price == 1000000, 'price should be 1000000');

        let (mut amount, mut price) = SeedOrders::calculate_order(100000, 100000, 20, true);
        assert(amount == 250, 'amount should be 250');
        assert(price == 10000000, 'price should be 10000000');

        // make sure we don't overflow
        let (mut amount, mut price) = SeedOrders::calculate_order(13000000000, 100000, 1, true);
    }

    #[test]
    #[available_gas(10000000)]
    fn test_calculate_no_ladder() {
        let (mut amount, mut price) = SeedOrders::calculate_order(100000, 100000, 1, false);
        assert(amount == 5000, 'amount should be 5000');
        assert(price == 100000, 'price should be 100000');

        let (mut amount, mut price) = SeedOrders::calculate_order(100000, 100000, 10, false);
        assert(amount == 5000, 'amount should be 5250');
        assert(price == 100009, 'price should be 100010');

        let (mut amount, mut price) = SeedOrders::calculate_order(100000, 100000, 20, false);
        assert(amount == 5000, 'amount should be 5000');
        assert(price == 100019, 'price should be 100020');
    }

    #[test]
    #[available_gas(100000000)]
    fn test_create_orders() {
        helpers::init();
        config::set('TIME_ACCELERATION', 24);

        let crew = mocks::delegated_crew(1, 'PLAYER');

        // Seed celestial and orbit data for Adalia Prime
        let asteroid = mocks::adalia_prime();
        components::set::<Celestial>(asteroid.path(), Celestial {
            celestial_type: celestial_types::C_TYPE_ASTEROID,
            mass: f128::FixedTrait::new(5711148277301932455541959738129383424, false), // mass in tonnes
            radius: f64::FixedTrait::new(1611222621356, false), // radius in km
            purchase_order: 0,
            scan_status: celestial_statuses::SURFACE_SCANNED,
            scan_finish_time: 0,
            bonuses: 0,
            abundances: 0 // Will be assigned during additional settlement seeding
        });

        components::set::<Orbit>(asteroid.path(), Orbit {
            a: f128::FixedTrait::new(6049029247426345756235714160, false),
            ecc: f128::FixedTrait::new(5995191823955604275, false),
            inc: f128::FixedTrait::new(45073898850257648, false),
            raan: f128::FixedTrait::new(62919943230756093952, false),
            argp: f128::FixedTrait::new(97469086699478581248, false),
            m: f128::FixedTrait::new(17488672753899970560, false),
        });

        // Construct a marketplace & warehouse
        let exchange = mocks::public_marketplace(crew, 1);
        components::set::<Location>(exchange.path(), LocationTrait::new(EntityTrait::from_position(1, 1591782)));
        let storage = mocks::public_warehouse(crew, 2);
        components::set::<Location>(storage.path(), LocationTrait::new(EntityTrait::from_position(1, 1591783)));

        let mut state = SeedOrders::contract_state_for_testing();
        let total_amount = SeedOrders::create_orders(
            ref state,
            crew,
            exchange,
            storage,
            42,
            100000,
            100000,
            true,
            mocks::context('PLAYER'),
            starknet::contract_address_const::<'PLAYER'>()
        );

        assert(total_amount == 100000, 'wrong total amount');

        // Check a few orders
        let mut path = order_path(crew, exchange, order_types::LIMIT_SELL, 42, 125892, storage, 2);
        let mut order_data = components::get::<Order>(path).unwrap();
        assert(order_data.status == order_statuses::OPEN, 'wrong status');
        assert(order_data.amount == 9750, 'wrong amount');
        assert(order_data.valid_time == 0, 'wrong valid time');
        assert(order_data.maker_fee == 0, 'wrong maker fee');

        path = order_path(crew, exchange, order_types::LIMIT_SELL, 42, 1000000, storage, 2);
        order_data = components::get::<Order>(path).unwrap();
        assert(order_data.status == order_statuses::OPEN, 'wrong status');
        assert(order_data.amount == 5250, 'wrong amount');
        assert(order_data.valid_time == 0, 'wrong valid time');
        assert(order_data.maker_fee == 0, 'wrong maker fee');

        path = order_path(crew, exchange, order_types::LIMIT_SELL, 42, 10000000, storage, 2);
        order_data = components::get::<Order>(path).unwrap();
        assert(order_data.status == order_statuses::OPEN, 'wrong status');
        assert(order_data.amount == 250, 'wrong amount');
        assert(order_data.valid_time == 0, 'wrong valid time');
        assert(order_data.maker_fee == 0, 'wrong maker fee');
    }

    #[test]
    #[available_gas(250000000)]
    fn test_seed() {
        helpers::init();
        config::set('TIME_ACCELERATION', 24);

        let crew = mocks::delegated_crew(1, 'ADMIN');

        // Seed celestial and orbit data for Adalia Prime
        let asteroid = mocks::adalia_prime();
        components::set::<Celestial>(asteroid.path(), Celestial {
            celestial_type: celestial_types::C_TYPE_ASTEROID,
            mass: f128::FixedTrait::new(5711148277301932455541959738129383424, false), // mass in tonnes
            radius: f64::FixedTrait::new(1611222621356, false), // radius in km
            purchase_order: 0,
            scan_status: celestial_statuses::SURFACE_SCANNED,
            scan_finish_time: 0,
            bonuses: 0,
            abundances: 0 // Will be assigned during additional settlement seeding
        });

        components::set::<Orbit>(asteroid.path(), Orbit {
            a: f128::FixedTrait::new(6049029247426345756235714160, false),
            ecc: f128::FixedTrait::new(5995191823955604275, false),
            inc: f128::FixedTrait::new(45073898850257648, false),
            raan: f128::FixedTrait::new(62919943230756093952, false),
            argp: f128::FixedTrait::new(97469086699478581248, false),
            m: f128::FixedTrait::new(17488672753899970560, false),
        });

        // Construct a marketplace & warehouses
        let exchange = mocks::public_marketplace(crew, 1);
        components::set::<Location>(exchange.path(), LocationTrait::new(EntityTrait::from_position(1, 1615648)));
        let mut unique_path: Array<felt252> = Default::default();
        unique_path.append('LotUse');
        unique_path.append(EntityTrait::from_position(1, 1615648).into());
        components::set::<Unique>(unique_path.span(), Unique { unique: exchange.into() });

        let storage = mocks::public_warehouse(crew, 2);
        components::set::<Location>(storage.path(), LocationTrait::new(EntityTrait::from_position(1, 1610713)));
        unique_path = Default::default();
        unique_path.append('LotUse');
        unique_path.append(EntityTrait::from_position(1, 1610713).into());
        components::set::<Unique>(unique_path.span(), Unique { unique: storage.into() });
        let mut inv_path: Array<felt252> = Default::default();
        inv_path.append(storage.into());
        inv_path.append(2);
        components::set::<Inventory>(inv_path.span(), InventoryTrait::new(inventory_types::WAREHOUSE_PRIMARY));

        // Create product configs
        mocks::product_type(product_types::CORE_DRILL); // 175
        mocks::product_type(product_types::HYDROGEN_PROPELLANT); // 170
        mocks::product_type(product_types::FOOD); // 129

        // Seed orders
        let mut state = SeedOrders::contract_state_for_testing();
        SeedOrders::run(ref state, 1615648, 1610713, mocks::context('ADMIN'));

        // Check a few orders
        let mut path = order_path(crew, exchange, order_types::LIMIT_SELL, product_types::CORE_DRILL, 45565801, storage, 2);
        let mut order_data = components::get::<Order>(path).unwrap();
        assert(order_data.status == order_statuses::OPEN, 'wrong status');
        assert(order_data.amount == 27582500, 'wrong amount');
        assert(order_data.valid_time == 0, 'wrong valid time');
        assert(order_data.maker_fee == 0, 'wrong maker fee');
    }
}
