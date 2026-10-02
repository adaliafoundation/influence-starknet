use option::OptionTrait;
use traits::TryInto;

use influence::components;
use influence::components::Unique;
use influence::config::{entities, permissions};
use influence::systems::agreements::helpers::use_lot_path;
use influence::types::{Entity, EntityTrait};

#[derive(Copy, Drop)]
struct LotAccess {
    allowed: bool,
    stale_tenant: bool,
}

// Resolve usage rights independently of occupancy. Only a successful new plan clears stale tenancy.
fn lot_access(crew: Entity, lot: Entity) -> LotAccess {
    let mut stale_tenant = false;
    if let Option::Some(data) = components::get::<Unique>(use_lot_path(lot)) {
        let tenant: Entity = data.unique.try_into().unwrap();
        if tenant.can(lot, permissions::USE_LOT) {
            return LotAccess { allowed: crew == tenant, stale_tenant: false };
        }
        stale_tenant = true;
    }
    let (asteroid_id, _) = lot.to_position();
    let asteroid = EntityTrait::new(entities::ASTEROID, asteroid_id);
    LotAccess {
        allowed: crew.can(lot, permissions::USE_LOT) || crew.can(asteroid, permissions::USE_LOT),
        stale_tenant,
    }
}
