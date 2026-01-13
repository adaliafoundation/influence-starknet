use hash::LegacyHash;
use option::OptionTrait;
use starknet::{ClassHash, ContractAddress, SyscallResultTrait};
use starknet::class_hash::Felt252TryIntoClassHash;
use starknet::storage_access::StorageAddress;
use traits::TryInto;

const DAY: u64 = 86400; // 24 hours
const EPOCH: u64 = 1609459200; // start timestamp for orbits
const HOUR: u64 = 3600; // 60 minutes
const MAX_ASTEROID_RADIUS: u64 = 1611222621356; // 375.142 km (f64)
const MONTH: u64 = 2592000; // 30 days
const WEEK: u64 = 604800; // 7 days
const YEAR: u64 = 31536000; // 1 year

// Settable constants (with config::set)
// ADALIAN_PURCHASE_PRICE - price in tokens per Adalian
// ADALIAN_PURCHASE_TOKEN - token address for Adalian purchase (ETH / USDC / SWAY)
// ASTEROID_PURCHASE_BASE_PRICE - base price in tokens for an asteroid
// ASTEROID_PURCHASE_LOT_PRICE - price in tokens per asteroid lot
// ASTEROID_PURCHASE_TOKEN - token address for asteroid purchase (ETH / USDC / SWAY)
// ASTEROID_MERKLE_ROOT - Merkle root for asteroid features
// ASTEROID_SALE_LIMIT - asteroids allowed for sale per 1 million IRL sec period
// CONSTRUCTION_GRACE_PERIOD - grace period in IRL seconds after construction planned
// CORE_SAMPLING_TIME - in-game seconds to sample a deposit
// CREW_SCHEDULE_BUFFER - buffer in IRL seconds for crew scheduling
// CREWMATE_FOOD_PER_YEAR - kg / in-game year
// DECONSTRUCTION_PENALTY - fraction of building materials lost at deconstruction (f64)
// EMERGENCY_PROP_GEN_TIME - in-game seconds to generate emergency propellant up to 10%
// EVENT_SWAY - SWAY reward for event completion
// HOPPER_SPEED - hopper speed in km / in-game hr (f64)
// INSTANT_TRANSPORT_DISTANCE - instant transfer distance in km (f64)
// LAUNCH_TIME - unix time for launch of exploitation
// MAX_POLICY_DURATION - maximum policy duration in IRL seconds
// MAX_PROCESS_TIME - longest a process can run in in-game seconds
// RANDOM_STRATEGY - randomness strategy
// SCANNING_TIME - time for asteroid scans in IRL seconds
// TESTNET_SWAY_MERKLE_ROOT - Merkle root for testnet SWAY rewards
// TIME_ACCELERATION - time acceleration factor

mod actions;
mod entities;
mod errors;
mod noise;
mod permissions;
mod random_events;
mod resource_bonuses;

fn get(name: felt252) -> felt252 {
    let selector = 0x37802032f0a60a9a88d14be2a2adc9b5c19da641ac29831487d2daa90bb75a0; // constants
    let base = starknet::storage_base_address_from_felt252(LegacyHash::hash(selector, name));
    let address = starknet::storage_address_from_base_and_offset(base, 0);
    return starknet::storage_read_syscall(0, address).unwrap_syscall();
}

fn set(name: felt252, value: felt252) {
    let selector = 0x37802032f0a60a9a88d14be2a2adc9b5c19da641ac29831487d2daa90bb75a0; // constants
    let base = starknet::storage_base_address_from_felt252(LegacyHash::hash(selector, name));
    let address = starknet::storage_address_from_base_and_offset(base, 0);
    starknet::storage_write_syscall(0, address, value).unwrap_syscall();
}
