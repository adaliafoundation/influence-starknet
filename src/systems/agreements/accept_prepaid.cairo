#[starknet::contract]
mod AcceptPrepaidAgreement {
    use array::{Array, ArrayTrait};
    use option::OptionTrait;
    use starknet::{contract_address_const, ContractAddress};
    use traits::{Into, TryInto};

    use cubit::f64::{FixedTrait, trig::PI, comp};
    use cubit::f128::{FixedTrait as FixedTrait128};

    use influence::{components, config, contracts};
    use influence::common::{crew::CrewDetailsTrait, math::RoundedDivTrait, position};
    use influence::components::{Celestial, Crew, CrewTrait, Control, ControlTrait, PrepaidPolicy, PrepaidPolicyTrait,
        PrepaidAgreement, PrepaidAgreementTrait, Unique};
    use influence::config::{entities, errors, permissions, MAX_ASTEROID_RADIUS};
    use influence::contracts::sway::{ISwayDispatcher, ISwayDispatcherTrait};
    use influence::systems::agreements::helpers::agreement_path;
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
            let mut lot_use_path: Array<felt252> = Default::default();
            lot_use_path.append('LotUse');
            lot_use_path.append(target.into());
            let mut has_building = false;

            match components::get::<Unique>(lot_use_path.span()) {
                Option::Some(unique_data) => {
                    let lot_use: Entity = unique_data.unique.try_into().unwrap();
                    has_building = lot_use.label == entities::BUILDING;
                    assert(!controller_crew.controls(lot_use), 'lot controlled by asteroid');
                },
                Option::None(_) => ()
            };

            // Ensure use lot agreements are unique / you can't lease over the top of someone else's lease
            let mut unique_path: Array<felt252> = Default::default();
            unique_path.append('UseLot');
            unique_path.append(target.into());
            let mut unique: Entity = EntityTrait::new(entities::CREW, 0);

            // Allow creating a new agreement if caller crew is current tenant OR as long as the current unique
            // tenant no longer has permission to use the lot
            match components::get::<Unique>(unique_path.span()) {
                Option::Some(unique_data) => {
                    unique = unique_data.unique.try_into().unwrap();
                    assert(unique == permitted || !unique.can(target, permissions::USE_LOT), 'lot already leased');
                },
                Option::None(_) => ()
            };

            // If the current / former user no longer has permissions, and a building is present, check if within
            // the auction period (7 days). If so, find the auction price and ensure there's a receipt for SWAY tx
            // sending that much to the previous tenant.
            if unique.id != 0 && has_building {
                match components::get::<PrepaidAgreement>(agreement_path(target, permission, unique.into())) {
                    Option::Some(current_data) => {
                        if context.now < current_data.end_time + 604800 {
                            let mut elapsed_hours = (context.now - current_data.end_time) / 3600;
                            let mut memo: Array<felt252> = Default::default();
                            memo.append(target.into());
                            memo.append(permission.into());
                            memo.append(unique.into());
                            memo.append('auction'.into());

                            let delegated_to = components::get::<Crew>(unique.path())
                                .expect(errors::CREW_NOT_FOUND).delegated_to;
                            ISwayDispatcher { contract_address: contracts::get('Sway') }.confirm_receipt(
                                context.caller, delegated_to, auction_price(elapsed_hours).into(), memo.hash()
                            );
                        }
                    },
                    Option::None(_) => ()
                };
            }

            // Update unique with new lease permitted crew
            components::set::<Unique>(unique_path.span(), Unique { unique: permitted.into() });
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

    fn auction_price(elapsed: u64) -> u64 {
        if (elapsed < 84) {
            if (elapsed < 42) {
                if (elapsed < 21) {
                    if (elapsed == 0) { return 1000000000000; }
                    if (elapsed == 1) { return 848342898244; }
                    if (elapsed == 2) { return 719685673001; }
                    if (elapsed == 3) { return 610540229659; }
                    if (elapsed == 4) { return 517947467923; }
                    if (elapsed == 5) { return 439397056076; }
                    if (elapsed == 6) { return 372759372031; }
                    if (elapsed == 7) { return 316227766017; }
                    if (elapsed == 8) { return 268269579528; }
                    if (elapsed == 9) { return 227584592607; }
                    if (elapsed == 10) { return 193069772888; }
                    if (elapsed == 11) { return 163789370695; }
                    if (elapsed == 12) { return 138949549437; }
                    if (elapsed == 13) { return 117876863479; }
                    if (elapsed == 14) { return 100000000000; }
                    if (elapsed == 15) { return 84834289824; }
                    if (elapsed == 16) { return 71968567300; }
                    if (elapsed == 17) { return 61054022966; }
                    if (elapsed == 18) { return 51794746792; }
                    if (elapsed == 19) { return 43939705608; }
                    if (elapsed == 20) { return 37275937203; }
                } else {
                    if (elapsed == 21) { return 31622776602; }
                    if (elapsed == 22) { return 26826957953; }
                    if (elapsed == 23) { return 22758459261; }
                    if (elapsed == 24) { return 19306977289; }
                    if (elapsed == 25) { return 16378937070; }
                    if (elapsed == 26) { return 13894954944; }
                    if (elapsed == 27) { return 11787686348; }
                    if (elapsed == 28) { return 10000000000; }
                    if (elapsed == 29) { return 8483428982; }
                    if (elapsed == 30) { return 7196856730; }
                    if (elapsed == 31) { return 6105402297; }
                    if (elapsed == 32) { return 5179474679; }
                    if (elapsed == 33) { return 4393970561; }
                    if (elapsed == 34) { return 3727593720; }
                    if (elapsed == 35) { return 3162277660; }
                    if (elapsed == 36) { return 2682695795; }
                    if (elapsed == 37) { return 2275845926; }
                    if (elapsed == 38) { return 1930697729; }
                    if (elapsed == 39) { return 1637893707; }
                    if (elapsed == 40) { return 1389495494; }
                    if (elapsed == 41) { return 1178768635; }
                }
            } else {
                if (elapsed < 63) {
                    if (elapsed == 42) { return 1000000000; }
                    if (elapsed == 43) { return 848342898; }
                    if (elapsed == 44) { return 719685673; }
                    if (elapsed == 45) { return 610540230; }
                    if (elapsed == 46) { return 517947468; }
                    if (elapsed == 47) { return 439397056; }
                    if (elapsed == 48) { return 372759372; }
                    if (elapsed == 49) { return 316227766; }
                    if (elapsed == 50) { return 268269580; }
                    if (elapsed == 51) { return 227584593; }
                    if (elapsed == 52) { return 193069773; }
                    if (elapsed == 53) { return 163789371; }
                    if (elapsed == 54) { return 138949549; }
                    if (elapsed == 55) { return 117876863; }
                    if (elapsed == 56) { return 100000000; }
                    if (elapsed == 57) { return 84834290; }
                    if (elapsed == 58) { return 71968567; }
                    if (elapsed == 59) { return 61054023; }
                    if (elapsed == 60) { return 51794747; }
                    if (elapsed == 61) { return 43939706; }
                    if (elapsed == 62) { return 37275937; }
                } else {
                    if (elapsed == 63) { return 31622777; }
                    if (elapsed == 64) { return 26826958; }
                    if (elapsed == 65) { return 22758459; }
                    if (elapsed == 66) { return 19306977; }
                    if (elapsed == 67) { return 16378937; }
                    if (elapsed == 68) { return 13894955; }
                    if (elapsed == 69) { return 11787686; }
                    if (elapsed == 70) { return 10000000; }
                    if (elapsed == 71) { return 8483429; }
                    if (elapsed == 72) { return 7196857; }
                    if (elapsed == 73) { return 6105402; }
                    if (elapsed == 74) { return 5179475; }
                    if (elapsed == 75) { return 4393971; }
                    if (elapsed == 76) { return 3727594; }
                    if (elapsed == 77) { return 3162278; }
                    if (elapsed == 78) { return 2682696; }
                    if (elapsed == 79) { return 2275846; }
                    if (elapsed == 80) { return 1930698; }
                    if (elapsed == 81) { return 1637894; }
                    if (elapsed == 82) { return 1389495; }
                    if (elapsed == 83) { return 1178769; }
                }
            }
        } else {
            if (elapsed < 126) {
                if (elapsed < 105) {
                    if (elapsed == 84) { return 1000000; }
                    if (elapsed == 85) { return 848343; }
                    if (elapsed == 86) { return 719686; }
                    if (elapsed == 87) { return 610540; }
                    if (elapsed == 88) { return 517947; }
                    if (elapsed == 89) { return 439397; }
                    if (elapsed == 90) { return 372759; }
                    if (elapsed == 91) { return 316228; }
                    if (elapsed == 92) { return 268270; }
                    if (elapsed == 93) { return 227585; }
                    if (elapsed == 94) { return 193070; }
                    if (elapsed == 95) { return 163789; }
                    if (elapsed == 96) { return 138950; }
                    if (elapsed == 97) { return 117877; }
                    if (elapsed == 98) { return 100000; }
                    if (elapsed == 99) { return 84834; }
                    if (elapsed == 100) { return 71969; }
                    if (elapsed == 101) { return 61054; }
                    if (elapsed == 102) { return 51795; }
                    if (elapsed == 103) { return 43940; }
                    if (elapsed == 104) { return 37276; }
                } else {
                    if (elapsed == 105) { return 31623; }
                    if (elapsed == 106) { return 26827; }
                    if (elapsed == 107) { return 22758; }
                    if (elapsed == 108) { return 19307; }
                    if (elapsed == 109) { return 16379; }
                    if (elapsed == 110) { return 13895; }
                    if (elapsed == 111) { return 11788; }
                    if (elapsed == 112) { return 10000; }
                    if (elapsed == 113) { return 8483; }
                    if (elapsed == 114) { return 7197; }
                    if (elapsed == 115) { return 6105; }
                    if (elapsed == 116) { return 5179; }
                    if (elapsed == 117) { return 4394; }
                    if (elapsed == 118) { return 3728; }
                    if (elapsed == 119) { return 3162; }
                    if (elapsed == 120) { return 2683; }
                    if (elapsed == 121) { return 2276; }
                    if (elapsed == 122) { return 1931; }
                    if (elapsed == 123) { return 1638; }
                    if (elapsed == 124) { return 1389; }
                    if (elapsed == 125) { return 1179; }
                }
            } else {
                if (elapsed < 147) {
                    if (elapsed == 126) { return 1000; }
                    if (elapsed == 127) { return 848; }
                    if (elapsed == 128) { return 720; }
                    if (elapsed == 129) { return 611; }
                    if (elapsed == 130) { return 518; }
                    if (elapsed == 131) { return 439; }
                    if (elapsed == 132) { return 373; }
                    if (elapsed == 133) { return 316; }
                    if (elapsed == 134) { return 268; }
                    if (elapsed == 135) { return 228; }
                    if (elapsed == 136) { return 193; }
                    if (elapsed == 137) { return 164; }
                    if (elapsed == 138) { return 139; }
                    if (elapsed == 139) { return 118; }
                    if (elapsed == 140) { return 100; }
                    if (elapsed == 141) { return 85; }
                    if (elapsed == 142) { return 72; }
                    if (elapsed == 143) { return 61; }
                    if (elapsed == 144) { return 52; }
                    if (elapsed == 145) { return 44; }
                    if (elapsed == 146) { return 37; }
                } else {
                    if (elapsed == 147) { return 32; }
                    if (elapsed == 148) { return 27; }
                    if (elapsed == 149) { return 23; }
                    if (elapsed == 150) { return 19; }
                    if (elapsed == 151) { return 16; }
                    if (elapsed == 152) { return 14; }
                    if (elapsed == 153) { return 12; }
                    if (elapsed == 154) { return 10; }
                    if (elapsed == 155) { return 8; }
                    if (elapsed == 156) { return 7; }
                    if (elapsed == 157) { return 6; }
                    if (elapsed == 158) { return 5; }
                    if (elapsed == 159) { return 4; }
                    if (elapsed == 160) { return 4; }
                    if (elapsed == 161) { return 3; }
                    if (elapsed == 162) { return 3; }
                    if (elapsed == 163) { return 2; }
                    if (elapsed == 164) { return 2; }
                    if (elapsed == 165) { return 2; }
                    if (elapsed == 166) { return 1; }
                    if (elapsed == 167) { return 1; }
                    if (elapsed == 168) { return 0; }
                }
            }
        }

        return 0; // Default once auction has expired
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
        PrepaidPolicy, PrepaidPolicyTrait, Unique};
    use influence::config::{entities, permissions};
    use influence::contracts::sway::{Sway, ISwayDispatcher, ISwayDispatcherTrait};
    use influence::systems::agreements::helpers::agreement_path;
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
    #[available_gas(15000000)]
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
        memo.append('auction'.into());
        ISwayDispatcher { contract_address: sway_address }.transfer_with_confirmation(
            starknet::contract_address_const::<'PLAYER'>(),
            1389495494,
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
        let mut price = AcceptPrepaidAgreement::auction_price(0);
        assert(price == 1000000000000, 'invalid price');

        price = AcceptPrepaidAgreement::auction_price(49);
        assert(price == 316227766, 'invalid price');

        price = AcceptPrepaidAgreement::auction_price(168);
        assert(price == 0, 'invalid price');

        price = AcceptPrepaidAgreement::auction_price(169);
        assert(price == 0, 'invalid price');
    }
}
