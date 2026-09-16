#[starknet::contract]
mod GrantOffchainStarterPack {
    use array::{Array, ArrayTrait, SpanTrait};
    use clone::Clone;
    use option::OptionTrait;
    use starknet::{ContractAddress, get_contract_address};
    use starknet::storage::Map;
    use traits::{Into, TryInto};

    use influence::{components, contracts};
    use influence::common::crewmate as crewmate_common;
    use influence::components::{Building, BuildingAllowance, BuildingTrait, Control, ControlTrait, Crew, CrewTrait,
        Location, LocationTrait, Name, NameTrait, StarterPack, Station, StationTrait,
        building_type::types as building_types,
        crewmate::{collections, Crewmate, CrewmateTrait},
        starter_pack_products};
    use influence::config::{entities, errors, permissions, roles};
    use influence::contracts::crewmate::{ICrewmateDispatcher, ICrewmateDispatcherTrait};
    use influence::systems::helpers::{change_name, create_restricted_crew};
    use influence::types::{Context, ContextTrait, Entity, EntityTrait, StringTrait};

    #[storage]
    struct Storage {
        // Shared by offchain grant systems so an external payment reference can only be used once.
        external_refs: Map::<felt252, bool>
    }

    #[derive(Copy, Drop, starknet::Event)]
    struct OffchainStarterPackGranted {
        external_ref: felt252,
        product_id: u64,
        recipient: ContractAddress,
        crew: Entity,
        composition: Span<u64>,
        restricted_until: u64,
        lot_allowance: u64,
        food_reload_allowance: u64,
        core_sample_allowance: u64,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        OffchainStarterPackGranted: OffchainStarterPackGranted
    }

    #[external(v0)]
    fn run(
        ref self: ContractState,
        recipient: ContractAddress,
        external_ref: felt252,
        product_id: u64,
        restricted_until: u64,
        station: Entity,
        classes: Span<u64>,
        impactful: Span<u64>,
        cosmetic: Span<u64>,
        genders: Span<u64>,
        bodies: Span<u64>,
        faces: Span<u64>,
        hairs: Span<u64>,
        hair_colors: Span<u64>,
        clothes: Span<u64>,
        names: Span<felt252>,
        context: Context
    ) {
        assert(
            context.is_admin() || context.has_role(roles::OFFCHAIN_STARTER_PACK_GRANTER),
            'not starter pack granter'
        );
        assert(!recipient.is_zero(), 'invalid recipient');
        assert(external_ref != 0, 'external ref required');
        assert(!self.external_refs.read(external_ref), 'external ref used');
        self.external_refs.write(external_ref, true);

        let count = pack_size(product_id);
        assert(classes.len() == count, errors::INCORRECT_CREW_SIZE);
        assert(impactful.len() == count, 'invalid impactful length');
        assert(cosmetic.len() == count * 3, 'invalid cosmetic length');
        assert(genders.len() == count, 'invalid gender length');
        assert(bodies.len() == count, 'invalid body length');
        assert(faces.len() == count, 'invalid face length');
        assert(hairs.len() == count, 'invalid hair length');
        assert(hair_colors.len() == count, 'invalid hair color length');
        assert(clothes.len() == count, 'invalid clothes length');
        assert(names.len() == count, 'invalid name length');

        let mut station_data = components::get::<Station>(station.path()).expect(errors::STATION_NOT_FOUND);
        components::get::<Building>(station.path()).expect(errors::BUILDING_NOT_FOUND).assert_operational();
        let building_allowances = pack_building_allowances(product_id);
        let lot_allowance = pack_lot_allowance(product_id);
        let food_reload_allowance = pack_food_reload_allowance(product_id);
        let core_sample_allowance = pack_core_sample_allowance(product_id);

        let (crew, mut crew_data) = create_restricted_crew(station, recipient, restricted_until, context.caller);
        let crewmate_contract = ICrewmateDispatcher { contract_address: contracts::get('Crewmate') };
        let contract_address = get_contract_address();
        let mut roster: Array<u64> = Default::default();

        let mut iter = 0;
        loop {
            if iter >= count { break; };

            let class = *classes.at(iter);
            let cosmetic_start = iter * 3;
            let crewmate_cosmetic = array![
                *cosmetic.at(cosmetic_start),
                *cosmetic.at(cosmetic_start + 1),
                *cosmetic.at(cosmetic_start + 2)
            ];
            let crewmate_impactful = array![*impactful.at(iter)];

            let mut crewmate_data = CrewmateTrait::new(collections::ADALIAN);
            crewmate_common::provision_adalian(
                ref crewmate_data,
                class,
                crewmate_impactful.span(),
                crewmate_cosmetic.span(),
                *genders.at(iter),
                *bodies.at(iter),
                *faces.at(iter),
                *hairs.at(iter),
                *hair_colors.at(iter),
                *clothes.at(iter),
                *names.at(iter)
            );

            let crewmate_id = crewmate_contract.mint_with_auto_id(contract_address);
            crewmate_contract.transfer_with_restriction(
                contract_address, recipient, crewmate_id, restricted_until, context.caller
            );
            let crewmate = EntityTrait::new(entities::CREWMATE, crewmate_id.try_into().unwrap());
            components::set::<Crewmate>(crewmate.path(), crewmate_data);
            components::set::<Control>(crewmate.path(), ControlTrait::new(crew));
            change_name(crewmate, StringTrait::new(*names.at(iter)));
            roster.append(crewmate.id);

            iter += 1;
        };

        crew_data.roster = roster.span();
        crew_data.last_fed = context.now;
        components::set::<Crew>(crew.path(), crew_data);

        station_data.population += count.try_into().unwrap();
        components::set::<Station>(station.path(), station_data);

        components::set::<StarterPack>(crew.path(), StarterPack {
            product_id: product_id,
            restricted_until: restricted_until,
            valid: true,
            invalidated_at: 0,
            building_allowances: building_allowances,
            lot_allowance: lot_allowance,
            food_reload_allowance: food_reload_allowance,
            core_sample_allowance: core_sample_allowance
        });

        self.emit(OffchainStarterPackGranted {
            external_ref: external_ref,
            product_id: product_id,
            recipient: recipient,
            crew: crew,
            composition: roster.span(),
            restricted_until: restricted_until,
            lot_allowance: lot_allowance,
            food_reload_allowance: food_reload_allowance,
            core_sample_allowance: core_sample_allowance,
            caller: context.caller
        });
    }

    fn pack_size(product_id: u64) -> usize {
        if product_id == starter_pack_products::EXPLORER { return 2; }
        if product_id == starter_pack_products::STRATEGIST { return 3; }
        if product_id == starter_pack_products::INDUSTRIALIST { return 5; }
        assert(false, 'invalid starter pack');
        return 0;
    }

    fn pack_building_allowances(product_id: u64) -> Span<BuildingAllowance> {
        if product_id == starter_pack_products::EXPLORER {
            return array![
                BuildingAllowance { building_type: building_types::WAREHOUSE, count: 1 },
                BuildingAllowance { building_type: building_types::EXTRACTOR, count: 1 }
            ].span();
        }
        if product_id == starter_pack_products::STRATEGIST {
            return array![
                BuildingAllowance { building_type: building_types::WAREHOUSE, count: 1 },
                BuildingAllowance { building_type: building_types::EXTRACTOR, count: 1 },
                BuildingAllowance { building_type: building_types::REFINERY, count: 1 }
            ].span();
        }
        if product_id == starter_pack_products::INDUSTRIALIST {
            return array![
                BuildingAllowance { building_type: building_types::WAREHOUSE, count: 1 },
                BuildingAllowance { building_type: building_types::EXTRACTOR, count: 1 },
                BuildingAllowance { building_type: building_types::REFINERY, count: 1 },
                BuildingAllowance { building_type: building_types::BIOREACTOR, count: 1 },
                BuildingAllowance { building_type: building_types::FACTORY, count: 1 }
            ].span();
        }
        assert(false, 'invalid starter pack');
        let empty: Array<BuildingAllowance> = Default::default();
        return empty.span();
    }

    fn pack_food_reload_allowance(product_id: u64) -> u64 {
        if product_id == starter_pack_products::EXPLORER { return 1; }
        if product_id == starter_pack_products::STRATEGIST { return 1; }
        if product_id == starter_pack_products::INDUSTRIALIST { return 1; }
        assert(false, 'invalid starter pack');
        return 0;
    }

    fn pack_lot_allowance(product_id: u64) -> u64 {
        if product_id == starter_pack_products::EXPLORER { return 2; }
        if product_id == starter_pack_products::STRATEGIST { return 3; }
        if product_id == starter_pack_products::INDUSTRIALIST { return 5; }
        assert(false, 'invalid starter pack');
        return 0;
    }

    fn pack_core_sample_allowance(product_id: u64) -> u64 {
        if product_id == starter_pack_products::EXPLORER { return 5; }
        if product_id == starter_pack_products::STRATEGIST { return 8; }
        if product_id == starter_pack_products::INDUSTRIALIST { return 12; }
        assert(false, 'invalid starter pack');
        return 0;
    }

}

#[cfg(test)]
mod tests {
    use array::{Array, ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use traits::{Into, TryInto};

    use influence::{components, contracts};
    use influence::components::{Control, Crew, Crewmate, StarterPack, StarterPackTrait,
        building_type::types as building_types,
        crewmate::{classes, crewmate_traits},
        inventory_type::types as inventory_types,
        ship_type::types as ship_types,
        starter_pack_products};
    use influence::config::{entities, roles};
    use influence::contracts::Dispatcher;
    use influence::contracts::crew::{ICrewDispatcher, ICrewDispatcherTrait};
    use influence::contracts::crewmate::{ICrewmateDispatcher, ICrewmateDispatcherTrait};
    use influence::test::{helpers, mocks};
    use influence::types::{Context, Entity, EntityTrait};

    use super::GrantOffchainStarterPack;

    #[test]
    #[available_gas(30000000)]
    fn test_grant_explorer_starter_crew_pack() {
        let station = setup();
        let mut state = GrantOffchainStarterPack::contract_state_for_testing();
        grant_explorer(ref state, station, 'stripe:explorer:1', 200, mocks::context('ADMIN'));

        assert_pack(1, starter_pack_products::EXPLORER, 2, 1, 1, 0, 0, 0, 2, 5, 1);

        let crewmate1 = EntityTrait::new(entities::CREWMATE, 20000);
        let crewmate1_data = components::get::<Crewmate>(crewmate1.path()).unwrap();
        assert(crewmate1_data.class == classes::PILOT, 'wrong class');
        assert(
            components::get::<Control>(crewmate1.path()).unwrap().controller == EntityTrait::new(entities::CREW, 1),
            'wrong controller'
        );

        let crew_contract = ICrewDispatcher { contract_address: contracts::get('Crew') };
        let crewmate_contract = ICrewmateDispatcher { contract_address: contracts::get('Crewmate') };
        assert(crew_contract.is_restricted(1), 'crew unrestricted');
        assert(crewmate_contract.is_restricted(20000), 'crewmate unrestricted');
        assert(crew_contract.ownerOf(1) == starknet::contract_address_const::<'PLAYER'>(), 'wrong crew owner');
        assert(crewmate_contract.ownerOf(20000) == starknet::contract_address_const::<'PLAYER'>(), 'wrong crewmate owner');
        assert(crew_contract.restriction(1).restriction_authority == starknet::contract_address_const::<'ADMIN'>(), 'wrong crew auth');
        assert(
            crewmate_contract.restriction(20000).restriction_authority == starknet::contract_address_const::<'ADMIN'>(),
            'wrong crewmate auth'
        );
    }

    #[test]
    #[available_gas(30000000)]
    fn test_grant_strategist_starter_pack() {
        let station = setup();
        let mut state = GrantOffchainStarterPack::contract_state_for_testing();
        grant_strategist(ref state, station, 'stripe:strategist:1', 200, mocks::context('ADMIN'));

        assert_pack(1, starter_pack_products::STRATEGIST, 3, 1, 1, 1, 0, 0, 3, 8, 1);
    }

    #[test]
    #[available_gas(30000000)]
    fn test_grant_industrialist_starter_pack() {
        let station = setup();
        let mut state = GrantOffchainStarterPack::contract_state_for_testing();
        grant_industrialist(ref state, station, 'stripe:industrial:1', 200, mocks::context('ADMIN'));

        assert_pack(1, starter_pack_products::INDUSTRIALIST, 5, 1, 1, 1, 1, 1, 5, 12, 1);
    }

    #[test]
    #[available_gas(30000000)]
    fn test_grants_with_offchain_starter_pack_role() {
        let station = setup();
        let mut dispatcher_state = Dispatcher::contract_state_for_testing();
        starknet::testing::set_caller_address(starknet::contract_address_const::<'ADMIN'>());
        Dispatcher::add_grant(
            ref dispatcher_state,
            starknet::contract_address_const::<'STRIPE_JOB'>(),
            roles::OFFCHAIN_STARTER_PACK_GRANTER
        );

        let mut state = GrantOffchainStarterPack::contract_state_for_testing();
        grant_explorer(ref state, station, 'stripe:role:1', 200, mocks::context('STRIPE_JOB'));

        assert_pack(1, starter_pack_products::EXPLORER, 2, 1, 1, 0, 0, 0, 2, 5, 1);

        let crew_contract = ICrewDispatcher { contract_address: contracts::get('Crew') };
        assert(
            crew_contract.restriction(1).restriction_authority == starknet::contract_address_const::<'STRIPE_JOB'>(),
            'wrong role auth'
        );
    }

    #[test]
    #[available_gas(30000000)]
    #[should_panic(expected: ('external ref used', ))]
    fn test_rejects_duplicate_external_ref() {
        let station = setup();
        let mut state = GrantOffchainStarterPack::contract_state_for_testing();
        grant_explorer(ref state, station, 'stripe:duplicate', 200, mocks::context('ADMIN'));
        grant_explorer(ref state, station, 'stripe:duplicate', 200, mocks::context('ADMIN'));
    }

    #[test]
    #[available_gas(30000000)]
    #[should_panic(expected: ('not starter pack granter', ))]
    fn test_rejects_non_admin() {
        let station = setup();
        let mut state = GrantOffchainStarterPack::contract_state_for_testing();
        grant_explorer(ref state, station, 'stripe:not-admin', 200, mocks::context('PLAYER'));
    }

    #[test]
    #[available_gas(30000000)]
    #[should_panic(expected: ('invalid starter pack', ))]
    fn test_rejects_invalid_product() {
        let station = setup();
        let mut state = GrantOffchainStarterPack::contract_state_for_testing();
        GrantOffchainStarterPack::run(
            ref state,
            starknet::contract_address_const::<'PLAYER'>(),
            'stripe:bad-product',
            999,
            200,
            station,
            array![classes::PILOT, classes::ENGINEER].span(),
            array![crewmate_traits::NAVIGATOR, crewmate_traits::BUILDER].span(),
            explorer_cosmetic().span(),
            array![1, 1].span(),
            array![1, 1].span(),
            array![1, 1].span(),
            array![1, 1].span(),
            array![1, 1].span(),
            array![32, 34].span(),
            array!['One Test', 'Two Test'].span(),
            mocks::context('ADMIN')
        );
    }

    #[test]
    #[available_gas(30000000)]
    #[should_panic(expected: ('invalid cosmetic length', ))]
    fn test_rejects_wrong_span_lengths() {
        let station = setup();
        let mut state = GrantOffchainStarterPack::contract_state_for_testing();
        GrantOffchainStarterPack::run(
            ref state,
            starknet::contract_address_const::<'PLAYER'>(),
            'stripe:bad-length',
            starter_pack_products::EXPLORER,
            200,
            station,
            array![classes::PILOT, classes::ENGINEER].span(),
            array![crewmate_traits::NAVIGATOR, crewmate_traits::BUILDER].span(),
            array![crewmate_traits::DRIVE_COMMAND].span(),
            array![1, 1].span(),
            array![1, 1].span(),
            array![1, 1].span(),
            array![1, 1].span(),
            array![1, 1].span(),
            array![32, 34].span(),
            array!['One Test', 'Two Test'].span(),
            mocks::context('ADMIN')
        );
    }

    #[test]
    #[available_gas(30000000)]
    fn test_expired_restriction_reports_unrestricted() {
        let station = setup();
        let mut state = GrantOffchainStarterPack::contract_state_for_testing();
        grant_explorer(ref state, station, 'stripe:expired', 200, mocks::context('ADMIN'));

        starknet::testing::set_block_timestamp(201);
        let crew_contract = ICrewDispatcher { contract_address: contracts::get('Crew') };
        let crewmate_contract = ICrewmateDispatcher { contract_address: contracts::get('Crewmate') };
        assert(!crew_contract.is_restricted(1), 'crew restricted');
        assert(!crewmate_contract.is_restricted(20000), 'crewmate restricted');
    }

    fn setup() -> Entity {
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        starknet::testing::set_block_timestamp(100);
        helpers::init();

        let crew_address = helpers::deploy_crew();
        let crewmate_address = helpers::deploy_crewmate();

        starknet::testing::set_contract_address(starknet::contract_address_const::<'ADMIN'>());
        ICrewDispatcher { contract_address: crew_address }
            .add_grant(starknet::contract_address_const::<'DISPATCHER'>(), 2);
        ICrewmateDispatcher { contract_address: crewmate_address }
            .add_grant(starknet::contract_address_const::<'DISPATCHER'>(), 2);

        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        mocks::inventory_type(inventory_types::PROPELLANT_TINY);
        mocks::ship_type(ship_types::ESCAPE_MODULE);

        let station_controller = EntityTrait::new(entities::CREW, 999);
        return mocks::public_habitat(station_controller, 1);
    }

    fn grant_explorer(
        ref state: GrantOffchainStarterPack::ContractState,
        station: Entity,
        external_ref: felt252,
        restricted_until: u64,
        context: Context
    ) {
        GrantOffchainStarterPack::run(
            ref state,
            starknet::contract_address_const::<'PLAYER'>(),
            external_ref,
            starter_pack_products::EXPLORER,
            restricted_until,
            station,
            array![classes::PILOT, classes::ENGINEER].span(),
            array![crewmate_traits::NAVIGATOR, crewmate_traits::BUILDER].span(),
            explorer_cosmetic().span(),
            array![1, 1].span(),
            array![1, 1].span(),
            array![1, 1].span(),
            array![1, 1].span(),
            array![1, 1].span(),
            array![32, 34].span(),
            array!['One Test', 'Two Test'].span(),
            context
        );
    }

    fn grant_strategist(
        ref state: GrantOffchainStarterPack::ContractState,
        station: Entity,
        external_ref: felt252,
        restricted_until: u64,
        context: Context
    ) {
        GrantOffchainStarterPack::run(
            ref state,
            starknet::contract_address_const::<'PLAYER'>(),
            external_ref,
            starter_pack_products::STRATEGIST,
            restricted_until,
            station,
            array![classes::PILOT, classes::ENGINEER, classes::MINER].span(),
            array![crewmate_traits::NAVIGATOR, crewmate_traits::BUILDER, crewmate_traits::PROSPECTOR].span(),
            strategist_cosmetic().span(),
            array![1, 1, 1].span(),
            array![1, 1, 1].span(),
            array![1, 1, 1].span(),
            array![1, 1, 1].span(),
            array![1, 1, 1].span(),
            array![32, 34, 36].span(),
            array!['One Test', 'Two Test', 'Three Test'].span(),
            context
        );
    }

    fn grant_industrialist(
        ref state: GrantOffchainStarterPack::ContractState,
        station: Entity,
        external_ref: felt252,
        restricted_until: u64,
        context: Context
    ) {
        GrantOffchainStarterPack::run(
            ref state,
            starknet::contract_address_const::<'PLAYER'>(),
            external_ref,
            starter_pack_products::INDUSTRIALIST,
            restricted_until,
            station,
            array![classes::PILOT, classes::ENGINEER, classes::MINER, classes::MERCHANT, classes::SCIENTIST].span(),
            array![
                crewmate_traits::NAVIGATOR,
                crewmate_traits::BUILDER,
                crewmate_traits::PROSPECTOR,
                crewmate_traits::HAULER,
                crewmate_traits::DIETITIAN
            ].span(),
            industrialist_cosmetic().span(),
            array![1, 1, 1, 1, 1].span(),
            array![1, 1, 1, 1, 1].span(),
            array![1, 1, 1, 1, 1].span(),
            array![1, 1, 1, 1, 1].span(),
            array![1, 1, 1, 1, 1].span(),
            array![32, 34, 36, 38, 40].span(),
            array!['One Test', 'Two Test', 'Three Test', 'Four Test', 'Five Test'].span(),
            context
        );
    }

    fn explorer_cosmetic() -> Array<u64> {
        return array![
            crewmate_traits::DRIVE_COMMAND,
            crewmate_traits::RIGHTEOUS,
            crewmate_traits::ADVENTUROUS,
            crewmate_traits::DRIVE_COMMAND,
            crewmate_traits::RIGHTEOUS,
            crewmate_traits::ADVENTUROUS
        ];
    }

    fn strategist_cosmetic() -> Array<u64> {
        return array![
            crewmate_traits::DRIVE_COMMAND,
            crewmate_traits::RIGHTEOUS,
            crewmate_traits::ADVENTUROUS,
            crewmate_traits::DRIVE_COMMAND,
            crewmate_traits::RIGHTEOUS,
            crewmate_traits::ADVENTUROUS,
            crewmate_traits::DRIVE_COMMAND,
            crewmate_traits::RIGHTEOUS,
            crewmate_traits::ADVENTUROUS
        ];
    }

    fn industrialist_cosmetic() -> Array<u64> {
        return array![
            crewmate_traits::DRIVE_COMMAND,
            crewmate_traits::RIGHTEOUS,
            crewmate_traits::ADVENTUROUS,
            crewmate_traits::DRIVE_COMMAND,
            crewmate_traits::RIGHTEOUS,
            crewmate_traits::ADVENTUROUS,
            crewmate_traits::DRIVE_COMMAND,
            crewmate_traits::RIGHTEOUS,
            crewmate_traits::ADVENTUROUS,
            crewmate_traits::DRIVE_COMMAND,
            crewmate_traits::RIGHTEOUS,
            crewmate_traits::ADVENTUROUS,
            crewmate_traits::DRIVE_COMMAND,
            crewmate_traits::RIGHTEOUS,
            crewmate_traits::ADVENTUROUS
        ];
    }

    fn assert_pack(
        crew_id: u64,
        product_id: u64,
        crew_size: usize,
        warehouse_count: u64,
        extractor_count: u64,
        refinery_count: u64,
        bioreactor_count: u64,
        factory_count: u64,
        lot_allowance: u64,
        core_sample_allowance: u64,
        food_reload_allowance: u64
    ) {
        let crew = EntityTrait::new(entities::CREW, crew_id);
        let crew_data = components::get::<Crew>(crew.path()).unwrap();
        assert(crew_data.roster.len() == crew_size, 'wrong crew size');
        assert(*crew_data.roster.at(0) == 20000, 'wrong crewmate 1');

        let starter_pack = components::get::<StarterPack>(crew.path()).unwrap();
        assert(starter_pack.product_id == product_id, 'wrong pack');
        assert(starter_pack.restricted_until == 200, 'wrong restriction');
        assert(starter_pack.valid, 'pack invalid');
        assert(starter_pack.invalidated_at == 0, 'pack invalidated');
        assert(starter_pack.building_allowance(building_types::WAREHOUSE) == warehouse_count, 'wrong warehouse');
        assert(starter_pack.building_allowance(building_types::EXTRACTOR) == extractor_count, 'wrong extractor');
        assert(starter_pack.building_allowance(building_types::REFINERY) == refinery_count, 'wrong refinery');
        assert(starter_pack.building_allowance(building_types::BIOREACTOR) == bioreactor_count, 'wrong bioreactor');
        assert(starter_pack.building_allowance(building_types::FACTORY) == factory_count, 'wrong factory');
        assert(starter_pack.lot_allowance == lot_allowance, 'wrong lots');
        assert(starter_pack.core_sample_allowance == core_sample_allowance, 'wrong core samples');
        assert(starter_pack.food_reload_allowance == food_reload_allowance, 'wrong food');
    }
}
