use array::{ArrayTrait, SpanTrait};
use option::OptionTrait;
use traits::{Into, TryInto};
use starknet::ContractAddress;
use influence::{components, config};
use influence::common::{missions, nft};
use influence::common::missions::Assignment;
use influence::components::{Building, Celestial, Location};
use influence::components::building::{statuses as building_status};
use influence::components::building_type::types as buildings;
use influence::components::celestial::statuses as scans;
use influence::config::entities;
use influence::types::{Context, Entity, EntityTrait};
use influence::common::mission_evidence::{hash, key, parse, segment};

fn asteroid_id(entity: Entity) -> u64 {
    let (id, _) = entity.to_position();
    id
}

fn assignment(asteroid: Entity) -> Assignment {
    Assignment { campaign: config::get('COLONIZATION_CAMPAIGN'), subject: asteroid, mission: 0 }
}

fn colonizer(a: Assignment) -> ContractAddress {
    missions::state(a, 'Colonizer').try_into().unwrap()
}

fn assert_owner(a: Assignment, context: Context) {
    let owner = colonizer(a);
    assert(owner.is_non_zero() && context.caller == owner, 'not colonizer');
    nft::assert_owner('Asteroid', a.subject, owner);
}

fn branch(kind: u64) -> u32 {
    if kind == buildings::HABITAT {
        1
    } else if kind == buildings::SPACEPORT {
        2
    } else if kind == buildings::MARKETPLACE {
        3
    } else {
        0
    }
}

// Status is deliberately excluded: finishing construction changes it, but rebuilding
// changes the construction timestamps and cannot reuse an earlier use receipt.
fn fingerprint(building: Entity, data: Building) -> felt252 {
    hash(@(building, data.building_type, data.planned_at, data.finish_time))
}

fn qualifying_data(a: Assignment, building: Entity, data: Building) -> bool {
    building.label == entities::BUILDING
        && data.status == building_status::OPERATIONAL
        && branch(data.building_type) != 0
        && missions::state(a, key('Built', building, 0)) == fingerprint(building, data)
        && asteroid_id(building) == a.subject.id
}

fn qualifying(a: Assignment, building: Entity) -> bool {
    match components::get::<Building>(building.path()) {
        Option::Some(data) => qualifying_data(a, building, data),
        Option::None(_) => false
    }
}

fn operational_selection(a: Assignment, mission: u32, id: u64) -> bool {
    if id == 0 {
        return false;
    }
    let building = EntityTrait::new(entities::BUILDING, id);
    match components::get::<Building>(building.path()) {
        Option::Some(data) => {
            branch(data.building_type) == mission
                && qualifying_data(a, building, data)
                && missions::state(a, key('Used', building, 0)) == fingerprint(building, data)
        },
        Option::None(_) => false
    }
}

fn operational_branch(a: Assignment, mission: u32) -> bool {
    operational_selection(a, mission, missions::state(a, mission.into()).try_into().unwrap())
}

fn operational_colony(a: Assignment) -> bool {
    operational_branch(a, 1) && operational_branch(a, 2) && operational_branch(a, 3)
}

fn earned(a: Assignment, mission: u32) -> bool {
    let word: u128 = missions::state(a, 'Earned').try_into().unwrap();
    word / missions::bit(mission) % 2 == 1
}

fn earn(a: Assignment, mission: u32) {
    let word: u128 = missions::state(a, 'Earned').try_into().unwrap();
    if word / missions::bit(mission) % 2 == 0 {
        missions::set_state(a, 'Earned', (word + missions::bit(mission)).into());
    }
}

fn validate(a: Assignment) {
    let word = missions::lifecycle(a);
    if !missions::has_flag(word, a.mission, 0) || missions::has_flag(word, a.mission, 1) {
        return;
    }
    let complete = if a.mission == 4 {
        operational_colony(a)
    } else {
        earned(a, a.mission)
    };
    if complete {
        missions::set_flag(a, 1);
    }
}

// Resolve the campaign from the actual native target, never from client-supplied
// mission evidence. Unrelated or pre-campaign actions are simply not credited.
fn before(a: Assignment, name: felt252, data: Span<felt252>) -> Option<(Assignment, Entity, u64)> {
    let scanning = name == 'ScanSurfaceStart' || name == 'ScanSurfaceFinish';
    let construction = name == 'ConstructionStart' || name == 'ConstructionFinish';
    let use_building = name == 'StationCrew' || name == 'DockShip';
    let trade = name == 'FillBuyOrder' || name == 'FillSellOrder';
    if !(scanning || construction || use_building || trade) {
        return Option::None;
    }
    let target = parse::<Entity>(segment(data, if trade {
        2
    } else {
        0
    }, 2));
    if target.label != (if scanning {
        entities::ASTEROID
    } else {
        entities::BUILDING
    }) {
        return Option::None;
    }
    let asteroid = if scanning {
        target
    } else {
        EntityTrait::new(entities::ASTEROID, asteroid_id(target))
    };
    assert(a.subject == asteroid, 'wrong colony target');
    if !missions::flag(a, 0) {
        return Option::None;
    }
    let context = parse::<Context>(segment(data, data.len() - 4, 4));
    if scanning {
        assert_owner(a, context);
        let celestial = components::get::<Celestial>(asteroid.path()).unwrap();
        if name == 'ScanSurfaceStart' {
            assert(celestial.scan_status == scans::UNSCANNED, 'scan already started');
            assert(missions::state(a, 'ScanStarted') == 0, 'scan already recorded');
        } else {
            assert(missions::state(a, 'ScanStarted') == hash(@celestial), 'unobserved scan start');
            assert(celestial.scan_status == scans::SURFACE_SCANNING, 'not surface scanning');
        }
    } else {
        if !earned(a, 0) {
            return Option::None;
        }
        let building = components::get::<Building>(target.path()).unwrap();
        let kind = branch(building.building_type);
        if kind == 0 {
            return Option::None;
        }
        if name == 'ConstructionStart' {
            if context.now < missions::state(a, 'ScanFinished').try_into().unwrap() {
                return Option::None;
            }
            assert(building.status == building_status::PLANNED, 'not planned');
        } else if name == 'ConstructionFinish' {
            if missions::state(a, key('Built', target, 0)) != fingerprint(target, building) {
                return Option::None;
            }
        } else {
            if !qualifying_data(a, target, building) {
                return Option::None;
            }
            if name == 'StationCrew' {
                if kind != 1 {
                    return Option::None;
                }
                let crew = parse::<Entity>(segment(data, data.len() - 6, 2));
                if components::get::<Location>(crew.path()).unwrap().location == target {
                    return Option::None;
                }
            } else if name == 'DockShip' {
                if kind != 2 {
                    return Option::None;
                }
            } else {
                if kind != 3 {
                    return Option::None;
                }
                let amount = *data.at(if name == 'FillBuyOrder' {
                    9
                } else {
                    5
                });
                if amount == 0 {
                    return Option::None;
                }
            }
        }
    }
    Option::Some((a, target, if trade {
        influence::entities::current_id('Delivery')
    } else {
        0
    }))
}

fn record_use(a: Assignment, target: Entity) {
    let building = components::get::<Building>(target.path()).unwrap();
    assert(qualifying_data(a, target, building), 'building no longer qualifies');
    let mission = branch(building.building_type);
    missions::set_state(a, key('Used', target, 0), fingerprint(target, building));
    let selected: u64 = missions::state(a, mission.into()).try_into().unwrap();
    if selected != target.id && !operational_selection(a, mission, selected) {
        missions::set_state(a, mission.into(), target.id.into());
    }
    earn(a, mission);
}

fn after(name: felt252, a: Assignment, target: Entity, delivery_before: u64, context: Context) {
    if name == 'FillBuyOrder' || name == 'FillSellOrder' {
        // FillBuyOrder also implements cancellation. A successful fill creates one
        // delivery; cancellation creates none and must never earn commerce credit.
        let delivery_after = influence::entities::current_id('Delivery');
        if delivery_after == delivery_before {
            return;
        }
        assert(delivery_after == delivery_before + 1, 'unexpected trade delivery');
    }
    if name == 'ScanSurfaceStart' {
        missions::set_state(
            a, 'ScanStarted', hash(@components::get::<Celestial>(target.path()).unwrap())
        );
    } else if name == 'ScanSurfaceFinish' {
        assert(
            components::get::<Celestial>(target.path())
                .unwrap()
                .scan_status == scans::SURFACE_SCANNED,
            'scan incomplete'
        );
        missions::set_state(a, 'ScanStarted', 0);
        missions::set_state(a, 'ScanFinished', context.now.into());
        earn(a, 0);
    } else if name == 'ConstructionStart' {
        let building = components::get::<Building>(target.path()).unwrap();
        missions::set_state(a, key('Built', target, 0), fingerprint(target, building));
    } else if name != 'ConstructionFinish' {
        record_use(a, target);
    }
}

#[starknet::contract]
mod ColonizationMissionCampaign {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use traits::{Into, TryInto};
    use starknet::ContractAddress;
    use influence::{components, config};
    use influence::common::{missions, nft};
    use influence::common::missions::Assignment;
    use influence::components::Celestial;
    use influence::components::celestial::statuses;
    use influence::config::entities;
    use influence::types::{Context, EntityTrait};
    use super::{assert_owner, colonizer, operational_colony, validate};
    #[storage]
    struct Storage {}
    #[external(v0)]
    fn evaluate(
        ref self: ContractState,
        a: Assignment,
        operation: u32,
        action_name: felt252,
        args: Span<felt252>,
        context: Context
    ) -> (ContractAddress, u128) {
        assert(
            a.campaign != 0 && a.campaign == config::get('COLONIZATION_CAMPAIGN'),
            'wrong colony campaign'
        );
        assert(a.subject.label == entities::ASTEROID && a.mission < 5, 'invalid colony subject');
        assert(args.is_empty(), 'unexpected colony arguments');
        assert(
            context.payment_amount == 0 && context.payment_to.is_zero(),
            'unsupported payment context'
        );
        if operation == 0 {
            if a.mission == 0 {
                assert(missions::state(a, 'Colonizer') == 0, 'colony already enrolled');
                nft::assert_owner('Asteroid', a.subject, context.caller);
                assert(
                    components::get::<Celestial>(a.subject.path())
                        .unwrap()
                        .scan_status == statuses::UNSCANNED,
                    'scan already started'
                );
                missions::set_state(a, 'Colonizer', context.caller.into());
            } else {
                assert_owner(a, context);
                assert(
                    missions::flag(Assignment { mission: 0, ..a }, 1), 'scan mission incomplete'
                );
            }
        } else if operation == 2 {
            validate(a);
        } else if operation == 3 {
            assert_owner(a, context);
            if a.mission == 4 {
                assert(operational_colony(a), 'colony not operational');
            }
            let reward: u128 = missions::read(
                array!['ColonyReward', a.campaign, a.mission.into()].span()
            )
                .try_into()
                .unwrap();
            return (colonizer(a), reward);
        } else {
            panic_with_felt252('unknown mission operation');
        }
        (starknet::contract_address_const::<0>(), 0)
    }
}

#[starknet::contract]
mod ConfigureColonizationMissions {
    use array::ArrayTrait;
    use traits::Into;
    use influence::{config, common::missions};
    use influence::types::{Context, ContextTrait};
    #[storage]
    struct Storage {}
    #[external(v0)]
    fn run(ref self: ContractState, campaign: felt252, context: Context) {
        assert(context.is_admin(), 'only admin');
        assert(config::get('COLONIZATION_CAMPAIGN') == 0, 'colony already configured');
        assert(
            campaign != 0 && missions::read(array!['DefinitionCount', campaign].span()) == 5,
            'invalid colony definition'
        );
        let rewards = array![150000_u128, 250000, 300000, 350000, 450000];
        let mut i = 0_u32;
        loop {
            if i == 5 {
                break;
            }
            missions::write(
                array!['ColonyReward', campaign, i.into()].span(), (*rewards.at(i) * 1000000).into()
            );
            i += 1;
        };
        config::set_with_event('COLONIZATION_CAMPAIGN', campaign);
    }
}
