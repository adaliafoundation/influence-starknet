use array::{ArrayTrait, SpanTrait};
use option::OptionTrait;
use traits::{Into, TryInto};

use influence::components;
use influence::components::{
    BuildingAllowance, StarterPack, StarterPackBuildingFunding, StarterPackLotLease, StarterPackTrait, Unique
};
use influence::config::{entities, errors};
use influence::types::{Entity, EntityTrait};

fn is_valid(crew: Entity) -> bool {
    match components::get::<StarterPack>(crew.path()) {
        Option::Some(starter_pack) => starter_pack.valid,
        Option::None(_) => false
    }
}

fn lot_allowance(crew: Entity) -> u64 {
    match components::get::<StarterPack>(crew.path()) {
        Option::Some(starter_pack) => {
            if starter_pack.valid { return starter_pack.lot_allowance; }
            return 0;
        },
        Option::None(_) => 0
    }
}

fn assert_valid(crew: Entity) -> StarterPack {
    let starter_pack = match components::get::<StarterPack>(crew.path()) {
        Option::Some(starter_pack) => starter_pack,
        Option::None(_) => {
            assert(false, errors::INSUFFICIENT_AMOUNT);
            let allowances: Array<BuildingAllowance> = Default::default();
            return StarterPack {
                product_id: 0,
                restricted_until: 0,
                valid: false,
                invalidated_at: 0,
                building_allowances: allowances.span(),
                lot_allowance: 0,
                food_reload_allowance: 0,
                core_sample_allowance: 0
            };
        }
    };
    assert(starter_pack.valid, 'starter pack invalid');
    return starter_pack;
}

fn invalidate(crew: Entity, now: u64) {
    match components::get::<StarterPack>(crew.path()) {
        Option::Some(mut starter_pack) => {
            if starter_pack.valid {
                starter_pack.valid = false;
                starter_pack.invalidated_at = now;
                components::set::<StarterPack>(crew.path(), starter_pack);
            }
        },
        Option::None(_) => ()
    };
}

fn consume_building_allowance(crew: Entity, building_type: u64) -> StarterPack {
    let starter_pack = assert_valid(crew);
    assert(starter_pack.building_allowance(building_type) > 0, errors::INSUFFICIENT_AMOUNT);

    let mut allowances = starter_pack.building_allowances;
    let mut updated: Array<BuildingAllowance> = Default::default();

    loop {
        match allowances.pop_front() {
            Option::Some(allowance) => {
                if *allowance.building_type == building_type {
                    updated.append(BuildingAllowance {
                        building_type: *allowance.building_type,
                        count: *allowance.count - 1
                    });
                } else {
                    updated.append(*allowance);
                }
            },
            Option::None(_) => {
                break;
            },
        };
    };

    let updated_pack = StarterPack {
        product_id: starter_pack.product_id,
        restricted_until: starter_pack.restricted_until,
        valid: starter_pack.valid,
        invalidated_at: starter_pack.invalidated_at,
        building_allowances: updated.span(),
        lot_allowance: starter_pack.lot_allowance,
        food_reload_allowance: starter_pack.food_reload_allowance,
        core_sample_allowance: starter_pack.core_sample_allowance
    };
    components::set::<StarterPack>(crew.path(), updated_pack);
    return updated_pack;
}

fn consume_lot_allowance(crew: Entity) -> StarterPack {
    let mut starter_pack = assert_valid(crew);
    assert(starter_pack.lot_allowance > 0, errors::INSUFFICIENT_AMOUNT);
    starter_pack.lot_allowance -= 1;
    components::set::<StarterPack>(crew.path(), starter_pack);
    return starter_pack;
}

fn consume_food_reload_allowance(crew: Entity) -> StarterPack {
    let mut starter_pack = assert_valid(crew);
    assert(starter_pack.food_reload_allowance > 0, errors::INSUFFICIENT_AMOUNT);
    starter_pack.food_reload_allowance -= 1;
    components::set::<StarterPack>(crew.path(), starter_pack);
    return starter_pack;
}

fn consume_core_sample_allowance(crew: Entity) -> StarterPack {
    let mut starter_pack = assert_valid(crew);
    assert(starter_pack.core_sample_allowance > 0, errors::INSUFFICIENT_AMOUNT);
    starter_pack.core_sample_allowance -= 1;
    components::set::<StarterPack>(crew.path(), starter_pack);
    return starter_pack;
}

fn mark_building_funded(building: Entity, crew: Entity, restricted_until: u64) {
    components::set::<StarterPackBuildingFunding>(building.path(), StarterPackBuildingFunding {
        crew: crew,
        restricted_until: restricted_until
    });
}

fn mark_lot_lease(agreement_path: Span<felt252>, crew: Entity) {
    components::set::<StarterPackLotLease>(agreement_path, StarterPackLotLease { crew: crew });
}

fn clear_lot_lease(agreement_path: Span<felt252>) {
    components::set::<StarterPackLotLease>(
        agreement_path, StarterPackLotLease { crew: EntityTrait::new(entities::CREW, 0) }
    );
}

fn assert_lot_lease_transferable(agreement_path: Span<felt252>) {
    match components::get::<StarterPackLotLease>(agreement_path) {
        Option::Some(_) => {
            assert(false, 'starter lease restricted');
        },
        Option::None(_) => ()
    };
}

fn prepare_lot_lease_extension(agreement_path: Span<felt252>, now: u64, end_time: u64) {
    match components::get::<StarterPackLotLease>(agreement_path) {
        Option::Some(_) => {
            assert(now >= end_time, 'starter lease active');
            clear_lot_lease(agreement_path);
        },
        Option::None(_) => ()
    };
}

fn assert_building_unrestricted(building: Entity, now: u64) {
    match components::get::<StarterPackBuildingFunding>(building.path()) {
        Option::Some(funding) => {
            assert(now >= funding.restricted_until, 'starter funded restricted');
        },
        Option::None(_) => ()
    };
}

fn assert_target_unrestricted(target: Entity, now: u64) {
    if target.label == entities::BUILDING {
        assert_building_unrestricted(target, now);
    } else if target.label == entities::LOT {
        let mut lot_use_path: Array<felt252> = Default::default();
        lot_use_path.append('LotUse');
        lot_use_path.append(target.into());

        match components::get::<Unique>(lot_use_path.span()) {
            Option::Some(unique_data) => {
                let lot_use: Entity = unique_data.unique.try_into().unwrap();
                if lot_use.label == entities::BUILDING {
                    assert_building_unrestricted(lot_use, now);
                }
            },
            Option::None(_) => ()
        };
    }
}
