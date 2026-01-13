use array::{ArrayTrait, SpanTrait};
use cmp::{min, max};
use core::clone::Clone;
use option::OptionTrait;
use traits::{Into, TryInto};

use cubit::f64::{Fixed, FixedTrait, ONE};

use influence::components;
use influence::components::{ProductTypeTrait,
    inventory_type::{types, InventoryType, InventoryTypeTrait},
    inventory::{Inventory, InventoryTrait}};
use influence::config::errors;
use influence::types::inventory_item::{InventoryItem, InventoryItemTrait, InventoryContentsTrait};

// Adds items to the inventory checking lock status and space
// @param inventory: the inventory component to add to
// @param items: the items to add
// @param efficiency: the efficiency of the crew for storage space
fn add(ref inventory: Inventory, items: Span<InventoryItem>, mass_eff: Fixed, volume_eff: Fixed) {
    inventory.assert_ready();

    let config = InventoryTypeTrait::by_type(inventory.inventory_type);
    _add(ref inventory, items, config);

    if config.modifiable {
        let modified_mass = integer::u64_wide_mul(config.mass, mass_eff.mag) / ONE.into();
        let modified_volume = integer::u64_wide_mul(config.volume, volume_eff.mag) / ONE.into();
        assert((inventory.mass + inventory.reserved_mass).into() <= modified_mass, 'inventory mass exceeded');
        assert((inventory.volume + inventory.reserved_volume).into() <= modified_volume, 'inventory volume exceeded');
    } else {
        assert(inventory.mass + inventory.reserved_mass <= config.mass, 'inventory mass exceeded');
        assert(inventory.volume + inventory.reserved_volume <= config.volume, 'inventory volume exceeded');
    }
}

// Adds items to the inventory without checking for space and lock
fn add_unchecked(ref inventory: Inventory, items: Span<InventoryItem>) {
    let config = InventoryTypeTrait::by_type(inventory.inventory_type);
    _add(ref inventory, items, config);
}

// Internal add function
fn _add(ref inventory: Inventory, items: Span<InventoryItem>, config: InventoryType) {
    let has_mask = config.products.len() > 0;
    let mut results: Array<InventoryItem> = Default::default();
    let mut lhs = inventory.contents;
    let mut remaining = items;

    // Find matches and add amounts to lhs
    loop {
        match lhs.pop_front() {
            Option::Some(v) => {
                let new_amount = match_and_delete(ref remaining, *v.product) + *v.amount;
                assert(
                    !has_mask ||
                    (new_amount + inventory.reservations.amount_of(*v.product) <= config.products.amount_of(*v.product)),
                    'adding too many'
                );
                results.append(InventoryItem { product: *v.product, amount: new_amount });
            },
            Option::None(_) => {
                break ();
            }
        };
    };

    // Add leftovers from rhs
    loop {
        match remaining.pop_front() {
            Option::Some(v) => {
                assert(
                    !has_mask ||
                    (*v.amount + inventory.reservations.amount_of(*v.product) <= config.products.amount_of(*v.product)),
                    'adding too many'
                );
                results.append(*v);
            },
            Option::None(_) => {
                break ();
            }
        };
    };

    inventory.contents = results.span();
    let (new_mass, new_volume) = totals(items);
    inventory.mass += new_mass;
    inventory.volume += new_volume;
}

// Removes a set of items from the inventory
// @param inventory: the inventory component to remove from
// @param items: the items to remove
fn remove(ref inventory: Inventory, items: Span<InventoryItem>) {
    inventory.assert_ready();

    let mut result: Array<InventoryItem> = Default::default();
    let mut lhs = inventory.contents;
    let mut remaining = items;
    let mut next = lhs.pop_front();

    loop {
        if next.is_none() { break; }
        let current = next.unwrap();
        let to_remove = match_and_delete(ref remaining, *current.product);
        assert(to_remove <= *current.amount, 'removing too many');
        let amount = *current.amount - to_remove;

        match amount.into() {
            0 => next = lhs.pop_back(),
            _ => {
                result.append(InventoryItem { product: *current.product, amount: amount });
                next = lhs.pop_front();
            }
        };
    };

    assert(remaining.len() == 0, 'too many products');

    inventory.contents = result.span();
    let (old_mass, old_volume) = totals(items);
    inventory.mass -= min(inventory.mass, old_mass);
    inventory.volume -= min(inventory.volume, old_volume);
}

// Reserves space in the inventory based on the size of the items
// @param inventory: the inventory to reserve space in
// @param items: the items to reserve space for
// @param mass_eff: the efficiency of the crew for storage mass
// @param volume_eff: the efficiency of the crew for storage space
fn reserve(ref inventory: Inventory, items: Span<InventoryItem>, mass_eff: Fixed, volume_eff: Fixed) {
    inventory.assert_ready();

    let config = InventoryTypeTrait::by_type(inventory.inventory_type);
    _reserve(ref inventory, items, config);

    if config.modifiable {
        let modified_mass = integer::u64_wide_mul(config.mass, mass_eff.mag) / ONE.into();
        let modified_volume = integer::u64_wide_mul(config.volume, volume_eff.mag) / ONE.into();
        assert((inventory.mass + inventory.reserved_mass).into() <= modified_mass, 'inventory mass exceeded');
        assert((inventory.volume + inventory.reserved_volume).into() <= modified_volume, 'inventory volume exceeded');
    } else {
        assert(inventory.mass + inventory.reserved_mass <= config.mass, 'inventory mass exceeded');
        assert(inventory.volume + inventory.reserved_volume <= config.volume, 'inventory volume exceeded');
    }
}

fn reserve_unchecked(ref inventory: Inventory, items: Span<InventoryItem>) {
    let config = InventoryTypeTrait::by_type(inventory.inventory_type);
    _reserve(ref inventory, items, config);
}

fn _reserve(ref inventory: Inventory, items: Span<InventoryItem>, config: InventoryType) {
    // Adjust total mass and volume
    let (new_mass, new_volume) = totals(items);
    inventory.reserved_mass += new_mass;
    inventory.reserved_volume += new_volume;

    // If there is no product mask, just return, otherwise we need to check the limited products
    if config.products.len() == 0 { return; }

    let mut results: Array<InventoryItem> = Default::default();
    let mut lhs = inventory.reservations;
    let mut remaining = items;

    // Find matches and add amounts to lhs
    loop {
        match lhs.pop_front() {
            Option::Some(v) => {
                let new_amount = match_and_delete(ref remaining, *v.product) + *v.amount;
                assert(
                    new_amount + inventory.contents.amount_of(*v.product) <= config.products.amount_of(*v.product),
                    'reserving too many'
                );
                results.append(InventoryItem { product: *v.product, amount: new_amount });
            },
            Option::None(_) => {
                break ();
            }
        };
    };

    // Add leftovers from rhs
    loop {
        match remaining.pop_front() {
            Option::Some(v) => {
                assert(
                    *v.amount + inventory.contents.amount_of(*v.product) <= config.products.amount_of(*v.product),
                    'reserving too many'
                );
                results.append(*v);
            },
            Option::None(_) => {
                break ();
            }
        };
    };

    inventory.reservations = results.span();
}

// Unreserves space in the inventory based on the size of the items
// @param inventory: the inventory to unreserve space in
// @param items: the items to unreserve space for
fn unreserve(ref inventory: Inventory, items: Span<InventoryItem>) {
    let (removed_mass, removed_volume) = totals(items);
    inventory.reserved_mass -= min(inventory.reserved_mass, removed_mass);
    inventory.reserved_volume -= min(inventory.reserved_volume, removed_volume);

    // If there are no reservations (i.e. there is no relevant product mask), just return
    if inventory.reservations.len() == 0 { return; }

    let mut result: Array<InventoryItem> = Default::default();
    let mut lhs = inventory.reservations;
    let mut remaining = items;
    let mut next = lhs.pop_front();

    loop {
        if next.is_none() { break; }
        let current = next.unwrap();
        let to_remove = match_and_delete(ref remaining, *current.product);
        let amount = *current.amount - min(to_remove, *current.amount); // TODO: assert after mainnet deploy

        match amount.into() {
            0 => next = lhs.pop_back(),
            _ => {
                result.append(InventoryItem { product: *current.product, amount: amount });
                next = lhs.pop_front();
            }
        };
    };

    assert(remaining.len() == 0, 'too many products');
    inventory.reservations = result.span();
}

fn totals(items: Span<InventoryItem>) -> (u64, u64) {
    let mut mass: u64 = 0;
    let mut volume: u64 = 0;
    let mut iter = 0;

    loop {
        if iter >= items.len() { break; }

        let amount = *items.at(iter).amount;
        let product_config = ProductTypeTrait::by_type((*items.at(iter)).product);
        mass += amount * product_config.mass;
        volume += amount * product_config.volume;

        iter += 1;
    };

    return (mass, volume);
}

// Matches a product and returns the amount, deletes the item from contents
fn match_and_delete(ref contents: Span<InventoryItem>, product: u64) -> u64 {
    let mut mutated: Array<InventoryItem> = Default::default();
    let mut amount = 0;

    loop {
        match contents.pop_front() {
            Option::Some(item) => {
                if *item.product == product {
                    amount = *item.amount;
                } else {
                    mutated.append(*item);
                }
            },
            Option::None(_) => {
                break ();
            },
        };
    };

    contents = mutated.span();
    return amount;
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use array::{ArrayTrait, SpanTrait};
    use core::clone::Clone;
    use option::OptionTrait;
    use traits::Into;

    use cubit::f64::{Fixed, FixedTrait, ONE};

    use influence::components;
    use influence::components::{
        inventory_type::{types, InventoryType},
        product_type::types as product_types,
        inventory::{Inventory, InventoryTrait}};
    use influence::types::inventory_item::{InventoryItem, InventoryItemTrait, InventoryContentsTrait};
    use influence::test::mocks;

    fn add_product_types() {
        mocks::product_type(product_types::WATER);
        mocks::product_type(product_types::HYDROGEN);
        mocks::product_type(product_types::AMMONIA);
        mocks::product_type(product_types::NITROGEN);
    }

    #[test]
    #[available_gas(3000000)]
    fn test_add() {
        add_product_types();
        mocks::inventory_type(types::WAREHOUSE_PRIMARY);

        let contents1 = array![
            InventoryItemTrait::new(1, 10), InventoryItemTrait::new(2, 20), InventoryItemTrait::new(3, 30)
        ];

        let mut inventory = Inventory {
            status: 1,
            inventory_type: types::WAREHOUSE_PRIMARY,
            mass: 0,
            volume: 0,
            reserved_mass: 0,
            reserved_volume: 0,
            contents: Default::default().span(),
            reservations: Default::default().span()
        };

        super::add(ref inventory, contents1.span(), FixedTrait::ONE(), FixedTrait::ONE());
        assert(inventory.mass == 60000, 'wrong mass');
        assert(inventory.volume == 332810, 'wrong volume');
        assert(inventory.contents.len() == 3, 'wrong length');

        let contents2 = array![
            InventoryItemTrait::new(1, 5), InventoryItemTrait::new(2, 10), InventoryItemTrait::new(4, 15)
        ];

        super::add(ref inventory, contents2.span(), FixedTrait::ONE(), FixedTrait::ONE());
        assert(inventory.mass == 90000, 'wrong mass');
        assert(inventory.volume == 497265, 'wrong volume');

        assert(inventory.contents.len() == 4, 'wrong length');
        assert(*inventory.contents.at(0).product == 1, 'wrong product');
        assert(*inventory.contents.at(0).amount == 15, 'wrong amount');
        assert(*inventory.contents.at(1).product == 2, 'wrong product');
        assert(*inventory.contents.at(1).amount == 30, 'wrong amount');
        assert(*inventory.contents.at(2).product == 3, 'wrong product');
        assert(*inventory.contents.at(2).amount == 30, 'wrong amount');
        assert(*inventory.contents.at(3).product == 4, 'wrong product');
        assert(*inventory.contents.at(3).amount == 15, 'wrong amount');
    }

    #[test]
    #[available_gas(3000000)]
    fn test_remove_pop_swap() {
        add_product_types();
        mocks::inventory_type(types::WAREHOUSE_PRIMARY);

        let contents1 = array![
            InventoryItemTrait::new(1, 10), InventoryItemTrait::new(2, 20), InventoryItemTrait::new(3, 30)
        ];

        let mut inventory = Inventory {
            status: 1,
            inventory_type: 10,
            mass: 0,
            volume: 0,
            reserved_mass: 0,
            reserved_volume: 0,
            contents: Default::default().span(),
            reservations: Default::default().span()
        };

        super::add(ref inventory, contents1.span(), FixedTrait::ONE(), FixedTrait::ONE());

        let contents2 = array![
            InventoryItemTrait::new(1, 10), InventoryItemTrait::new(2, 10), InventoryItemTrait::new(3, 15)
        ];

        super::remove(ref inventory, contents2.span());
        assert(inventory.mass == 25000, 'wrong mass');
        assert(inventory.volume == 161550, 'wrong volume');
        assert(inventory.contents.len() == 2, 'wrong length');
        assert(*inventory.contents.at(0).product == 3, 'wrong product');
        assert(*inventory.contents.at(0).amount == 15, 'wrong amount');
        assert(*inventory.contents.at(1).product == 2, 'wrong product');
        assert(*inventory.contents.at(1).amount == 10, 'wrong amount');
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic(expected: ('too many products', ))]
    fn test_remove_too_many() {
        add_product_types();
        mocks::inventory_type(types::WAREHOUSE_PRIMARY);

        let contents1 = array![InventoryItemTrait::new(1, 10), InventoryItemTrait::new(2, 20)];
        let mut inventory = Inventory {
            status: 1,
            inventory_type: 10,
            mass: 0,
            volume: 0,
            reserved_mass: 0,
            reserved_volume: 0,
            contents: Default::default().span(),
            reservations: Default::default().span()
        };

        super::add(ref inventory, contents1.span(), FixedTrait::ONE(), FixedTrait::ONE());
        let contents2 = array![InventoryItemTrait::new(1, 10), InventoryItemTrait::new(3, 30)];
        super::remove(ref inventory, contents2.span());
    }

    #[test]
    #[available_gas(2500000)]
    fn test_remove_pop() {
        add_product_types();
        mocks::inventory_type(types::WAREHOUSE_PRIMARY);

        let contents1 = array![
            InventoryItemTrait::new(1, 10),
            InventoryItemTrait::new(2, 20),
            InventoryItemTrait::new(3, 30),
            InventoryItemTrait::new(4, 40)
        ];

        let mut inventory = Inventory {
            status: 1,
            inventory_type: 10,
            mass: 0,
            volume: 0,
            reserved_mass: 0,
            reserved_volume: 0,
            contents: Default::default().span(),
            reservations: Default::default().span()
        };

        super::add(ref inventory, contents1.span(), FixedTrait::ONE(), FixedTrait::ONE());
        let contents2 = array![InventoryItemTrait::new(1, 10), InventoryItemTrait::new(3, 30)];
        super::remove(ref inventory, contents2.span());

        assert(inventory.contents.len() == 2, 'wrong length');
        assert(*inventory.contents.at(0).product == 4, 'wrong product');
        assert(*inventory.contents.at(0).amount == 40, 'wrong amount');
        assert(*inventory.contents.at(1).product == 2, 'wrong product');
        assert(*inventory.contents.at(1).amount == 20, 'wrong amount');
    }

    #[test]
    #[available_gas(2500000)]
    fn test_remove_all() {
        add_product_types();
        mocks::inventory_type(types::WAREHOUSE_PRIMARY);

        let contents1 = array![
            InventoryItemTrait::new(1, 10), InventoryItemTrait::new(2, 20), InventoryItemTrait::new(3, 30)
        ];

        let mut inventory = Inventory {
            status: 1,
            inventory_type: 10,
            mass: 0,
            volume: 0,
            reserved_mass: 0,
            reserved_volume: 0,
            contents: Default::default().span(),
            reservations: Default::default().span()
        };

        super::add(ref inventory, contents1.span(), FixedTrait::ONE(), FixedTrait::ONE());
        let contents2 = array![
            InventoryItemTrait::new(1, 5), InventoryItemTrait::new(2, 10), InventoryItemTrait::new(3, 15)
        ];

        super::remove(ref inventory, contents2.span());

        assert(inventory.contents.len() == 3, 'wrong length');
        assert(*inventory.contents.at(0).product == 1, 'wrong product');
        assert(*inventory.contents.at(0).amount == 5, 'wrong amount');
        assert(*inventory.contents.at(1).product == 2, 'wrong product');
        assert(*inventory.contents.at(1).amount == 10, 'wrong amount');
        assert(*inventory.contents.at(2).product == 3, 'wrong product');
        assert(*inventory.contents.at(2).amount == 15, 'wrong amount');
    }

    #[test]
    #[available_gas(3000000)]
    fn test_reserve() {
        mocks::product_type(product_types::CEMENT);
        mocks::product_type(product_types::STEEL_BEAM);
        mocks::product_type(product_types::STEEL_SHEET);
        mocks::inventory_type(types::WAREHOUSE_SITE);

        let mut inventory = Inventory {
            status: 1,
            inventory_type: types::WAREHOUSE_SITE,
            mass: 0,
            volume: 0,
            reserved_mass: 0,
            reserved_volume: 0,
            contents: Default::default().span(),
            reservations: Default::default().span()
        };

        let unreserve = array![InventoryItemTrait::new(product_types::CEMENT, 100000)];
        let reserve = array![
            InventoryItemTrait::new(product_types::CEMENT, 250000),
            InventoryItemTrait::new(product_types::STEEL_BEAM, 100000),
            InventoryItemTrait::new(product_types::STEEL_SHEET, 100000)
        ];

        // Allows unreserving "below" zero for legacy support
        super::unreserve(ref inventory, reserve.span());

        // Now try to actually reserve
        super::reserve(ref inventory, reserve.span(), FixedTrait::ONE(), FixedTrait::ONE());
        assert(inventory.reservations.len() == 3, 'wrong length');
        assert(*inventory.reservations.at(0).product == product_types::CEMENT, 'wrong product');
        assert(*inventory.reservations.at(0).amount == 250000, 'wrong amount');

        // Un-reserve
        super::unreserve(ref inventory, unreserve.span());
        assert(inventory.reservations.len() == 3, 'wrong length');
        assert(*inventory.reservations.at(0).product == product_types::CEMENT, 'wrong product');
        assert(*inventory.reservations.at(0).amount == 150000, 'wrong amount');
    }

    #[test]
    #[available_gas(2500000)]
    #[should_panic(expected: ('reserving too many', ))]
    fn test_reserve_fail() {
        mocks::product_type(product_types::CEMENT);
        mocks::product_type(product_types::STEEL_BEAM);
        mocks::product_type(product_types::STEEL_SHEET);
        mocks::inventory_type(types::WAREHOUSE_SITE);

        let mut inventory = Inventory {
            status: 1,
            inventory_type: types::WAREHOUSE_SITE,
            mass: 0,
            volume: 0,
            reserved_mass: 0,
            reserved_volume: 0,
            contents: Default::default().span(),
            reservations: Default::default().span()
        };

        let reserve = array![InventoryItemTrait::new(product_types::CEMENT, 250000)];

        super::reserve(ref inventory, reserve.span(), FixedTrait::ONE(), FixedTrait::ONE());
        super::reserve(ref inventory, reserve.span(), FixedTrait::ONE(), FixedTrait::ONE());
    }
}