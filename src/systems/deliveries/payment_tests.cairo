use array::ArrayTrait;
use option::OptionTrait;
use traits::{Into, TryInto};
use starknet::{ContractAddress, testing};

use influence::components;
use influence::common::inventory;
use influence::components::{Control, ControlTrait, Delivery, Inventory, Location, LocationTrait,
    PrivateSale, PrivateSaleTrait, WhitelistAgreement, WhitelistAgreementTrait,
    delivery::statuses, modifier_type::types as modifiers, product_type::types as products};
use influence::config::{entities, permissions};
use influence::systems::agreements::helpers::agreement_path;
use influence::contracts::sway::{ISwayDispatcher, ISwayDispatcherTrait};
use influence::test::{helpers, mocks};
use influence::types::{Entity, EntityTrait, InventoryItemTrait};
use super::{AcceptDelivery, PackageDelivery};

#[derive(Copy, Drop)]
struct Fixture {
    delivery: Entity,
    buyer: Entity,
    seller: Entity,
    origin: Entity,
    destination: Entity,
    sway: ISwayDispatcher,
}

fn setup(price: u64) -> Fixture {
    let f = setup_inventory();
    package(f, f.seller, 'SELLER', price);
    f
}

fn setup_inventory() -> Fixture {
    testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
    helpers::init();
    mocks::constants();
    mocks::modifier_type(modifiers::INVENTORY_MASS_CAPACITY);
    mocks::modifier_type(modifiers::INVENTORY_VOLUME_CAPACITY);
    mocks::modifier_type(modifiers::HOPPER_TRANSPORT_TIME);
    mocks::modifier_type(modifiers::FREE_TRANSPORT_DISTANCE);
    mocks::product_type(products::WATER);
    let sway = ISwayDispatcher { contract_address: helpers::deploy_sway() };
    let asteroid = mocks::asteroid();
    let seller = mocks::delegated_crew(1, 'SELLER');
    let buyer = mocks::delegated_crew(2, 'BUYER');
    let lot = EntityTrait::from_position(asteroid.id, 1000);
    let station = mocks::public_habitat(seller, 1);
    components::set::<Location>(station.path(), LocationTrait::new(lot));
    components::set::<Location>(seller.path(), LocationTrait::new(station));
    components::set::<Location>(buyer.path(), LocationTrait::new(station));
    let origin = mocks::public_warehouse(seller, 3);
    let destination = mocks::public_warehouse(buyer, 4);
    components::set::<Location>(origin.path(), LocationTrait::new(lot));
    components::set::<Location>(destination.path(), LocationTrait::new(lot));
    let contents = array![InventoryItemTrait::new(products::WATER, 1000)].span();
    let inventory_path = array![origin.into(), 2].span();
    let mut inventory_data = components::get::<Inventory>(inventory_path).unwrap();
    inventory::add_unchecked(ref inventory_data, contents);
    components::set::<Inventory>(inventory_path, inventory_data);

    let delivery = EntityTrait::new(entities::DELIVERY, 1);
    Fixture { delivery, buyer, seller, origin, destination, sway }
}

fn package(f: Fixture, crew: Entity, caller: felt252, price: u64) {
    let contents = array![InventoryItemTrait::new(products::WATER, 1000)].span();
    let mut state = PackageDelivery::contract_state_for_testing();
    PackageDelivery::run(
        ref state, f.origin, 2, contents, f.destination, 2, price, crew, mocks::context(caller)
    );
    assert(components::get::<PrivateSale>(f.delivery.path()).unwrap().amount == price, 'wrong package price');
}

fn operator(f: Fixture) -> Entity {
    let crew = mocks::delegated_crew(3, 'OPERATOR');
    let location = components::get::<Location>(f.buyer.path()).unwrap();
    components::set::<Location>(crew.path(), location);
    crew
}

fn grant(target: Entity, permission: u64, crew: Entity) {
    components::set::<WhitelistAgreement>(
        agreement_path(target, permission, crew.into()), WhitelistAgreementTrait::new(true)
    );
}

fn pay(f: Fixture, payer: felt252, recipient: felt252, amount: u128, memo: felt252) {
    let payer: ContractAddress = payer.try_into().unwrap();
    testing::set_contract_address(starknet::contract_address_const::<'ADMIN'>());
    f.sway.mint(payer, amount.into());
    testing::set_contract_address(payer);
    f.sway.transfer_with_confirmation(
        recipient.try_into().unwrap(), amount, memo, starknet::contract_address_const::<'DISPATCHER'>()
    );
    testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
}

fn accept(f: Fixture) {
    let mut state = AcceptDelivery::contract_state_for_testing();
    AcceptDelivery::run(ref state, f.delivery, f.buyer, mocks::context('BUYER'));
}

#[test]
#[available_gas(50000000)]
fn test_accept_closes_delivery_sale_only() {
    let f = setup(1000);
    components::set::<PrivateSale>(f.destination.path(), PrivateSaleTrait::new(5000));
    pay(f, 'BUYER', 'SELLER', 1000, f.delivery.into());
    accept(f);
    assert(components::get::<Delivery>(f.delivery.path()).unwrap().status == statuses::SENT, 'delivery not sent');
    assert(components::get::<PrivateSale>(f.delivery.path()).is_none(), 'delivery sale not closed');
    assert(components::get::<PrivateSale>(f.destination.path()).unwrap().amount == 5000, 'destination sale changed');
    assert(f.sway.balance_of(starknet::contract_address_const::<'SELLER'>()) == 1000, 'seller not paid');
    assert(f.sway.balance_of(starknet::contract_address_const::<'BUYER'>()) == 0, 'wrong buyer balance');
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('SWAY: invalid receipt', 'ENTRYPOINT_FAILED'))]
fn test_accept_requires_payment() {
    let f = setup(1000);
    accept(f);
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('SWAY: invalid receipt', 'ENTRYPOINT_FAILED'))]
fn test_accept_rejects_underpayment() {
    let f = setup(1000);
    pay(f, 'BUYER', 'SELLER', 999, f.delivery.into());
    accept(f);
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('SWAY: invalid receipt', 'ENTRYPOINT_FAILED'))]
fn test_accept_requires_callers_payment() {
    let f = setup(1000);
    pay(f, 'OTHER', 'SELLER', 1000, f.delivery.into());
    accept(f);
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('SWAY: invalid receipt', 'ENTRYPOINT_FAILED'))]
fn test_accept_requires_payment_to_seller() {
    let f = setup(1000);
    pay(f, 'BUYER', 'OTHER', 1000, f.delivery.into());
    accept(f);
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('SWAY: invalid receipt', 'ENTRYPOINT_FAILED'))]
fn test_accept_requires_delivery_receipt() {
    let f = setup(1000);
    pay(f, 'BUYER', 'SELLER', 1000, EntityTrait::new(entities::DELIVERY, 2).into());
    accept(f);
}

#[test]
#[available_gas(50000000)]
fn test_accept_zero_price_without_receipt() {
    let f = setup(0);
    accept(f);
    assert(components::get::<PrivateSale>(f.delivery.path()).is_none(), 'delivery sale not closed');
}

#[test]
#[available_gas(50000000)]
fn test_operator_packages_on_behalf_of_origin_controller() {
    let f = setup_inventory();
    let crew = operator(f);
    grant(f.origin, permissions::REMOVE_PRODUCTS, crew);
    package(f, crew, 'OPERATOR', 1000);
    pay(f, 'BUYER', 'SELLER', 1000, f.delivery.into());
    accept(f);
    assert(f.sway.balance_of(starknet::contract_address_const::<'SELLER'>()) == 1000, 'seller not paid');
    assert(f.sway.balance_of(starknet::contract_address_const::<'OPERATOR'>()) == 0, 'operator received proceeds');
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('E2002: access denied',))]
fn test_package_requires_remove_permission() {
    let f = setup_inventory();
    let crew = operator(f);
    grant(f.origin, permissions::ADD_PRODUCTS, crew);
    package(f, crew, 'OPERATOR', 1000);
}

#[test]
#[available_gas(50000000)]
fn test_operator_accepts_with_own_payment() {
    let f = setup(1000);
    let crew = operator(f);
    grant(f.destination, permissions::ADD_PRODUCTS, crew);
    pay(f, 'OPERATOR', 'SELLER', 1000, f.delivery.into());
    let mut state = AcceptDelivery::contract_state_for_testing();
    AcceptDelivery::run(ref state, f.delivery, crew, mocks::context('OPERATOR'));
    assert(components::get::<Delivery>(f.delivery.path()).unwrap().status == statuses::SENT, 'delivery not sent');
    assert(f.sway.balance_of(starknet::contract_address_const::<'SELLER'>()) == 1000, 'seller not paid');
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('SWAY: invalid receipt', 'ENTRYPOINT_FAILED'))]
fn test_operator_cannot_use_destination_owners_payment() {
    let f = setup(1000);
    let crew = operator(f);
    grant(f.destination, permissions::ADD_PRODUCTS, crew);
    pay(f, 'BUYER', 'SELLER', 1000, f.delivery.into());
    let mut state = AcceptDelivery::contract_state_for_testing();
    AcceptDelivery::run(ref state, f.delivery, crew, mocks::context('OPERATOR'));
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('E2002: access denied',))]
fn test_free_accept_requires_add_permission() {
    let f = setup(0);
    let crew = operator(f);
    grant(f.destination, permissions::REMOVE_PRODUCTS, crew);
    let mut state = AcceptDelivery::contract_state_for_testing();
    AcceptDelivery::run(ref state, f.delivery, crew, mocks::context('OPERATOR'));
}

#[test]
#[available_gas(50000000)]
fn test_payment_follows_current_origin_controller() {
    let f = setup(1000);
    let owner = mocks::delegated_crew(3, 'NEW_OWNER');
    components::set::<Control>(f.origin.path(), ControlTrait::new(owner));
    pay(f, 'BUYER', 'NEW_OWNER', 1000, f.delivery.into());
    accept(f);
    assert(components::get::<PrivateSale>(f.delivery.path()).is_none(), 'delivery sale not closed');
    assert(f.sway.balance_of(starknet::contract_address_const::<'NEW_OWNER'>()) == 1000, 'new owner not paid');
    assert(f.sway.balance_of(starknet::contract_address_const::<'SELLER'>()) == 0, 'previous owner paid');
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('SWAY: invalid receipt', 'ENTRYPOINT_FAILED'))]
fn test_payment_to_previous_origin_controller_is_rejected() {
    let f = setup(1000);
    pay(f, 'BUYER', 'SELLER', 1000, f.delivery.into());
    let owner = mocks::delegated_crew(3, 'NEW_OWNER');
    components::set::<Control>(f.origin.path(), ControlTrait::new(owner));
    accept(f);
}
