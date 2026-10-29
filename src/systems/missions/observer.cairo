use array::{ArrayTrait, SpanTrait};
use option::OptionTrait;
use traits::{Into, TryInto};
use influence::{components, config};
use influence::common::{missions, mission_evidence};
use influence::common::missions::Assignment;
use influence::types::{Entity, EntityTrait};
use influence::config::entities;

// A target is two felts: campaign, then packed Entity (80 bits) and mission mask.
// Grouping avoids running shared evidence producers more than once per subject.
const SUBJECT_RADIX: u128 = 1208925819614629174706176;

fn target(campaign: felt252, packed: felt252) -> (Assignment, u32) {
    let word: u128 = packed.try_into().unwrap();
    let subject: Entity = (word % SUBJECT_RADIX).try_into().unwrap();
    let mask: u32 = (word / SUBJECT_RADIX).try_into().unwrap();
    let count = if subject.label == entities::CREW {
        assert(
            campaign != 0 && campaign == config::get('STARTER_MISSION_CAMPAIGN'),
            'wrong starter campaign'
        );
        8
    } else {
        assert(subject.label == entities::ASTEROID, 'invalid mission subject');
        assert(
            campaign != 0 && campaign == config::get('COLONIZATION_CAMPAIGN'),
            'wrong colony campaign'
        );
        5
    };
    assert(mask != 0 && mask.into() < missions::bit(count), 'invalid mission mask');
    (Assignment { campaign, subject, mission: 0 }, mask)
}

fn encode_target(a: Assignment, mask: u32) -> felt252 {
    let subject: u128 = a.subject.into();
    (subject + mask.into() * SUBJECT_RADIX).into()
}

fn validate(a: Assignment, mut mask: u32) {
    let mut mission = 0;
    loop {
        if mask == 0 {
            break;
        }
        if mask % 2 == 1 {
            let step = Assignment { mission, ..a };
            if a.subject.label == entities::CREW {
                super::starter::validate(step);
            } else {
                super::colonization::validate(step);
            }
        }
        mask /= 2;
        mission += 1;
    };
}

#[starknet::contract]
mod MissionObserver {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use serde::Serde;
    use influence::common::{missions, mission_evidence};
    use influence::common::missions::Assignment;
    use influence::types::{Context, Entity};
    use influence::config::entities;
    use influence::systems::missions::{starter, colonization};
    use super::{target, validate};
    #[storage]
    struct Storage {}
    #[external(v0)]
    fn before(
        ref self: ContractState, name: felt252, data: Span<felt252>, targets: Span<felt252>
    ) -> Span<felt252> {
        assert(
            targets.len() != 0 && targets.len() <= 16 && targets.len() % 2 == 0,
            'invalid mission targets'
        );
        missions::lock();
        let mut snapshots: Array<(Assignment, u32, Span<felt252>)> = array![];
        let mut i = 0;
        loop {
            if i == targets.len() {
                break;
            }
            let (a, mask) = target(*targets.at(i), *targets.at(i + 1));
            let mut j = 0;
            loop {
                if j == i {
                    break;
                }
                let previous: u128 = (*targets.at(j + 1)).try_into().unwrap();
                let current: u128 = (*targets.at(i + 1)).try_into().unwrap();
                assert(
                    *targets.at(j) != a.campaign
                        || previous % super::SUBJECT_RADIX != current % super::SUBJECT_RADIX,
                    'duplicate mission target'
                );
                j += 2;
            };
            assert(missions::flag(a, 0), 'campaign not accepted');
            if a.subject.label == entities::CREW {
                let (actual, args, context) = starter::invocation(name, data);
                assert(actual.subject == a.subject, 'wrong starter crew');
                snapshots.append((a, mask, starter::pre(a, name, args, context)));
            } else {
                if let Option::Some((_, entity, delivery)) = colonization::before(a, name, data) {
                    snapshots
                        .append((a, mask, mission_evidence::encoded(@(entity, delivery)).span()));
                }
            }
            i += 2;
        };
        mission_evidence::encoded(@snapshots).span()
    }
    #[external(v0)]
    fn after(
        ref self: ContractState,
        name: felt252,
        data: Span<felt252>,
        snapshot: Span<felt252>,
        result: Span<felt252>
    ) {
        let snapshots = mission_evidence::parse::<
            Array<(Assignment, u32, Span<felt252>)>
        >(snapshot);
        for entry in snapshots {
            let (a, mask, proof) = entry;
            if a.subject.label == entities::CREW {
                let (_, args, context) = starter::invocation(name, data);
                starter::post(a, name, args, proof, context);
            } else {
                let (entity, delivery) = mission_evidence::parse::<(Entity, u64)>(proof);
                let context = mission_evidence::parse::<
                    Context
                >(mission_evidence::segment(data, data.len() - 4, 4));
                colonization::after(name, a, entity, delivery, context);
            }
            validate(a, mask);
        };
        missions::unlock();
    }
}

// One-time replacement of the pinned starter implementation. Existing evidence and
// lifecycle slots remain untouched; no per-player migration or old executor survives.
#[starknet::contract]
mod MigrateStarterObserver {
    use array::ArrayTrait;
    use traits::{Into, TryInto};
    use starknet::ClassHash;
    use influence::{config, systems, common::missions};
    use influence::types::{Context, ContextTrait};
    #[storage]
    struct Storage {}
    #[external(v0)]
    fn run(
        ref self: ContractState, expected_old: ClassHash, replacement: ClassHash, context: Context
    ) {
        assert(context.is_admin(), 'only admin');
        let campaign = config::get('STARTER_MISSION_CAMPAIGN');
        assert(campaign != 0, 'starter not configured');
        assert(
            missions::read(array!['StarterObserverMigrated', campaign].span()) == 0,
            'already migrated'
        );
        assert(
            expected_old.into() != 0 && replacement.into() != 0 && expected_old != replacement,
            'invalid replacement'
        );
        assert(systems::get('StarterMissionCampaign') == replacement, 'unregistered replacement');
        assert(systems::get('MissionObserver').into() != 0, 'observer not registered');
        let path = array!['Definition', campaign].span();
        assert(missions::read(path) == expected_old.into(), 'wrong old implementation');
        assert(
            missions::read(array!['DefinitionCount', campaign].span()) == 8, 'wrong mission count'
        );
        missions::write(path, replacement.into());
        missions::write(array!['StarterObserverMigrated', campaign].span(), 1);
        systems::set('MissionAction', 0.try_into().unwrap());
    }
}
