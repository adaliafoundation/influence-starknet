use option::OptionTrait;
use traits::{Into, TryInto};

use cubit::f64::{Fixed, FixedTrait, Vec3, Vec3Trait, trig, ONE, TWO};

use influence::{components, config};
use influence::common::packed;
use influence::config::{entities, errors, HOUR, MAX_ASTEROID_RADIUS};
use influence::components::celestial::{Celestial, CelestialTrait};
use influence::components::location::{Location, LocationTrait};
use influence::types::entity::{Entity, EntityTrait};

const PHI: u64 = 10307763583; // 2.3999632297286535 (f64)

// Resolves the location, implicitly for asteroids and lots
// @return (asteroidId, lotId) Values are scoped IDs, not entity UUIDs
fn position_of(entity: Entity) -> (u64, u64) {
    if (entity.label == entities::ASTEROID) || (entity.label == entities::LOT) {
        let stride: u64 = packed::EXP2_32.try_into().unwrap();
        let (lot, asteroid) = integer::u64_safe_divmod(entity.id, stride.try_into().unwrap());
        return (asteroid, lot);
    } else if (entity.label == entities::SPACE) {
        assert(false, errors::LOCATION_NOT_FOUND);
    }

    let next = components::get::<Location>(entity.path());
    if next.is_some() {
        return position_of(next.unwrap().location);
    }

    assert(false, errors::LOCATION_NOT_FOUND);
    return (0, 0);
}

fn assert_valid_lot(asteroid: u64, lot: u64) {
    assert(lot >= 1, 'lots start at 1');
    let celestial = components::get::<Celestial>(EntityTrait::new(entities::ASTEROID, asteroid).path())
        .expect(errors::CELESTIAL_NOT_FOUND);
    let max_lot: u128 = surface_area(celestial.radius).try_into().unwrap();
    assert(lot.into() <= max_lot, 'lot too large');
}

// Returns the radius in km
fn radius(id: u64) -> Fixed {
    let asteroid_id = FixedTrait::new_unscaled(id.into(), false);
    let exp = FixedTrait::new(2040109466, false); // 0.475 (f64)
    return FixedTrait::new(MAX_ASTEROID_RADIUS, false) / asteroid_id.pow(exp);
}

fn surface_area(radius: Fixed) -> Fixed {
    return FixedTrait::new(53972150818, false) * radius * radius; // 4 * PI (f64)
}

fn surface_position(lot: u64, radius: Fixed, surface_area: Fixed) -> Vec3 {
    let normalized = surface_position_norm(lot, surface_area.floor());
    return normalized * Vec3Trait::new(radius, radius, radius);
}

fn surface_distance(origin_lot: u64, dest_lot: u64, radius: Fixed) -> Fixed {
    assert((origin_lot != 0) && (dest_lot != 0), 'lot cannot be 0');
    let surface_area = surface_area(radius).floor();
    let origin_pos = surface_position_norm(origin_lot, surface_area);
    let dest_pos = surface_position_norm(dest_lot, surface_area);
    return radius * origin_pos.dot(dest_pos).acos_fast();
}

// Returns the actual IRL time in seconds it takes to travel between two lots
fn hopper_travel_time(origin_lot: u64, dest_lot: u64, radius: Fixed, time_eff: Fixed, dist_eff: Fixed) -> u64 {
    let mut distance = FixedTrait::ZERO();
    if origin_lot == dest_lot { return 0; }

    // Calculate half the antipodal distance
    if (origin_lot == 0) || (dest_lot == 0) {
        distance = FixedTrait::new(trig::HALF_PI, false) * radius / time_eff;
    } else {
        distance = surface_distance(origin_lot, dest_lot, radius) / time_eff;
    }

    let instant_distance: u64 = config::get('INSTANT_TRANSPORT_DISTANCE').try_into().unwrap();
    let free_distance = FixedTrait::new(instant_distance, false) * dist_eff;
    if distance < free_distance { return 0; }
    let accel: u64 = config::get('TIME_ACCELERATION').try_into().unwrap();
    let hopper_speed: u64 = config::get('HOPPER_SPEED').try_into().unwrap();
    return (distance / FixedTrait::new((hopper_speed * accel) / HOUR, false)).ceil().try_into().unwrap();
}

fn surface_position_norm(lot: u64, num_lots: Fixed) -> Vec3 {
    let one = FixedTrait::ONE();
    let lot_adj = FixedTrait::new_unscaled(lot.into() - 1, false);
    let theta = FixedTrait::new(PHI, false) * lot_adj;
    let lot_frac = lot_adj / (num_lots - one);
    let y = one - (lot_frac * FixedTrait::new(TWO, false)); // 2
    let radius_y = (one - y * y).sqrt(); // radius at y
    let x = radius_y * theta.cos_fast();
    let z = radius_y * theta.sin_fast();
    return Vec3Trait::new(x, y, z);
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use option::OptionTrait;
    use traits::{Into, TryInto};

    use cubit::f64::{Fixed, FixedTrait, Vec3, Vec3Trait, trig, ONE};
    use cubit::f64::test::helpers::assert_relative;

    use influence::{components, config};
    use influence::common::packed;
    use influence::config::{entities, errors, MAX_ASTEROID_RADIUS};
    use influence::components::celestial::{Celestial, CelestialTrait};
    use influence::components::location::{Location, LocationTrait};
    use influence::types::entity::{Entity, EntityTrait};
    use influence::test::{helpers, mocks};

    #[test]
    #[available_gas(2000000)]
    fn test_radius() {
        let mut res = super::radius(1); // Adalia Prime
        assert(res.mag == MAX_ASTEROID_RADIUS, 'radius should be max');

        res = super::radius(250000);
        assert(res.mag == 4396773074, 'radius incorrect'); // 1.023 km
    }

    #[test]
    #[available_gas(3000000)]
    fn test_surface_area() {
        let mut res = super::surface_area(FixedTrait::new(MAX_ASTEROID_RADIUS, false)); // Adalia Prime
        assert(res.mag == 7595582831137231, 'surface area incorrect');

        res = super::surface_area(FixedTrait::new(4396773064, false)); // 1.023 km
        assert(res.mag == 56561133418, 'surface area incorrect');
    }

    #[test]
    #[available_gas(5000000)]
    fn test_surface_position() {
        let mut area = super::surface_area(FixedTrait::new(MAX_ASTEROID_RADIUS, false)); // Adalia Prime
        let mut res = super::surface_position_norm(1, area);
        assert(res.x.mag == 0, 'x incorrect');
        assert(res.y == FixedTrait::ONE(), 'y incorrect');
        assert(res.z.mag == 0, 'z incorrect');

        area = super::surface_area(FixedTrait::new(4396773064, false)); // 1.023 km
        res = super::surface_position_norm(13, area.floor());
        assert(res.x.mag == 0, 'x incorrect');
        assert(res.y == FixedTrait::new(ONE, true), 'y incorrect');
        assert(res.z.mag == 0, 'z incorrect');
    }

    #[test]
    #[available_gas(3600000)]
    fn test_distance() {
        let error = Option::Some(42949673); // 0.01 km
        let mut res = super::surface_distance(1, 1, FixedTrait::new_unscaled(100, false));
        assert(res.mag == 0, 'distance incorrect');

        res = super::surface_distance(1, 13, FixedTrait::new(4396773064, false));
        assert_relative(res, 13812869958, 'distance incorrect', error); // 3.2161 km

        res = super::surface_distance(123, 342, FixedTrait::new(39186281348, false));
        assert_relative(res, 64928776843, 'distance incorrect', error); // 15.1174 km
    }

    #[test]
    #[available_gas(4000000)]
    fn test_position_of() {
        let ship = EntityTrait::new(entities::SHIP, 1);
        let building = EntityTrait::new(entities::BUILDING, 2);
        let asteroid = mocks::asteroid();
        let lot = EntityTrait::from_position(asteroid.id, 69);
        components::set::<Location>(building.path(), LocationTrait::new(lot));
        components::set::<Location>(ship.path(), LocationTrait::new(building));

        let (ast, lot) = super::position_of(ship);
        assert(ast == asteroid.id, 'wrong asteroid');
        assert(lot == 69, 'wrong lot');
    }

    #[test]
    #[available_gas(5000000)]
    fn test_hopper_travel_time() {
        helpers::init();
        mocks::constants();

        let radius = super::radius(1);
        let mut time = super::hopper_travel_time(1602262, 1613996, radius, FixedTrait::ONE(), FixedTrait::ONE());
        assert(time == 1022, 'travel time incorrect');

        time = super::hopper_travel_time(1602262, 1615970, radius, FixedTrait::ONE(), FixedTrait::ONE());
        assert(time == 1009, 'travel time incorrect');
    }
}
