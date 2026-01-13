use array::{ArrayTrait, SpanTrait};
use cmp::max as int_max;
use option::OptionTrait;
use starknet::ContractAddress;
use traits::{Into, TryInto};

use cubit::f64::{Fixed, FixedTrait, HALF, ONE};
use cubit::f64::{core::pow_int, comp::{min, max}};

use influence::{components, config};
use influence::components::{ComponentTrait, Building, BuildingTrait, Crew, CrewTrait, Location, LocationTrait, Ship,
    ShipTrait, Station, StationTrait,
    crewmate::{collections, departments, titles, Crewmate, CrewmateTrait},
    modifier_type::{types as modifier_types, ModifierType, ModifierTypeTrait},
    station_type::{types as station_types, StationTypeTrait}};
use influence::config::{entities, errors, YEAR};
use influence::types::array::SpanTraitExt;
use influence::types::{Entity, EntityTrait};

const DMIL: u64 = 429496; // 0.0001 (f64)

#[derive(Copy, Drop, Serde)]
struct CrewDetails {
    entity: Entity,
    component: Crew,
    _crewmates: Span<Crewmate>,
    _location: Entity,
    _station: Entity,
    _station_data: Station,
    _ship: Entity,
    _ship_data: Ship,
    _asteroid_id: u64,
    _lot_id: u64,
    _station_bonus: Fixed,
    _food_bonus: Fixed,
    _current_food: u64,
    _consume_mod: Fixed,
    _position_fetched: bool
}

trait CrewDetailsTrait {
    fn new(crew: Entity) -> CrewDetails;
    fn crewmates(ref self: CrewDetails) -> Span<Crewmate>;
    fn location(ref self: CrewDetails) -> Entity;
    fn station(ref self: CrewDetails) -> (Entity, Station);
    fn ship(ref self: CrewDetails) -> (Entity, Ship);
    fn asteroid_id(ref self: CrewDetails) -> u64;
    fn lot_id(ref self: CrewDetails) -> u64;
    fn bonus(ref self: CrewDetails, modifier: u64, now: u64) -> Fixed;
    fn station_bonus(ref self: CrewDetails) -> Fixed;
    fn food_bonus(ref self: CrewDetails, now: u64) -> Fixed;
    fn current_food(ref self: CrewDetails, now: u64) -> u64;
    fn consume_mod(ref self: CrewDetails) -> Fixed;
    fn assert_all_but_ready(ref self: CrewDetails, delegate: ContractAddress, now: u64);
    fn assert_all_ready(ref self: CrewDetails, delegate: ContractAddress, now: u64);
    fn assert_all_ready_within(ref self: CrewDetails, delegate: ContractAddress, now: u64);
    fn assert_building_operational(ref self: CrewDetails);
    fn assert_delegated_to(ref self: CrewDetails, delegate: ContractAddress);
    fn assert_manned(ref self: CrewDetails);
    fn assert_not_in_emergency(ref self: CrewDetails);
    fn assert_launched(ref self: CrewDetails, now: u64);
    fn assert_ready(ref self: CrewDetails, now: u64);
}

impl CrewDetailsImpl of CrewDetailsTrait {
    fn new(crew: Entity) -> CrewDetails {
        let crew_data = components::get::<Crew>(crew.path()).expect(errors::CREW_NOT_FOUND);
        let crewmates: Array<Crewmate> = Default::default();

        return CrewDetails {
            entity: crew,
            component: crew_data,
            _crewmates: crewmates.span(),
            _location: EntityTrait::new(0, 0),
            _station: EntityTrait::new(0, 0),
            _station_data: StationTrait::new(0),
            _ship: EntityTrait::new(0, 0),
            _ship_data: ShipTrait::new(0, 0),
            _asteroid_id: 0,
            _lot_id: 0,
            _station_bonus: FixedTrait::ZERO(),
            _food_bonus: FixedTrait::ZERO(),
            _current_food: 0,
            _consume_mod: FixedTrait::ZERO(),
            _position_fetched: false
        };
    }

    fn crewmates(ref self: CrewDetails) -> Span<Crewmate> {
        if self._crewmates.len() == 0 {
            let roster = _hydrate_roster(self.component.roster);
            self._crewmates = roster;
        }

        return self._crewmates;
    }

    fn location(ref self: CrewDetails) -> Entity {
        if self._location.is_empty() {
            let location = components::get::<Location>(self.entity.path()).expect(errors::LOCATION_NOT_FOUND).location;
            self._location = location;
        }

        return self._location;
    }

    fn station(ref self: CrewDetails) -> (Entity, Station) {
        if self._station.is_empty() {
            match components::get::<Station>(self.location().path()) {
                // Ship or Habitat
                Option::Some(station_data) => {
                    self._station = self._location;
                    self._station_data = station_data;
                },
                // Escape module
                Option::None(_) => {
                    self._station = self.entity;
                    self._station_data = Station {
                        station_type: station_types::STANDARD_QUARTERS,
                        population: self.component.roster.len().into()
                    };
                }
            }
        }

        return (self._station, self._station_data);
    }

    fn ship(ref self: CrewDetails) -> (Entity, Ship) {
        if self._ship.is_empty() {
            match components::get::<Ship>(self.location().path()) {
                // Standard ships
                Option::Some(ship_data) => {
                    self._ship = self._location;
                    self._ship_data = ship_data;
                },
                // Escape module
                Option::None(_) => {
                    self._ship = self.entity;
                    self._ship_data = components::get::<Ship>(self.entity.path()).expect(errors::SHIP_NOT_FOUND);
                }
            }
        }

        return (self._ship, self._ship_data);
    }

    fn asteroid_id(ref self: CrewDetails) -> u64 {
        if self._position_fetched == false {
            let (asteroid_id, lot_id) = self.location().to_position();
            self._asteroid_id = asteroid_id;
            self._lot_id = lot_id;
            self._position_fetched = true;
        }

        return self._asteroid_id;
    }

    fn lot_id(ref self: CrewDetails) -> u64 {
        if self._position_fetched == false {
            let (asteroid_id, lot_id) = self.location().to_position();
            self._asteroid_id = asteroid_id;
            self._lot_id = lot_id;
            self._position_fetched = true;
        }

        return self._lot_id;
    }

    fn bonus(ref self: CrewDetails, modifier: u64, now: u64) -> Fixed {
        let config = ModifierTypeTrait::by_type(modifier);
        let crewmates_bonus = from_crewmates(config, self.crewmates());

        if config.further_modified {
            return crewmates_bonus * self.station_bonus() * self.food_bonus(now);
        } else {
            return crewmates_bonus;
        }
    }

    fn station_bonus(ref self: CrewDetails) -> Fixed {
        if self._station_bonus == FixedTrait::ZERO() {
            let (_, station_data) = self.station();
            self._station_bonus = _from_station(station_data);
        }

        return self._station_bonus;
    }

    fn food_bonus(ref self: CrewDetails, now: u64) -> Fixed {
        if self._food_bonus == FixedTrait::ZERO() {
            let food_remaining = FixedTrait::new_unscaled(self.current_food(now).into(), false);
            let food_per_year = config::get('CREWMATE_FOOD_PER_YEAR').try_into().unwrap();
            let consumption_rate = FixedTrait::new_unscaled(food_per_year / 2, false) / self.consume_mod();

            let mut raw_val = food_remaining / consumption_rate;

            // Check for rationing bonus
            if raw_val < FixedTrait::ONE() {
                let ration_mod = from_crewmates(
                    ModifierTypeTrait::by_type(modifier_types::FOOD_RATIONING_PENALTY), self.crewmates()
                );

                raw_val = FixedTrait::ONE() - ((FixedTrait::ONE() - raw_val) / ration_mod);
            }

            let quarter = FixedTrait::new(1073741824, false); // 0.25
            self._food_bonus = min(max(raw_val, quarter), FixedTrait::ONE());
        }

        return self._food_bonus;
    }

    fn current_food(ref self: CrewDetails, now: u64) -> u64 {
        if self._current_food == 0 {
            let start_time: u64 = config::get('LAUNCH_TIME').try_into().unwrap();
            let time_since_fed = int_max(now, start_time) - int_max(self.component.last_fed, start_time);
            self._current_food = _current_food(time_since_fed, self.consume_mod());
        }

        return self._current_food;
    }

    fn consume_mod(ref self: CrewDetails) -> Fixed {
        if self._consume_mod == FixedTrait::ZERO() {
            self._consume_mod = from_crewmates(ModifierTypeTrait::by_type(modifier_types::FOOD_CONSUMPTION_TIME), self.crewmates());
        }

        return self._consume_mod;
    }

    fn assert_all_but_ready(ref self: CrewDetails, delegate: ContractAddress, now: u64) {
        // Check that crew is delegated
        self.assert_delegated_to(delegate);

        // Check that crew is manned and ready
        self.assert_manned();
        self.assert_launched(now);

        // Check that ship is not in emergency mode
        self.assert_not_in_emergency();

        // Check for non-operational buildings
        self.assert_building_operational();
    }

    fn assert_all_ready(ref self: CrewDetails, delegate: ContractAddress, now: u64) {
        self.assert_all_but_ready(delegate, now);
        self.assert_ready(now);
    }

    fn assert_all_ready_within(ref self: CrewDetails, delegate: ContractAddress, now: u64) {
        self.assert_all_but_ready(delegate, now);
        self.assert_ready(now + config::get('CREW_SCHEDULE_BUFFER').try_into().unwrap());
    }

    fn assert_building_operational(ref self: CrewDetails) {
        let (station, station_data) = self.station();

        // If station (crew or ship) is in a building, check that it is operational
        // Otherwise the ship is in orbit, on a lot, or in space, so ignore
        match components::get::<Building>(station.path()) {
            Option::Some(building_data) => {
                building_data.assert_operational();
            },
            Option::None(_) => ()
        };
    }

    fn assert_delegated_to(ref self: CrewDetails, delegate: ContractAddress) {
        self.component.assert_delegated_to(delegate);
    }

    fn assert_manned(ref self: CrewDetails) {
        self.component.assert_manned();
    }

    fn assert_ready(ref self: CrewDetails, now: u64) {
        self.component.assert_ready(now);
    }

    fn assert_not_in_emergency(ref self: CrewDetails) {
        let (ship, ship_data) = self.ship();
        assert(ship_data.emergency_at == 0, errors::EMERGENCY_ACTIVE);
    }

    fn assert_launched(ref self: CrewDetails, now: u64) {
        let launch: u64 = config::get('LAUNCH_TIME').try_into().unwrap();
        assert(now >= launch, 'not launched yet');
    }
}

// Extracts crewmate component from the crew's roster
fn _hydrate_roster(roster: Span<u64>) -> Span<Crewmate> {
    let mut crewmates: Array<Crewmate> = Default::default();
    let mut iter = 0;

    loop {
        if iter >= roster.len() { break; }
        crewmates.append(
            components::get::<Crewmate>(EntityTrait::new(entities::CREWMATE, *roster.at(iter)).path())
                .expect(errors::CREWMATE_NOT_FOUND)
        );

        iter += 1;
    };

    return crewmates.span();
}

// Converts the title id to an Arvad department and rank
fn _to_department(title: u64) -> (felt252, u64) {
    let mut rank: u64 = 0;

    if (title == 0) || (title > 65) { return (0, 0); }
    let (div, rem) = integer::u64_safe_divmod(title - 1, 13_u64.try_into().unwrap());
    let department = rem + 1;
    let rank = (div + 1) * 2;

    return (department.into(), rank);
}

// Computes the relative efficiency of a station based on its population cap
fn _from_station(station: Station) -> Fixed {
    let config = StationTypeTrait::by_type(station.station_type);
    let soft_cap = config.cap / 2;

    if station.population > config.cap {
        return FixedTrait::ONE();
    } else if station.population > soft_cap {
        let efficiency_drop = config.efficiency - FixedTrait::ONE();
        let pop_fraction = FixedTrait::new_unscaled(station.population - soft_cap, false) /
            FixedTrait::new_unscaled(soft_cap, false);

        return config.efficiency - efficiency_drop * pop_fraction;
    }

    return config.efficiency;
}

// Calculates efficiency for classes, titles, and traits for the crewmates
fn from_crewmates(config: ModifierType, crewmates: Span<Crewmate>) -> Fixed {
    let mut class_matches = 0;
    let mut trait_eff = 0;
    let mut iter = 0;

    loop {
        if iter >= crewmates.len() { break; }

        // Increment the class matches
        let crewmate = *crewmates.at(iter);
        if crewmate.class == config.class {
            class_matches += 1;
        }

        // Calculate department efficiency (with bonus to specialists)
        let (dept, mut rank) = _to_department(crewmate.title);
        if crewmate.collection == collections::ARVAD_SPECIALIST {
            rank += 1;
        }

        // Ranks are doubled (and need to then be halved) to account for the half tier bonus from specialists
        if dept == config.dept_type.into() {
            trait_eff += (rank * config.dept_eff * DMIL) / 2;
        } else if dept == departments::MANAGEMENT.into() {
            trait_eff += (rank * config.mgmt_eff * DMIL) / 2;
        }

        // Calculate trait efficiency
        let mut jter = 0;
        if crewmate.impactful.contains(config.trait_type) {
            trait_eff += config.trait_eff * DMIL;
        }

        iter += 1;
    };

    let mut result = FixedTrait::new(ONE + trait_eff, false);

    // Apply class affinity bonus if present
    if config.class != 0 {
        let half = FixedTrait::new(HALF, false); // 0.5
        let three_halves = FixedTrait::new(6442450944, false); // 1.5
        result *= three_halves - pow_int(half, class_matches, false);
    }

    return result;
}

// Returns the current amount of food remaining on a per crewmate basis
fn _current_food(_time_since_fed: u64, consume_mod: Fixed) -> u64 {
    let accel = FixedTrait::new_unscaled(config::get('TIME_ACCELERATION').try_into().unwrap(), false);
    let years_since_fed = (FixedTrait::new_unscaled(_time_since_fed, false) / FixedTrait::new_unscaled(YEAR, false)) *
        accel;

    let food_per_year = config::get('CREWMATE_FOOD_PER_YEAR').try_into().unwrap();
    let max_food = FixedTrait::new_unscaled(food_per_year, false);
    let consumption = max_food * years_since_fed / consume_mod;

    // 1000 - consumption
    let full_time = max_food - consumption;

    // 750 - consumption / 2
    let fast_time = max_food * FixedTrait::new(3221225472, false) - consumption * FixedTrait::new(2147483648, false);

    let food_remaining = max(full_time, fast_time);
    if food_remaining.sign == true { return 0; }
    return food_remaining.try_into().unwrap();
}

// Returns the number of IRL seconds since the crew would have been fully fed (per crewmate basis)
fn time_since_fed(_food: u64, consume_mod: Fixed) -> u64 {
    let food_per_year = config::get('CREWMATE_FOOD_PER_YEAR').try_into().unwrap();
    let food_over_consumption = FixedTrait::new((_food * consume_mod.mag) / food_per_year, false);

    // consumption_modifier - (food / consumption_rate)
    let full_time = consume_mod - food_over_consumption;

    // 1.5 * consumption_modifier - (food * 2 / consumption_rate)
    let half_time = FixedTrait::new(6442450944, false) * consume_mod -
        FixedTrait::new(8589934592, false) * food_over_consumption;

    let accel = config::get('TIME_ACCELERATION').try_into().unwrap();
    let time_since_fed = max(full_time, half_time) * FixedTrait::new_unscaled(YEAR / accel, false);
    return time_since_fed.try_into().unwrap();
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use traits::{Into, TryInto};
    use integer::{u128_safe_divmod, u128_as_non_zero};

    use influence::{config, components};
    use influence::components::crewmate::{classes, crewmate_traits, titles};
    use influence::components::{Crew, CrewTrait, Location, LocationTrait, Station, StationTrait,
        modifier_type::{types as modifier_types, ModifierType, ModifierTypeTrait},
        crewmate::{collections, departments, Crewmate}};
    use influence::config::entities;
    use influence::types::entity::{Entity, EntityTrait};
    use influence::test::{helpers, mocks};

    use cubit::f64::{FixedTrait, ONE};
    use cubit::f64::test::helpers::assert_relative;

    use super::CrewDetailsTrait;

    #[test]
    #[available_gas(12000000)]
    fn test_from_food() {
        helpers::init();
        mocks::constants();
        let crew = mocks::delegated_crew(1, 'PLAYER');
        let mut crew_details = CrewDetailsTrait::new(crew);

        let err = 18446744073709551; // 0.1%
        assert_relative(crew_details.food_bonus(100000), ONE.into(), 'efficiency should be 100%', Option::Some(err));
        assert_relative(crew_details.food_bonus(657000), ONE.into(), 'efficiency should be 100%', Option::Some(err));
        assert_relative(crew_details.food_bonus(985500), 3221225472, 'efficiency should be 75%', Option::Some(err));
        assert_relative(crew_details.food_bonus(1314000), 2147483648, 'efficiency should be 50%', Option::Some(err));
        assert_relative(crew_details.food_bonus(1642500), 1073741824, 'efficiency should be 25%', Option::Some(err));
        assert_relative(crew_details.food_bonus(2628000), 1073741824, 'efficiency should be 25%', Option::Some(err));
    }

    #[test]
    #[available_gas(1500000)]
    fn test_from_crewmates() {
        let mut crewmates: Array<Crewmate> = Default::default();
        let impactful: Array<u64> = array![crewmate_traits::SURVEYOR];
        crewmates.append(Crewmate {
            status: 1,
            collection: collections::ARVAD_SPECIALIST,
            class: classes::MINER,
            title: titles::BLOCK_CAPTAIN,
            appearance: 0,
            impactful: impactful.span(),
            cosmetic: Default::default().span()
        });

        crewmates.append(Crewmate {
            status: 1,
            collection: collections::ARVAD_SPECIALIST,
            class: classes::MINER,
            title: titles::BLOCK_CAPTAIN,
            appearance: 0,
            impactful: impactful.span(),
            cosmetic: Default::default().span()
        });

        // Add modifier configs
        mocks::modifier_type(modifier_types::CORE_SAMPLE_TIME);
        mocks::modifier_type(modifier_types::HOPPER_TRANSPORT_TIME);

        let mut eff = super::from_crewmates(
            ModifierTypeTrait::by_type(modifier_types::CORE_SAMPLE_TIME), crewmates.span()
        );

        assert_relative(eff, 6522981581, 'efficiency should be 1.51875', Option::Some(42950));

        // Test without class affinity
        let mut crewmates2: Array<Crewmate> = Default::default();
        crewmates2.append(Crewmate {
            status: 1,
            collection: collections::ADALIAN,
            class: classes::PILOT,
            title: 0,
            appearance: 0,
            impactful: array![crewmate_traits::LOGISTICIAN].span(),
            cosmetic: Default::default().span()
        });

        eff = super::from_crewmates(
            ModifierTypeTrait::by_type(modifier_types::HOPPER_TRANSPORT_TIME), crewmates2.span()
        );

        assert_relative(eff, 4509715661, 'efficiency should be 1.05', Option::Some(42950));
    }

    #[test]
    #[available_gas(1500000)]
    fn test_from_station() {
        mocks::station_type(3);
        let mut station = Station { station_type: 3, population: 0 };
        assert_relative(super::_from_station(station), 5153960755, 'empty', Option::None(())); // 1.2

        station.population = 500;
        assert_relative(super::_from_station(station), 5153960755, 'at soft cap', Option::None(()));

        station.population = 625;
        assert_relative(super::_from_station(station), 4939212390, 'at 1.25 soft cap', Option::None(())); // 1.15

        station.population = 875;
        assert_relative(super::_from_station(station), 4509715661, 'at 1.75 soft cap', Option::None(())); // 1.05

        station.population = 1000;
        assert_relative(super::_from_station(station), ONE.into(), 'at cap', Option::None(()));
    }

    #[test]
    #[available_gas(6000000)]
    fn test_total_bonus() {
        helpers::init();
        mocks::constants();
        mocks::station_type(1);

        let crew = EntityTrait::new(entities::CREW, 1);
        let crew_data = Crew {
            delegated_to: starknet::contract_address_const::<'PLAYER'>(),
            roster: array![1].span(),
            last_fed: 0,
            ready_at: 0,
            action_type: 0,
            action_target: EntityTrait::new(0, 0),
            action_round: 0,
            action_weight: 0,
            action_strategy: 0
        };

        components::set::<Crew>(crew.path(), crew_data);

        let mut crewmates: Array<Crewmate> = Default::default();
        crewmates.append(Crewmate {
            status: 1,
            collection: collections::ADALIAN,
            class: classes::PILOT,
            title: 0,
            appearance: 0,
            impactful: array![crewmate_traits::LOGISTICIAN].span(),
            cosmetic: Default::default().span()
        });

        components::set::<Crewmate>(EntityTrait::new(entities::CREWMATE, 1).path(), *crewmates.at(0));

        let ship = EntityTrait::new(entities::SHIP, 1);
        let station = Station {
            station_type: 1,
            population: 1
        };

        components::set::<Station>(ship.path(), station);
        components::set::<Location>(crew.path(), LocationTrait::new(ship));

        // Add modifier configs
        mocks::modifier_type(modifier_types::FOOD_CONSUMPTION_TIME);
        mocks::modifier_type(modifier_types::FOOD_RATIONING_PENALTY);
        mocks::modifier_type(modifier_types::HOPPER_TRANSPORT_TIME);

        let mut crew_details = CrewDetailsTrait::new(crew);
        let eff = crew_details.bonus(modifier_types::HOPPER_TRANSPORT_TIME, 0);
        assert_relative(eff, 4509715661, 'efficiency should be 1.05', Option::Some(42950));
    }

    #[test]
    #[available_gas(100000)]
    fn test_to_department() {
        let (dept, rank) = super::_to_department(65);
        assert(dept == departments::MANAGEMENT.into(), 'department wrong');
        assert(rank == 10, 'rank wrong');

        let (dept, rank) = super::_to_department(1);
        assert(dept == departments::NAVIGATION.into(), 'department wrong');
        assert(rank == 2, 'rank wrong');
    }

    #[test]
    #[available_gas(2500000)]
    fn test_current_food() {
        mocks::constants();
        let mut consume_mod = FixedTrait::ONE();

        assert(super::_current_food(0, consume_mod) == 1000, 'wrong food');
        assert(super::_current_food(262800, consume_mod) == 800, 'wrong food');
        assert(super::_current_food(657000, consume_mod) == 500, 'wrong food');
        assert(super::_current_food(919800, consume_mod) == 400, 'wrong food');
        assert(super::_current_food(1314000, consume_mod) == 250, 'wrong food');
        assert(super::_current_food(2828000, consume_mod) == 0, 'wrong food');

        // Test with consumption modificiation
        consume_mod = FixedTrait::new(5368709120, false); // 1.25
        assert(super::_current_food(1314000, consume_mod) == 350, 'wrong food');
        assert(super::_current_food(2463750, consume_mod) == 0, 'wrong food');
    }

    #[test]
    #[available_gas(2500000)]
    fn test_time_since_fed() {
        mocks::constants();
        let mut consume_mod = FixedTrait::ONE();

        config::set('TIME_ACCELERATION', 24);
        assert(super::time_since_fed(1000, consume_mod) == 0, 'wrong time');
        assert(super::time_since_fed(800, consume_mod) == 262800, 'wrong time');
        assert(super::time_since_fed(500, consume_mod) == 657000, 'wrong time');
        assert(super::time_since_fed(400, consume_mod) == 919800, 'wrong time');
        assert(super::time_since_fed(250, consume_mod) == 1314000, 'wrong time');
        assert(super::time_since_fed(0, consume_mod) == 1971000, 'wrong time');

        // Test with consumption modification
        consume_mod = FixedTrait::new(5368709120, false); // 1.25
        assert(super::time_since_fed(350, consume_mod) == 1314000, 'wrong time');
        assert(super::time_since_fed(0, consume_mod) == 2463750, 'wrong time');
    }

    #[test]
    #[available_gas(2000000)]
    fn test_assert_ready() {
        config::set('TIME_ACCELERATION', 24);
        config::set('LAUNCH_TIME', 1000);

        let mut crewmates: Array<Crewmate> = Default::default();
        crewmates.append(Crewmate {
            status: 1,
            collection: collections::ARVAD_CITIZEN,
            class: classes::MINER,
            title: 36,
            appearance: 0xc00010001000000031,
            impactful: array![31, 50, 44].span(),
            cosmetic: array![1, 5, 27, 33, 40].span()
        });

        let crew = EntityTrait::new(entities::CREW, 214);
        let crew_data = Crew {
            delegated_to: starknet::contract_address_const::<'PLAYER'>(),
            roster: array![7037].span(),
            last_fed: 0,
            ready_at: 0,
            action_type: 0,
            action_target: EntityTrait::new(0, 0),
            action_round: 0,
            action_weight: 0,
            action_strategy: 0
        };

        components::set::<Crew>(crew.path(), crew_data);
        components::set::<Crewmate>(EntityTrait::new(entities::CREWMATE, 7037).path(), *crewmates.at(0));
        let mut crew_details = super::CrewDetailsTrait::new(crew);
        crew_details.assert_ready(1001);
        crew_details.assert_launched(1001);
    }

    #[test]
    #[should_panic(expected: ('not launched yet', ))]
    #[available_gas(2000000)]
    fn test_assert_ready_fail() {
        config::set('TIME_ACCELERATION', 24);
        config::set('LAUNCH_TIME', 1000);

        let mut crewmates: Array<Crewmate> = Default::default();
        crewmates.append(Crewmate {
            status: 1,
            collection: collections::ADALIAN,
            class: classes::MINER,
            title: 0,
            appearance: 0,
            impactful: Default::default().span(),
            cosmetic: Default::default().span()
        });

        let crew = EntityTrait::new(entities::CREW, 1);
        let crew_data = Crew {
            delegated_to: starknet::contract_address_const::<'PLAYER'>(),
            roster: array![1].span(),
            last_fed: 0,
            ready_at: 0,
            action_type: 0,
            action_target: EntityTrait::new(0, 0),
            action_round: 0,
            action_weight: 0,
            action_strategy: 0
        };

        components::set::<Crew>(crew.path(), crew_data);
        components::set::<Crewmate>(EntityTrait::new(entities::CREWMATE, 1).path(), *crewmates.at(0));
        let mut crew_details = super::CrewDetailsTrait::new(crew);
        crew_details.assert_launched(999);
    }
}
