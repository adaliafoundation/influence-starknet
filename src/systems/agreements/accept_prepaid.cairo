#[starknet::contract]
mod AcceptPrepaidAgreement {
    use array::{Array, ArrayTrait};
    use cmp::min;
    use option::OptionTrait;
    use starknet::{contract_address_const, ContractAddress};
    use traits::{Into, TryInto};

    use cubit::f64::{FixedTrait, trig::PI, comp};
    use cubit::f128::{FixedTrait as FixedTrait128};

    use influence::{components, config, contracts};
    use influence::common::{crew::CrewDetailsTrait, math::RoundedDivTrait, position};
    use influence::components::{Building, Celestial, Crew, CrewTrait, Control, ControlTrait, PrepaidPolicy,
        PrepaidPolicyTrait, PrepaidAgreement, PrepaidAgreementTrait, PrepaidAgreementAuction,
        PrepaidAgreementAuctionTrait, Unique};
    use influence::components::agreements::prepaid_auction::modes as auction_modes;
    use influence::config::{entities, errors, permissions, MAX_ASTEROID_RADIUS};
    use influence::contracts::sway::{ISwayDispatcher, ISwayDispatcherTrait};
    use influence::systems::agreements::helpers::{
        agreement_path, auction_price, auction_settings, lot_use_path, use_lot_path
    };
    use influence::systems::policies::helpers::policy_path;
    use influence::types::{ArrayHashTrait, Context, Entity, EntityTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct PrepaidAgreementAccepted {
        target: Entity,
        permission: u64,
        permitted: Entity,
        term: u64,
        rate: u64,
        initial_term: u64,
        notice_period: u64,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        PrepaidAgreementAccepted: PrepaidAgreementAccepted
    }

    #[external(v0)]
    fn run(
        ref self: ContractState,
        target: Entity, // the target entity the permitted will get permission to act on
        permission: u64, // the permission being granted
        permitted: Entity, // the entity gaining the permission
        term: u64, // duration of the agreement in IRL seconds
        caller_crew: Entity,
        context: Context
    ) {
        // Check that crew is delegated, and ready
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_launched(context.now);
        crew_details.assert_delegated_to(context.caller);
        crew_details.assert_manned();

        // Check for current policy
        let mut controller_crew = EntityTrait::new(entities::CREW, 0);
        let (target_ast, _) = target.to_position();
        let mut asteroid = EntityTrait::new(entities::ASTEROID, target_ast);
        let mut policy_path: Span<felt252> = Default::default().span();

        if target.label == entities::LOT {
            assert(permission == permissions::USE_LOT, 'invalid permission');

            // Lot policies are all associated to the asteroid
            policy_path = policy_path(asteroid, permission);
            controller_crew = components::get::<Control>(asteroid.path()).expect(errors::CONTROL_NOT_FOUND).controller;

            // Check that the lot is not already used by the asteroid controller
            let mut has_building = false;
            let mut building = EntityTrait::new(entities::BUILDING, 0);
            let mut building_controller = EntityTrait::new(entities::CREW, 0);

            match components::get::<Unique>(lot_use_path(target)) {
                Option::Some(unique_data) => {
                    let lot_use: Entity = unique_data.unique.try_into().unwrap();
                    has_building = lot_use.label == entities::BUILDING;
                    if has_building {
                        building = lot_use;
                        building_controller = components::get::<Control>(building.path())
                            .expect(errors::CONTROL_NOT_FOUND).controller;
                        assert(!controller_crew.controls(lot_use), 'lot controlled by asteroid');
                    }
                },
                Option::None(_) => ()
            };

            // Ensure use lot agreements are unique / you can't lease over the top of someone else's lease
            let mut unique: Entity = EntityTrait::new(entities::CREW, 0);
            let mut requires_auction = false;
            let mut current_data = PrepaidAgreementTrait::new(0, 0, 0, 0, 0);

            // Allow creating a new agreement if caller crew is current tenant OR as long as the current unique
            // tenant no longer has permission to use the lot
            match components::get::<Unique>(use_lot_path(target)) {
                Option::Some(unique_data) => {
                    unique = unique_data.unique.try_into().unwrap();
                    assert(unique == permitted || !unique.can(target, permissions::USE_LOT), 'lot already leased');

                    if unique != permitted && has_building && building_controller != permitted {
                        match components::get::<PrepaidAgreement>(agreement_path(target, permission, unique.into())) {
                            Option::Some(data) => {
                                current_data = data;
                                requires_auction = true;
                            },
                            Option::None(_) => ()
                        };
                    }
                },
                Option::None(_) => ()
            };

            if requires_auction {
                let settings = auction_settings(asteroid);
                let mut elapsed = context.now - current_data.end_time;

                if settings.mode == auction_modes::MANUAL {
                    let auction_data = components::get::<PrepaidAgreementAuction>(target.path())
                        .expect(errors::PREPAID_AUCTION_NOT_FOUND);
                    elapsed = context.now - auction_data.start_time;
                    components::set::<PrepaidAgreementAuction>(
                        target.path(), PrepaidAgreementAuctionTrait::inactive()
                    );
                }

                let auction_amount = auction_price(settings, elapsed);
                let lease_lapse = ((context.now - current_data.end_time) * current_data.rate).div_ceil(3600);
                let to_controller = min(auction_amount, lease_lapse);
                let to_building_controller = auction_amount - to_controller;

                if to_controller > 0 {
                    let mut memo: Array<felt252> = Default::default();
                    memo.append(target.into());
                    memo.append(permission.into());
                    memo.append(unique.into());
                    memo.append('auction_controller'.into());

                    let delegated_to = components::get::<Crew>(controller_crew.path())
                        .expect(errors::CREW_NOT_FOUND).delegated_to;
                    ISwayDispatcher { contract_address: contracts::get('Sway') }.confirm_receipt(
                        context.caller, delegated_to, to_controller.into(), memo.hash()
                    );
                }

                if to_building_controller > 0 {
                    let mut memo: Array<felt252> = Default::default();
                    memo.append(target.into());
                    memo.append(permission.into());
                    memo.append(unique.into());
                    memo.append('auction_building'.into());

                    let delegated_to = components::get::<Crew>(building_controller.path())
                        .expect(errors::CREW_NOT_FOUND).delegated_to;
                    ISwayDispatcher { contract_address: contracts::get('Sway') }.confirm_receipt(
                        context.caller, delegated_to, to_building_controller.into(), memo.hash()
                    );
                }

                match components::get::<PrepaidAgreementAuction>(target.path()) {
                    Option::Some(_) => {
                        components::set::<PrepaidAgreementAuction>(
                            target.path(), PrepaidAgreementAuctionTrait::inactive()
                        );
                    },
                    Option::None(_) => ()
                };
            } else if has_building && (unique == permitted || building_controller == permitted) {
                match components::get::<PrepaidAgreementAuction>(target.path()) {
                    Option::Some(_) => {
                        components::set::<PrepaidAgreementAuction>(
                            target.path(), PrepaidAgreementAuctionTrait::inactive()
                        );
                    },
                    Option::None(_) => ()
                };
            }

            // Update unique with new lease permitted crew
            components::set::<Unique>(use_lot_path(target), Unique { unique: permitted.into() });
        } else {
            policy_path = policy_path(target, permission);
            controller_crew = components::get::<Control>(target.path()).expect(errors::CONTROL_NOT_FOUND).controller;
        }

        let policy_data = components::get::<PrepaidPolicy>(policy_path).expect(errors::PREPAID_POLICY_NOT_FOUND);

        // Check that the term matches the policy
        assert(term >= policy_data.initial_term, errors::INVALID_AGREEMENT);
        assert(term <= config::get('MAX_POLICY_DURATION').try_into().unwrap(), errors::AGREEMENT_TOO_LONG);

        // Get controller's account address
        let controller_address = components::get::<Crew>(controller_crew.path())
            .expect(errors::CREW_NOT_FOUND).delegated_to;

        // Calculate the required SWAY payment
        let mut rate: u64 = policy_data.rate;

        if asteroid.id == 1 && target.label == entities::LOT && permission == permissions::USE_LOT {
            rate = adalia_prime_lease_price(target, policy_data.rate);
        }

        let amount = (term * rate).div_ceil(3600);

        // Confirm receipt on SWAY contract for payment to controller
        let mut memo: Array<felt252> = Default::default();
        memo.append(target.into());
        memo.append(permission.into());
        memo.append(permitted.into());
        ISwayDispatcher { contract_address: contracts::get('Sway') }.confirm_receipt(
            context.caller, controller_address, amount.into(), memo.hash()
        );

        // Create agreement
        let mut agreement_data = PrepaidAgreement {
            rate: rate,
            initial_term: policy_data.initial_term,
            notice_period: policy_data.notice_period,
            start_time: context.now,
            end_time: context.now + term,
            notice_time: 0
        };

        components::set::<PrepaidAgreement>(agreement_path(target, permission, permitted.into()), agreement_data);

        self.emit(PrepaidAgreementAccepted {
            target: target,
            permission: permission,
            permitted: permitted,
            term: term,
            rate: agreement_data.rate,
            initial_term: agreement_data.initial_term,
            notice_period: agreement_data.notice_period,
            caller_crew: caller_crew,
            caller: context.caller
        });
    }

    fn adalia_prime_lease_price(lot: Entity, rate: u64) -> u64 {
        let (_, lot_index) = lot.to_position();
        let radius = FixedTrait::new(MAX_ASTEROID_RADIUS, false);

        // Adalia Prime colony centers
        let mut centers: Array<u64> = Default::default();
        centers.append(457078); // Secondary colony (Ya'axche)
        centers.append(1096252); // Mining colony (Saline)
        centers.append(1602262); // Primary colony (Arkos)

        let mut price_mods: Array<u64> = Default::default();
        price_mods.append(2); // 2x cost reduction around Ya'axche
        price_mods.append(5); // 5x cost reduction around Saline
        price_mods.append(1); // No cost reduction around Arkos

        // Calculate smallest distance from various "centers"
        let mut price_mod = 0;
        let mut iter = 0;
        let mut closest = radius * FixedTrait::new(PI, false);

        loop {
            if iter >= centers.len() { break; }
            let dist = position::surface_distance(lot_index, *centers.at(iter), radius);

            if dist < closest {
                closest = dist;
                price_mod = *price_mods.at(iter);
            }

            iter += 1;
        };

        if closest < FixedTrait::new(85899345920, false) {
            // Within 20 km, no discount
            return rate.div_ceil(price_mod);
        } else if closest < FixedTrait::new(214748364800, false) {
            // From 20km to 50 km, 50% discount
            return rate.div_ceil(2 * price_mod);
        } else if closest < FixedTrait::new(322122547200, false) {
            // From 50km to 75 km, 75% discount
            return rate.div_ceil(4 * price_mod);
        } else if closest < FixedTrait::new(429496729600, false) {
            // From 75km to 100 km, 90% discount
            return rate.div_ceil(10 * price_mod);
        } else {
            return rate / 100;
        }
    }

}

// Tests --------------------------------------------------------------------------------------------------------------

use influence::types::{Context, Entity};

#[starknet::interface]
trait IAcceptPrepaidAgreement<TContractState> {
    fn run(
        ref self: TContractState,
        target: Entity,
        permission: u64,
        permitted: Entity,
        term: u64,
        caller_crew: Entity,
        context: Context
    );
}

#[cfg(test)]
mod tests {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use traits::{Into, TryInto};
    use starknet::{ClassHash, testing};

    use influence::components;
    use influence::components::{Control, ControlTrait, Crew, CrewTrait, Location, LocationTrait, PrepaidAgreement,
        PrepaidAgreementTrait, PrepaidAgreementAuctionSettings, PrepaidAgreementAuctionSettingsTrait, PrepaidPolicy,
        PrepaidPolicyTrait, Unique};
    use influence::components::agreements::prepaid_auction::modes as auction_modes;
    use influence::config::{entities, permissions};
    use influence::contracts::sway::{Sway, ISwayDispatcher, ISwayDispatcherTrait};
    use influence::systems::agreements::helpers::{agreement_path, auction_price, lot_use_path, use_lot_path};
    use influence::types::{ArrayHashTrait, EntityTrait};
    use influence::test::{helpers, mocks};

    use super::{AcceptPrepaidAgreement, IAcceptPrepaidAgreementLibraryDispatcher,
        IAcceptPrepaidAgreementDispatcherTrait};

    #[test]
    #[available_gas(20000000)]
    fn test_accept_prepaid() {
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        helpers::init();
        mocks::constants();
        let asteroid = mocks::adalia_prime();
        let lot = EntityTrait::from_position(asteroid.id, 1595353);

        // Deploy SWAY
        let sway_address = helpers::deploy_sway();
        let amount: u256 = (1000000 * 1000000).into();
        starknet::testing::set_contract_address(starknet::contract_address_const::<'ADMIN'>());
        ISwayDispatcher { contract_address: sway_address }.mint(starknet::contract_address_const::<'PLAYER'>(), amount);
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());

        // Move controller crew to different delegate address
        let controller_crew = influence::test::mocks::delegated_crew(1, 'PLAYER');
        let mut crew_data = components::get::<Crew>(controller_crew.path()).unwrap();
        crew_data.delegated_to = starknet::contract_address_const::<'CONTROLLER'>();
        components::set::<Crew>(controller_crew.path(), crew_data);
        components::set::<Control>(asteroid.path(), ControlTrait::new(controller_crew));

        // Create prepaid policy
        let mut policy_path: Array<felt252> = Default::default();
        policy_path.append(asteroid.into());
        policy_path.append(permissions::USE_LOT.into());
        components::set::<PrepaidPolicy>(policy_path.span(), PrepaidPolicy {
            rate: 986301369,
            initial_term: 2628000,
            notice_period: 2628000
        });

        // Generate args
        let caller_crew = influence::test::mocks::delegated_crew(2, 'PLAYER');
        components::set::<Location>(caller_crew.path(), LocationTrait::new(asteroid));

        // Send payment
        starknet::testing::set_contract_address(starknet::contract_address_const::<'PLAYER'>());
        let mut memo: Array<felt252> = Default::default();
        memo.append(lot.into());
        memo.append(permissions::USE_LOT.into());
        memo.append(caller_crew.into());
        ISwayDispatcher { contract_address: sway_address }.transfer_with_confirmation(
            starknet::contract_address_const::<'CONTROLLER'>(),
            719999999370,
            memo.hash(),
            starknet::contract_address_const::<'DISPATCHER'>()
        );

        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());

        let class_hash: ClassHash = AcceptPrepaidAgreement::TEST_CLASS_HASH.try_into().unwrap();
        IAcceptPrepaidAgreementLibraryDispatcher { class_hash: class_hash }.run(
            lot, permissions::USE_LOT, caller_crew, 2628000, caller_crew, mocks::context('PLAYER')
        );

        // Check agreement
        let agreement_data = components::get::<PrepaidAgreement>(
            agreement_path(lot, permissions::USE_LOT, caller_crew.into())
        ).unwrap();

        assert(agreement_data.rate == 986301369, 'invalid rate');
        assert(agreement_data.initial_term == 2628000, 'invalid initial term');
        assert(agreement_data.notice_period == 2628000, 'invalid notice period');
        assert(agreement_data.start_time == 0, 'invalid start time');
        assert(agreement_data.end_time == 2628000, 'invalid end time');
    }

    #[test]
    #[should_panic(expected: ('lot controlled by asteroid', 'ENTRYPOINT_FAILED'))]
    #[available_gas(25000000)]
    fn test_accept_prepaid_fail() {
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        helpers::init();
        let asteroid = mocks::asteroid();
        let lot = EntityTrait::from_position(asteroid.id, 1);

        // Deploy SWAY
        let sway_address = helpers::deploy_sway();
        let amount: u256 = (100 * 1000000).into();
        starknet::testing::set_contract_address(starknet::contract_address_const::<'ADMIN'>());
        ISwayDispatcher { contract_address: sway_address }.mint(starknet::contract_address_const::<'PLAYER'>(), amount);
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());

        // Move controller crew to different delegate address
        let controller_crew = influence::test::mocks::delegated_crew(1, 'PLAYER');
        let mut crew_data = components::get::<Crew>(controller_crew.path()).unwrap();
        crew_data.delegated_to = starknet::contract_address_const::<'CONTROLLER'>();
        components::set::<Crew>(controller_crew.path(), crew_data);
        components::set::<Control>(asteroid.path(), ControlTrait::new(controller_crew));

        // Place controlled building on lot
        let building = mocks::public_warehouse(controller_crew, 1);
        components::set::<Location>(building.path(), LocationTrait::new(lot));

        let mut unique_path: Array<felt252> = Default::default();
        unique_path.append('LotUse');
        unique_path.append(lot.into());
        components::set::<Unique>(unique_path.span(), Unique { unique: building.into() });

        // Create prepaid policy
        let mut policy_path: Array<felt252> = Default::default();
        policy_path.append(asteroid.into());
        policy_path.append(permissions::USE_LOT.into());
        components::set::<PrepaidPolicy>(policy_path.span(), PrepaidPolicy {
            rate: 1000,
            initial_term: 500 * 3600,
            notice_period: 500 * 3600
        });

        // Generate args
        let caller_crew = influence::test::mocks::delegated_crew(2, 'PLAYER');
        components::set::<Location>(caller_crew.path(), LocationTrait::new(asteroid));

        // Send payment
        starknet::testing::set_contract_address(starknet::contract_address_const::<'PLAYER'>());
        let mut memo: Array<felt252> = Default::default();
        memo.append(lot.into());
        memo.append(permissions::USE_LOT.into());
        memo.append(caller_crew.into());
        ISwayDispatcher { contract_address: sway_address }.transfer_with_confirmation(
            starknet::contract_address_const::<'CONTROLLER'>(),
            5000000,
            memo.hash(),
            starknet::contract_address_const::<'DISPATCHER'>()
        );

        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());

        let class_hash: ClassHash = AcceptPrepaidAgreement::TEST_CLASS_HASH.try_into().unwrap();
        IAcceptPrepaidAgreementLibraryDispatcher { class_hash: class_hash }.run(
            lot, permissions::USE_LOT, caller_crew, 18000000, caller_crew, mocks::context('PLAYER')
        );
    }

    #[test]
    #[available_gas(40000000)]
    fn test_accept_prepaid_with_auction() {
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        helpers::init();
        mocks::constants();
        let asteroid = mocks::adalia_prime();
        let lot = EntityTrait::from_position(asteroid.id, 1595353);

        // Deploy SWAY
        let sway_address = helpers::deploy_sway();
        let amount: u256 = (1000000 * 1000000).into();
        starknet::testing::set_contract_address(starknet::contract_address_const::<'ADMIN'>());
        ISwayDispatcher { contract_address: sway_address }.mint(starknet::contract_address_const::<'PLAYER'>(), amount);
        ISwayDispatcher { contract_address: sway_address }.mint(starknet::contract_address_const::<'PLAYER2'>(), amount);
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());

        // Move controller crew to different delegate address
        let controller_crew = influence::test::mocks::delegated_crew(1, 'PLAYER');
        let mut crew_data = components::get::<Crew>(controller_crew.path()).unwrap();
        crew_data.delegated_to = starknet::contract_address_const::<'CONTROLLER'>();
        components::set::<Crew>(controller_crew.path(), crew_data);
        components::set::<Control>(asteroid.path(), ControlTrait::new(controller_crew));

        // Create prepaid policy
        let mut policy_path: Array<felt252> = Default::default();
        policy_path.append(asteroid.into());
        policy_path.append(permissions::USE_LOT.into());
        components::set::<PrepaidPolicy>(policy_path.span(), PrepaidPolicy {
            rate: 986301369,
            initial_term: 2628000,
            notice_period: 2628000
        });

        // Generate args
        let caller_crew = influence::test::mocks::delegated_crew(2, 'PLAYER');
        components::set::<Location>(caller_crew.path(), LocationTrait::new(asteroid));

        // Send payment
        starknet::testing::set_contract_address(starknet::contract_address_const::<'PLAYER'>());
        let mut memo: Array<felt252> = Default::default();
        memo.append(lot.into());
        memo.append(permissions::USE_LOT.into());
        memo.append(caller_crew.into());
        ISwayDispatcher { contract_address: sway_address }.transfer_with_confirmation(
            starknet::contract_address_const::<'CONTROLLER'>(),
            719999999370,
            memo.hash(),
            starknet::contract_address_const::<'DISPATCHER'>()
        );

        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());

        let class_hash: ClassHash = AcceptPrepaidAgreement::TEST_CLASS_HASH.try_into().unwrap();
        IAcceptPrepaidAgreementLibraryDispatcher { class_hash: class_hash }.run(
            lot, permissions::USE_LOT, caller_crew, 2628000, caller_crew, mocks::context('PLAYER')
        );

        // Build a warehouse
        let warehouse = influence::test::mocks::public_warehouse(caller_crew, 3);
        components::set::<Location>(warehouse.path(), LocationTrait::new(lot));
        let mut lot_use_path: Array<felt252> = Default::default();
        lot_use_path.append('LotUse');
        lot_use_path.append(lot.into());
        components::set::<Unique>(lot_use_path.span(), Unique { unique: warehouse.into() });
        components::set::<PrepaidAgreementAuctionSettings>(
            asteroid.path(),
            PrepaidAgreementAuctionSettingsTrait::new(auction_modes::AUTO, 0, 604800, 2000000, 1000000)
        );

        // Fast forward to end of agreement
        starknet::testing::set_block_timestamp(2628000 + 145000); // 2628000 + 40 hours (and change)

        // Create new agreement
        let new_crew = influence::test::mocks::delegated_crew(3, 'PLAYER2');
        components::set::<Location>(new_crew.path(), LocationTrait::new(asteroid));

        // Send payment
        starknet::testing::set_contract_address(starknet::contract_address_const::<'PLAYER2'>());
        let mut memo: Array<felt252> = Default::default();
        memo.append(lot.into());
        memo.append(permissions::USE_LOT.into());
        memo.append(new_crew.into());
        ISwayDispatcher { contract_address: sway_address }.transfer_with_confirmation(
            starknet::contract_address_const::<'CONTROLLER'>(),
            719999999370,
            memo.hash(),
            starknet::contract_address_const::<'DISPATCHER'>()
        );

        // Send auction payment
        let mut memo: Array<felt252> = Default::default();
        memo.append(lot.into());
        memo.append(permissions::USE_LOT.into());
        memo.append(caller_crew.into());
        memo.append('auction_controller'.into());
        ISwayDispatcher { contract_address: sway_address }.transfer_with_confirmation(
            starknet::contract_address_const::<'CONTROLLER'>(),
            1760480,
            memo.hash(),
            starknet::contract_address_const::<'DISPATCHER'>()
        );

        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        IAcceptPrepaidAgreementLibraryDispatcher { class_hash: class_hash }.run(
            lot, permissions::USE_LOT, new_crew, 2628000, new_crew, mocks::context('PLAYER2')
        );
    }

    #[test]
    #[available_gas(30000000)]
    fn test_accept_prepaid_with_expired_ship_lot_use_requires_no_auction() {
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        helpers::init();
        mocks::constants();
        let asteroid = mocks::asteroid();
        let lot = EntityTrait::from_position(asteroid.id, 1);

        // Deploy SWAY
        let sway_address = helpers::deploy_sway();
        let amount: u256 = (100 * 1000000).into();
        starknet::testing::set_contract_address(starknet::contract_address_const::<'ADMIN'>());
        ISwayDispatcher { contract_address: sway_address }.mint(starknet::contract_address_const::<'PLAYER2'>(), amount);
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());

        let controller_crew = influence::test::mocks::delegated_crew(1, 'CONTROLLER');
        components::set::<Control>(asteroid.path(), ControlTrait::new(controller_crew));

        // Create prepaid policy
        let mut policy_path: Array<felt252> = Default::default();
        policy_path.append(asteroid.into());
        policy_path.append(permissions::USE_LOT.into());
        components::set::<PrepaidPolicy>(policy_path.span(), PrepaidPolicy {
            rate: 1000,
            initial_term: 3600,
            notice_period: 3600
        });

        let tenant = influence::test::mocks::delegated_crew(2, 'PLAYER');
        components::set::<Location>(tenant.path(), LocationTrait::new(asteroid));
        let new_crew = influence::test::mocks::delegated_crew(3, 'PLAYER2');
        components::set::<Location>(new_crew.path(), LocationTrait::new(asteroid));
        let ship = EntityTrait::new(entities::SHIP, 7);
        components::set::<Unique>(lot_use_path(lot), Unique { unique: ship.into() });
        components::set::<Unique>(use_lot_path(lot), Unique { unique: tenant.into() });
        components::set::<PrepaidAgreement>(
            agreement_path(lot, permissions::USE_LOT, tenant.into()),
            PrepaidAgreementTrait::new(1000, 3600, 3600, 0, 3600)
        );

        starknet::testing::set_block_timestamp(7200);

        starknet::testing::set_contract_address(starknet::contract_address_const::<'PLAYER2'>());
        let mut memo: Array<felt252> = Default::default();
        memo.append(lot.into());
        memo.append(permissions::USE_LOT.into());
        memo.append(new_crew.into());
        ISwayDispatcher { contract_address: sway_address }.transfer_with_confirmation(
            starknet::contract_address_const::<'CONTROLLER'>(),
            1000,
            memo.hash(),
            starknet::contract_address_const::<'DISPATCHER'>()
        );

        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        let class_hash: ClassHash = AcceptPrepaidAgreement::TEST_CLASS_HASH.try_into().unwrap();
        IAcceptPrepaidAgreementLibraryDispatcher { class_hash: class_hash }.run(
            lot, permissions::USE_LOT, new_crew, 3600, new_crew, mocks::context('PLAYER2')
        );

        let agreement = components::get::<PrepaidAgreement>(
            agreement_path(lot, permissions::USE_LOT, new_crew.into())
        ).expect('agreement missing');
        assert(agreement.end_time == 10800, 'wrong end time');

        let unique = components::get::<Unique>(use_lot_path(lot)).expect('use lot missing');
        assert(unique.unique == new_crew.into(), 'wrong use lot');
    }

    #[test]
    #[available_gas(30000000)]
    fn test_adalia_prime_rate() {
        helpers::init();
        influence::test::mocks::adalia_prime();

        let mut price = AcceptPrepaidAgreement::adalia_prime_lease_price(EntityTrait::from_position(1, 457078), 1000);
        assert(price == 500, 'invalid price');

        price = AcceptPrepaidAgreement::adalia_prime_lease_price(EntityTrait::from_position(1, 1096252), 1000);
        assert(price == 200, 'invalid price');

        price = AcceptPrepaidAgreement::adalia_prime_lease_price(EntityTrait::from_position(1, 1598602), 1000);
        assert(price == 1000, 'invalid price');

        price = AcceptPrepaidAgreement::adalia_prime_lease_price(EntityTrait::from_position(1, 1580548), 1000);
        assert(price == 500, 'invalid price');

        price = AcceptPrepaidAgreement::adalia_prime_lease_price(EntityTrait::from_position(1, 1547367), 1000);
        assert(price == 250, 'invalid price');

        price = AcceptPrepaidAgreement::adalia_prime_lease_price(EntityTrait::from_position(1, 1501732), 1000);
        assert(price == 100, 'invalid price');

        price = AcceptPrepaidAgreement::adalia_prime_lease_price(EntityTrait::from_position(1, 1470059), 1000);
        assert(price == 10, 'invalid price');
    }

    #[test]
    #[available_gas(30000000)]
    fn test_auction_price() {
        let settings = PrepaidAgreementAuctionSettingsTrait::defaults();
        let mut price = auction_price(settings, 0);
        assert(price == 100000000000000000, 'invalid price');

        price = auction_price(settings, 302400);
        assert(price == 49700598802898204, 'invalid price');

        price = auction_price(settings, 601200);
        assert(price == 1000000, 'invalid price');

        price = auction_price(settings, 604800);
        assert(price == 1000000, 'invalid price');
    }
}
