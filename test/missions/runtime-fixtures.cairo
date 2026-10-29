// Admin-only fixtures compiled in an isolated temp package, never in production.
#[starknet::contract]
mod MissionRuntimeSeed {
    use array::ArrayTrait;
    use option::OptionTrait;
    use traits::Into;
    use starknet::ContractAddress;
    use influence::{components, runtime_mocks as mocks};
    use influence::common::inventory;
    use influence::components::{Crew, Building, Location, LocationTrait, Control, ControlTrait, Inventory, InventoryTrait, BuildingTypeTrait, ProcessType};
    use influence::components::modifier_type::types as modifiers;
    use influence::components::product_type::types as products;
    use influence::components::building_type::types as buildings;
    use influence::types::{Context, ContextTrait, EntityTrait, InventoryItem};
    #[storage]
    struct Storage {}
    #[external(v0)]
    fn run(ref self: ContractState, seller: ContractAddress, buyer: ContractAddress, market_account: ContractAddress, context: Context) {
        assert(context.is_admin(), 'admin fixture only');
        mocks::constants();
        for modifier in array![modifiers::INVENTORY_MASS_CAPACITY, modifiers::INVENTORY_VOLUME_CAPACITY, modifiers::MARKETPLACE_FEE_ENFORCEMENT, modifiers::MARKETPLACE_FEE_REDUCTION, modifiers::HOPPER_TRANSPORT_TIME, modifiers::FREE_TRANSPORT_DISTANCE, modifiers::CONSTRUCTION_TIME] { mocks::modifier_type(modifier); };
        mocks::product_type(products::WATER);
        mocks::exchange_type(influence::components::exchange_type::types::BASIC);
        let asteroid = mocks::asteroid();
        let c1 = mocks::delegated_crew(1,seller.into());
        let c2 = mocks::delegated_crew(2,buyer.into());
        let c3 = mocks::delegated_crew(3,market_account.into());
        let station = mocks::public_habitat(c3,1);
        let market = mocks::public_marketplace(c3,2);
        let source = mocks::public_warehouse(c1,3);
        let dest = mocks::public_warehouse(c2,4);
        let lot = EntityTrait::from_position(asteroid.id,1);
        for entity in array![station,market,source,dest] { components::set::<Location>(entity.path(),LocationTrait::new(lot)); };
        for crew in array![c1,c2,c3] {
            components::set::<Location>(crew.path(),LocationTrait::new(station));
            let mut data = components::get::<Crew>(crew.path()).unwrap(); data.last_fed = context.now;
            components::set::<Crew>(crew.path(),data);
        };
        components::set::<Control>(asteroid.path(),ControlTrait::new(c1));
        let path = array![source.into(),2].span();
        let mut stock = components::get::<Inventory>(path).unwrap();
        inventory::add_unchecked(ref stock,array![InventoryItem {product:products::WATER,amount:100000}].span());
        components::set::<Inventory>(path,stock);
        mocks::building_type(buildings::MARKETPLACE);
        let cfg = BuildingTypeTrait::by_type(buildings::MARKETPLACE);
        mocks::inventory_type(cfg.site_type);
        components::set::<ProcessType>(array![cfg.process_type.into()].span(),ProcessType {
            setup_time:3600, recipe_time:0, batched:false, processor_type:0,
            inputs:array![].span(), outputs:array![].span()
        });
        let mut building = components::get::<Building>(market.path()).unwrap();
        building.status = influence::components::building::statuses::PLANNED;
        components::set::<Building>(market.path(),building);
        components::set::<Inventory>(array![market.into(),cfg.site_slot.into()].span(),InventoryTrait::new(cfg.site_type));
    }
}
#[starknet::contract]
mod RevertingMissionPolicy {
    use array::ArrayTrait;
    #[storage]
    struct Storage {}
    #[external(v0)]
    fn before(ref self: ContractState, name: felt252, data: Span<felt252>, targets: Span<felt252>) -> Span<felt252> { array![].span() }
    #[external(v0)]
    fn after(ref self: ContractState, name: felt252, data: Span<felt252>, snapshot: Span<felt252>, result: Span<felt252>) { panic_with_felt252('test post hook rejected'); }
}
#[starknet::contract]
mod ReentrantMissionAction {
    use array::ArrayTrait;
    use starknet::SyscallResultTrait;
    use influence::types::Context;
    #[storage]
    struct Storage {}
    #[external(v0)]
    fn run(ref self: ContractState, context: Context) {
        starknet::syscalls::call_contract_syscall(starknet::get_contract_address(), selector!("run_system"), array!['ReentrantMissionAction', 0].span()).unwrap_syscall();
    }
}
