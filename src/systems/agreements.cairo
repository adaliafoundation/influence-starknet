mod accept_contract;
mod accept_prepaid;
mod accept_prepaid_merkle;
mod cancel_prepaid_auction;
mod cancel_prepaid;
mod configure_prepaid_auction;
mod extend_prepaid;
mod remove_from_whitelist;
mod remove_account_from_whitelist;
mod start_prepaid_auction;
mod transfer_prepaid;
mod whitelist;
mod whitelist_account;

use whitelist::Whitelist;
use remove_from_whitelist::RemoveFromWhitelist;

mod helpers {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use traits::{Into, TryInto};

    use influence::components;
    use influence::components::{PrepaidAgreementAuctionSettings, PrepaidAgreementAuctionSettingsTrait};
    use influence::config::{entities, permissions};
    use influence::types::{Entity, EntityTrait};

    const AUCTION_STEPS: u64 = 168;
    const AUCTION_STEP_SECONDS: u64 = 3600;
    const AUCTION_DESCENDING_PERIOD: u64 = 604800;

    fn auction_price_at_step(step: u64) -> u64 {
        if step < 84 {
            if step < 42 {
                if step < 21 {
                    if step == 0 { return 1000000000000000000; }
                    if step == 1 { return 847507816922201829; }
                    if step == 2 { return 718269499744236373; }
                    if step == 3 { return 608739015690039773; }
                    if step == 4 { return 515911074262835575; }
                    if step == 5 { return 437238668274483725; }
                    if step == 6 { return 370563189223278490; }
                    if step == 7 { return 314055199530349540; }
                    if step == 8 { return 266164236547033044; }
                    if step == 9 { return 225576271058740502; }
                    if step == 10 { return 191177653034444020; }
                    if step == 11 { return 162024555367531806; }
                    if step == 12 { return 137317077207327299; }
                    if step == 13 { return 116377296330119398; }
                    if step == 14 { return 98630668352047662; }
                    if step == 15 { return 83590262416621616; }
                    if step == 16 { return 70843400816664960; }
                    if step == 17 { return 60040335969476251; }
                    if step == 18 { return 50884654064766367; }
                    if step == 19 { return 43125142081271588; }
                    if step == 20 { return 36548895019758263; }
                } else {
                    if step == 21 { return 30975474229114060; }
                    if step == 22 { return 26251956542046379; }
                    if step == 23 { return 22248738378886241; }
                    if step == 24 { return 18855979692763086; }
                    if step == 25 { return 15980590185343013; }
                    if step == 26 { return 13543675101108422; }
                    if step == 27 { return 11478370518043979; }
                    if step == 28 { return 9728008739571616; }
                    if step == 29 { return 8244563449874440; }
                    if step == 30 { return 6987331970879664; }
                    if step == 31 { return 5921818464750930; }
                    if step == 32 { return 5018787439270645; }
                    if step == 33 { return 4253461586252832; }
                    if step == 34 { return 3604841943327583; }
                    if step == 35 { return 3055131725739148; }
                    if step == 36 { return 2589248019290944; }
                    if step == 37 { return 2194407936299403; }
                    if step == 38 { return 1859777879529861; }
                    if step == 39 { return 1576176290640554; }
                    if step == 40 { return 1335821727165310; }
                    if step == 41 { return 1132119355787117; }
                }
            } else {
                if step < 63 {
                    if step == 42 { return 959480003718509; }
                    if step == 43 { return 813166803331979; }
                    if step == 44 { return 689165222285491; }
                    if step == 45 { return 584072913037881; }
                    if step == 46 { return 495006359452125; }
                    if step == 47 { return 419521759061877; }
                    if step == 48 { return 355547970173893; }
                    if step == 49 { return 301329684013196; }
                    if step == 50 { return 255379262671881; }
                    if step == 51 { return 216435921394247; }
                    if step == 52 { return 183431135244384; }
                    if step == 53 { return 155459320986529; }
                    if step == 54 { return 131752989749501; }
                    if step == 55 { return 111661688715573; }
                    if step == 56 { return 94634154037181; }
                    if step == 57 { return 80203185294331; }
                    if step == 58 { return 67972826479005; }
                    if step == 59 { return 57607501779253; }
                    if step == 60 { return 48822808071277; }
                    if step == 61 { return 41377711484499; }
                    if step == 62 { return 35067933929465; }
                } else {
                    if step == 63 { return 29720348128532; }
                    if step == 64 { return 25188227360580; }
                    if step == 65 { return 21347219582505; }
                    if step == 66 { return 18091935465728; }
                    if step == 67 { return 15333056730456; }
                    if step == 68 { return 12994885436373; }
                    if step == 69 { return 11013266987335; }
                    if step == 70 { return 9333829861617; }
                    if step == 71 { return 7910493769543; }
                    if step == 72 { return 6704205305402; }
                    if step == 73 { return 5681866402579; }
                    if step == 74 { return 4815426190893; }
                    if step == 75 { return 4081111338594; }
                    if step == 76 { return 3458773761188; }
                    if step == 77 { return 2931337799572; }
                    if step == 78 { return 2484331699177; }
                    if step == 79 { return 2105490534880; }
                    if step == 80 { return 1784419686766; }
                    if step == 81 { return 1512309633204; }
                    if step == 82 { return 1281694235747; }
                    if step == 83 { return 1086245883700; }
                }
            }
        } else {
            if step < 126 {
                if step < 105 {
                    if step == 84 { return 920601877535; }
                    if step == 85 { return 780217287484; }
                    if step == 86 { return 661240250041; }
                    if step == 87 { return 560406280773; }
                    if step == 88 { return 474948703607; }
                    if step == 89 { return 402522738944; }
                    if step == 90 { return 341141167744; }
                    if step == 91 { return 289119806337; }
                    if step == 92 { return 245031295898; }
                    if step == 93 { return 207665938664; }
                    if step == 94 { return 175998506326; }
                    if step == 95 { return 149160109878; }
                    if step == 96 { return 126414359094; }
                    if step == 97 { return 107137157504; }
                    if step == 98 { return 90799578467; }
                    if step == 99 { return 76953352524; }
                    if step == 100 { return 65218567802; }
                    if step == 101 { return 55273246021; }
                    if step == 102 { return 46844508069; }
                    if step == 103 { return 39701086769; }
                    if step == 104 { return 33646981377; }
                } else {
                    if step == 105 { return 28516079732; }
                    if step == 106 { return 24167600481; }
                    if step == 107 { return 20482230324; }
                    if step == 108 { return 17358850307; }
                    if step == 109 { return 14711761328; }
                    if step == 110 { return 12468332726; }
                    if step == 111 { return 10567009449; }
                    if step == 112 { return 8955623110; }
                    if step == 113 { return 7589960591; }
                    if step == 114 { return 6432550931; }
                    if step == 115 { return 5451637197; }
                    if step == 116 { return 4620305139; }
                    if step == 117 { return 3915744722; }
                    if step == 118 { return 3318624261; }
                    if step == 119 { return 2812560002; }
                    if step == 120 { return 2383666587; }
                    if step == 121 { return 2020176066; }
                    if step == 122 { return 1712115007; }
                    if step == 123 { return 1451030852; }
                    if step == 124 { return 1229759990; }
                    if step == 125 { return 1042231204; }
                }
            } else {
                if step < 147 {
                    if step == 126 { return 883299092; }
                    if step == 127 { return 748602885; }
                    if step == 128 { return 634446797; }
                    if step == 129 { return 537698620; }
                    if step == 130 { return 455703783; }
                    if step == 131 { return 386212519; }
                    if step == 132 { return 327318128; }
                    if step == 133 { return 277404672; }
                    if step == 134 { return 235102628; }
                    if step == 135 { return 199251315; }
                    if step == 136 { return 168867047; }
                    if step == 137 { return 143116142; }
                    if step == 138 { return 121292049; }
                    if step == 139 { return 102795960; }
                    if step == 140 { return 87120379; }
                    if step == 141 { return 73835202; }
                    if step == 142 { return 62575911; }
                    if step == 143 { return 53033574; }
                    if step == 144 { return 44946368; }
                    if step == 145 { return 38092398; }
                    if step == 146 { return 32283605; }
                } else {
                    if step == 147 { return 27360608; }
                    if step == 148 { return 23188329; }
                    if step == 149 { return 19652290; }
                    if step == 150 { return 16655469; }
                    if step == 151 { return 14115640; }
                    if step == 152 { return 11963115; }
                    if step == 153 { return 10138834; }
                    if step == 154 { return 8592741; }
                    if step == 155 { return 7282415; }
                    if step == 156 { return 6171903; }
                    if step == 157 { return 5230736; }
                    if step == 158 { return 4433090; }
                    if step == 159 { return 3757078; }
                    if step == 160 { return 3184153; }
                    if step == 161 { return 2698595; }
                    if step == 162 { return 2287080; }
                    if step == 163 { return 1938318; }
                    if step == 164 { return 1642740; }
                    if step == 165 { return 1392235; }
                    if step == 166 { return 1179930; }
                    if step == 167 { return 1000000; }
                }
            }
        }
        return 1000000;
    }

    fn agreement_path(target: Entity, permission: u64, permitted: felt252) -> Span<felt252> {
        if target.label == entities::ASTEROID {
            assert(permission == permissions::USE_LOT, 'invalid permission');
        } else if target.label == entities::LOT {
            assert(permission == permissions::USE_LOT, 'invalid permission');
        } else if target.label == entities::BUILDING {
            assert(
                permission == permissions::RUN_PROCESS ||
                permission == permissions::ADD_PRODUCTS ||
                permission == permissions::REMOVE_PRODUCTS ||
                permission == permissions::STATION_CREW ||
                permission == permissions::RECRUIT_CREWMATE ||
                permission == permissions::DOCK_SHIP ||
                permission == permissions::BUY ||
                permission == permissions::SELL ||
                permission == permissions::LIMIT_BUY ||
                permission == permissions::LIMIT_SELL ||
                permission == permissions::EXTRACT_RESOURCES ||
                permission == permissions::ASSEMBLE_SHIP,
                'invalid permission'
            );
        } else if target.label == entities::SHIP {
            assert(
                permission == permissions::ADD_PRODUCTS ||
                permission == permissions::REMOVE_PRODUCTS ||
                permission == permissions::STATION_CREW,
                'invalid permission'
            );
        } else {
            assert(false, 'invalid permission');
        }

        let mut path: Array<felt252> = Default::default();
        path.append(target.into());
        path.append(permission.into());
        path.append(permitted);
        return path.span();
    }

    fn use_lot_path(lot: Entity) -> Span<felt252> {
        let mut path: Array<felt252> = Default::default();
        path.append('UseLot');
        path.append(lot.into());
        return path.span();
    }

    fn lot_use_path(lot: Entity) -> Span<felt252> {
        let mut path: Array<felt252> = Default::default();
        path.append('LotUse');
        path.append(lot.into());
        return path.span();
    }

    fn auction_settings(asteroid: Entity) -> PrepaidAgreementAuctionSettings {
        match components::get::<PrepaidAgreementAuctionSettings>(asteroid.path()) {
            Option::Some(settings) => settings,
            Option::None(_) => PrepaidAgreementAuctionSettingsTrait::defaults()
        }
    }

    fn auction_price(settings: PrepaidAgreementAuctionSettings, elapsed: u64) -> u64 {
        if elapsed < settings.grace_period {
            return auction_price_at_step(0);
        }

        let descending_elapsed = elapsed - settings.grace_period;
        if descending_elapsed >= AUCTION_DESCENDING_PERIOD {
            return auction_price_at_step(AUCTION_STEPS - 1);
        }

        let step = descending_elapsed / AUCTION_STEP_SECONDS;
        return auction_price_at_step(step);
    }
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use array::{Array, ArrayTrait, SpanTrait};
    use clone::Clone;
    use option::OptionTrait;
    use traits::Into;

    use influence::config::{entities, permissions};
    use influence::components;
    use influence::components::{Control, ControlTrait, Crew, CrewTrait, Location, LocationTrait,
        WhitelistAgreement, WhitelistAgreementTrait};
    use influence::types::{Context, Entity, EntityTrait};
    use influence::test::{helpers, mocks};

    use super::{helpers::agreement_path, RemoveFromWhitelist, Whitelist};

    #[test]
    #[available_gas(10000000)]
    fn test_grant_permission() {
        let asteroid = mocks::asteroid();
        let entity = EntityTrait::new(entities::BUILDING, 1);
        let permission = permissions::STATION_CREW;
        let crew = mocks::delegated_crew(2, 'PLAYER2');
        let caller_crew = mocks::delegated_crew(3, 'PLAYER');

        // Set controller and location
        components::set::<Control>(entity.path(), ControlTrait::new(caller_crew));
        components::set::<Location>(caller_crew.path(), LocationTrait::new(asteroid));
        components::set::<Location>(entity.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1)));

        let mut state = Whitelist::contract_state_for_testing();
        Whitelist::run(ref state, entity, permission, crew, caller_crew, mocks::context('PLAYER'));

        let agreement = components::get::<WhitelistAgreement>(agreement_path(entity, permission, crew.into()));
        assert(agreement.is_some(), 'agreement not set');
    }

    #[test]
    #[available_gas(10000000)]
    fn test_revoke_permission() {
        let asteroid = mocks::asteroid();
        let entity = EntityTrait::new(entities::BUILDING, 1);
        let permission = permissions::STATION_CREW;
        let crew = mocks::delegated_crew(2, 'PLAYER2');
        let caller_crew = mocks::delegated_crew(3, 'PLAYER');

        // Delegate and set caller to owner
        components::set::<Control>(entity.path(), ControlTrait::new(caller_crew));
        components::set::<Location>(caller_crew.path(), LocationTrait::new(asteroid));
        components::set::<Location>(entity.path(), LocationTrait::new(EntityTrait::from_position(asteroid.id, 1)));

        let mut state = Whitelist::contract_state_for_testing();
        Whitelist::run(ref state, entity, permission, crew, caller_crew, mocks::context('PLAYER'));
        let mut state = RemoveFromWhitelist::contract_state_for_testing();
        RemoveFromWhitelist::run(ref state, entity, permission, crew, caller_crew, mocks::context('PLAYER'));

        let agreement = components::get::<WhitelistAgreement>(agreement_path(entity, permission, crew.into()));
        assert(agreement.is_none(), 'agreement set');
    }
}
