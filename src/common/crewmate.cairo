use array::SpanTrait;

use influence::components::crewmate::{classes, crewmate_traits};
use influence::config::errors;

fn validate_adalian(
    class: u64,
    impactful: Span<u64>,
    cosmetic: Span<u64>,
    gender: u64,
    body: u64,
    face: u64,
    hair: u64,
    hair_color: u64,
    clothes: u64,
    name: felt252
) {
    assert(name != 0, errors::NAME_REQUIRED);
    assert((class >= 1) && (class <= 5), 'invalid class');
    assert(impactful.len() == 1, 'invalid number of impactful');
    assert(cosmetic.len() == 3, 'invalid number of cosmetic');
    assert_drive(*cosmetic.at(0));
    assert_adalian_drive_dependent(*cosmetic.at(0), *cosmetic.at(1));
    assert_adalian_cosmetic(*cosmetic.at(2));
    assert_adalian_impactful(class, *impactful.at(0));
    assert((gender >= 1) && (gender < 3), 'invalid gender');
    assert((face >= 0) && (face < 13 - gender * 5), 'invalid face');
    let body_end = gender * 6 + 1;
    assert((body >= body_end - 6) && (body < body_end), 'invalid body');
    let clothes_end = class * 2 + 32;
    assert((clothes >= clothes_end - 2) && (clothes < clothes_end), 'invalid clothes');
    assert((hair_color >= 1) && (hair_color < 6), 'invalid hair color');

    if hair != 0 {
        let hair_end = gender * 6;
        assert((hair >= hair_end - 6) && (hair < hair_end * 6), 'invalid hair');
    }
}

fn assert_drive(t: u64) {
    if t == crewmate_traits::DRIVE_SURVIVAL { return; }
    if t == crewmate_traits::DRIVE_SERVICE { return; }
    if t == crewmate_traits::DRIVE_GLORY { return; }
    if t == crewmate_traits::DRIVE_COMMAND { return; }

    assert(false, 'invalid drive');
}

fn assert_adalian_drive_dependent(drive: u64, t: u64) {
    if drive == crewmate_traits::DRIVE_SURVIVAL {
        if t == crewmate_traits::COMMUNAL { return; }
        if t == crewmate_traits::IMPARTIAL { return; }
        if t == crewmate_traits::ENTERPRISING { return; }
        if t == crewmate_traits::OPPORTUNISTIC { return; }
    } else if drive == crewmate_traits::DRIVE_SERVICE {
        if t == crewmate_traits::RIGHTEOUS { return; }
        if t == crewmate_traits::COMMUNAL { return; }
        if t == crewmate_traits::IMPARTIAL { return; }
        if t == crewmate_traits::ENTERPRISING { return; }
    } else if drive == crewmate_traits::DRIVE_GLORY {
        if t == crewmate_traits::RIGHTEOUS { return; }
        if t == crewmate_traits::IMPARTIAL { return; }
        if t == crewmate_traits::ENTERPRISING { return; }
        if t == crewmate_traits::OPPORTUNISTIC { return; }
    } else if drive == crewmate_traits::DRIVE_COMMAND {
        if t == crewmate_traits::RIGHTEOUS { return; }
        if t == crewmate_traits::COMMUNAL { return; }
        if t == crewmate_traits::IMPARTIAL { return; }
        if t == crewmate_traits::OPPORTUNISTIC { return; }
    }

    assert(false, 'invalid drive dependent');
}

fn assert_adalian_cosmetic(t: u64) {
    if t == crewmate_traits::ADVENTUROUS { return; }
    if t == crewmate_traits::AMBITIOUS { return; }
    if t == crewmate_traits::ARROGANT { return; }
    if t == crewmate_traits::CAUTIOUS { return; }
    if t == crewmate_traits::CREATIVE { return; }
    if t == crewmate_traits::CURIOUS { return; }
    if t == crewmate_traits::FRANTIC { return; }
    if t == crewmate_traits::INDEPENDENT { return; }
    if t == crewmate_traits::IRRATIONAL { return; }
    if t == crewmate_traits::PRAGMATIC { return; }
    if t == crewmate_traits::RECKLESS { return; }
    if t == crewmate_traits::SERIOUS { return; }

    assert(false, 'invalid cosmetic');
}

fn assert_adalian_impactful(class: u64, t: u64) {
    if class == classes::PILOT {
        if t == crewmate_traits::NAVIGATOR { return; }
        if t == crewmate_traits::BUSTER { return; }
        if t == crewmate_traits::OPERATOR { return; }
    } else if class == classes::ENGINEER {
        if t == crewmate_traits::REFINER { return; }
        if t == crewmate_traits::MECHANIC { return; }
        if t == crewmate_traits::BUILDER { return; }
    } else if class == classes::MINER {
        if t == crewmate_traits::SURVEYOR { return; }
        if t == crewmate_traits::RECYCLER { return; }
        if t == crewmate_traits::PROSPECTOR { return; }
    } else if class == classes::MERCHANT {
        if t == crewmate_traits::HAULER { return; }
        if t == crewmate_traits::MOGUL { return; }
        if t == crewmate_traits::LOGISTICIAN { return; }
    } else if class == classes::SCIENTIST {
        if t == crewmate_traits::DIETITIAN { return; }
        if t == crewmate_traits::SCHOLAR { return; }
        if t == crewmate_traits::EXPERIMENTER { return; }
    }

    assert(false, 'invalid impactful');
}
