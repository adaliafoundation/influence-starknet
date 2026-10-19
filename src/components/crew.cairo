use array::{ArrayTrait, Span, SpanTrait};
use cmp::max;
use core::starknet::SyscallResultTrait;
use option::OptionTrait;
use result::ResultTrait;
use starknet::{ContractAddress, ContractAddressIntoFelt252, Felt252TryIntoContractAddress, SyscallResult,};
use starknet::storage_access::{Store, StorageBaseAddress, storage_base_address_const};
use traits::{Into, TryInto};

use influence::common::{packed, packed::{pack_u128, unpack_u128, split_felt252}, random};
use influence::components::{ComponentTrait, resolve};
use influence::config::{entities, errors};
use influence::types::entity::{Entity, EntityTrait};

// Component ----------------------------------------------------------------------------------------------------------

#[derive(Copy, Drop, Serde)]
struct Crew {
    delegated_to: ContractAddress,
    roster: Span<u64>, // up to 5 crewmates
    last_fed: u64, // timestamp in seconds when the crew *would have had* full food
    ready_at: u64, // timestamp in seconds
    action_type: u64, // the type of the last action taken by the crew
    action_target: Entity, // the target of the last action taken by the crew
    action_round: u64, // the committed round to use for randomness for action events,
    action_weight: u64, // the weight of the last action taken by the crew (based on time / value)
    action_strategy: u64 // the randomness strategy used for random events
}

impl CrewComponent of ComponentTrait<Crew> {
    fn name() -> felt252 {
        return 'Crew';
    }

    fn is_set(data: Crew) -> bool {
        return data.delegated_to.into() != 0;
    }

    fn version() -> u64 {
        return 1;
    }
}

trait CrewTrait {
    fn new(delegated_to: ContractAddress) -> Crew;
    fn busy_until(self: Crew, now: u64) -> u64;
    fn add_busy(ref self: Crew, now: u64, busy_time: u64) -> u64;
    fn set_action(ref self: Crew, action_type: u64, action_target: Entity, action_time: u64, now: u64);
    fn assert_delegated_to(self: Crew, delegate: ContractAddress);
    fn assert_manned(self: Crew);
    fn assert_ready(self: Crew, now: u64);
}

impl CrewImpl of CrewTrait {
    fn new(delegated_to: ContractAddress) -> Crew {
        let roster: Array<u64> = Default::default();

        return Crew {
            delegated_to: delegated_to,
            roster: roster.span(),
            last_fed: 0,
            ready_at: 0,
            action_type: 0,
            action_target: EntityTrait::new(0, 0),
            action_round: 0,
            action_weight: 0,
            action_strategy: 0
        };
    }

    fn busy_until(self: Crew, now: u64) -> u64 {
        return max(now, self.ready_at);
    }

    fn add_busy(ref self: Crew, now: u64, busy_time: u64) -> u64 {
        self.ready_at = max(now, self.ready_at) + busy_time;
        return self.ready_at;
    }

    fn set_action(ref self: Crew, action_type: u64, action_target: Entity, action_time: u64, now: u64) {
        // Retire new random-event candidates while preserving pending actions for resolution.
    }

    fn assert_delegated_to(self: Crew, delegate: ContractAddress) {
        assert(self.delegated_to == delegate, errors::INCORRECT_DELEGATE);
    }

    fn assert_manned(self: Crew) {
        assert(self.roster.len() != 0, errors::CREW_UNMANNED);
    }

    fn assert_ready(self: Crew, now: u64) {
        assert(self.ready_at <= now, errors::CREW_RESTING);

        if self.action_type != 0 {
            assert(
                self.action_round + 10 >= random::get_current_round(self.action_strategy),
                errors::CREW_ACTION_UNRESOLVED
            );
        }
    }
}

// Storage Access -----------------------------------------------------------------------------------------------------

fn pack_roster(roster: Span<u64>) -> felt252 {
    let mut low: u128 = 0;
    let mut high: u128 = 0;
    let len = roster.len();

    if len > 0 { pack_u128(ref low, packed::EXP2_0, packed::EXP2_42, (*roster.at(0)).into()); }
    if len > 1 { pack_u128(ref low, packed::EXP2_42, packed::EXP2_42, (*roster.at(1)).into()); }
    if len > 2 { pack_u128(ref low, packed::EXP2_84, packed::EXP2_42, (*roster.at(2)).into()); }

    if len > 3 { pack_u128(ref high, packed::EXP2_0, packed::EXP2_42, (*roster.at(3)).into()); }
    if len > 4 { pack_u128(ref high, packed::EXP2_42, packed::EXP2_42, (*roster.at(4)).into()); }

    return low.into() + high.into() * packed::EXP2_128;
}

fn unpack_roster(packed: felt252) -> Span<u64> {
    let mut roster: Array<u64> = Default::default();
    let (low, high) = split_felt252(packed);

    let pos0 = unpack_u128(low, packed::EXP2_0, packed::EXP2_42);
    if pos0 != 0 {
        roster.append(pos0.try_into().unwrap());
    } else {
        return roster.span();
    }

    let pos1 = unpack_u128(low, packed::EXP2_42, packed::EXP2_42);
    if pos1 != 0 {
        roster.append(pos1.try_into().unwrap());
    } else {
        return roster.span();
    }

    let pos2 = unpack_u128(low, packed::EXP2_84, packed::EXP2_42);
    if pos2 != 0 {
        roster.append(pos2.try_into().unwrap());
    } else {
        return roster.span();
    }

    let pos3 = unpack_u128(high, packed::EXP2_0, packed::EXP2_42);
    if pos3 != 0 {
        roster.append(pos3.try_into().unwrap());
    } else {
        return roster.span();
    }

    let pos4 = unpack_u128(high, packed::EXP2_42, packed::EXP2_42);
    if pos4 != 0 {
        roster.append(pos4.try_into().unwrap());
    }

    return roster.span();
}

impl StoreCrew of Store<Crew> {
    #[inline(always)]
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<Crew> {
        return Self::read_at_offset(address_domain, base, 0);
    }

    #[inline(always)]
    fn write(address_domain: u32, base: StorageBaseAddress, value: Crew) -> SyscallResult<()> {
        return Self::write_at_offset(address_domain, base, 0, value);
    }

    #[inline(always)]
    fn read_at_offset(address_domain: u32, base: StorageBaseAddress, offset: u8) -> SyscallResult<Crew> {
        let delegated_to = Store::<ContractAddress>::read_at_offset(address_domain, base, offset)?;
        let roster = Store::<felt252>::read_at_offset(address_domain, base, offset + 1)?;
        let survival = Store::<felt252>::read_at_offset(address_domain, base, offset + 2)?;
        let (low, high) = split_felt252(survival);

        let mut result = CrewTrait::new(delegated_to);
        result.roster = unpack_roster(roster);
        result.last_fed = unpack_u128(low, packed::EXP2_0, packed::EXP2_36).try_into().unwrap();
        result.ready_at = unpack_u128(low, packed::EXP2_36, packed::EXP2_36).try_into().unwrap();
        result.action_type = unpack_u128(low, packed::EXP2_72, packed::EXP2_20).try_into().unwrap();

        // If no action type recorded, don't bother unpacking the rest
        if result.action_type != 0 {
            result.action_target = unpack_u128(high, packed::EXP2_0, packed::EXP2_80).try_into().unwrap();
            result.action_round = unpack_u128(low, packed::EXP2_92, packed::EXP2_36).try_into().unwrap();
            result.action_weight = unpack_u128(high, packed::EXP2_80, packed::EXP2_16).try_into().unwrap();
            result.action_strategy = unpack_u128(high, packed::EXP2_96, packed::EXP2_4).try_into().unwrap();
        }

        return Result::Ok(result);
    }

    #[inline(always)]
    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: Crew
    ) -> SyscallResult<()> {
        let mut low: u128 = 0;
        let mut high: u128 = 0;

        pack_u128(ref low, packed::EXP2_0, packed::EXP2_36, value.last_fed.into());
        pack_u128(ref low, packed::EXP2_36, packed::EXP2_36, value.ready_at.into());
        pack_u128(ref low, packed::EXP2_72, packed::EXP2_20, value.action_type.into());
        pack_u128(ref high, packed::EXP2_0, packed::EXP2_80, value.action_target.into());
        pack_u128(ref low, packed::EXP2_92, packed::EXP2_36, value.action_round.into());
        pack_u128(ref high, packed::EXP2_80, packed::EXP2_16, value.action_weight.into());
        pack_u128(ref high, packed::EXP2_96, packed::EXP2_4, value.action_strategy.into());

        let survival = low.into() + high.into() * packed::EXP2_128;
        Store::<ContractAddress>::write_at_offset(address_domain, base, offset, value.delegated_to).unwrap_syscall();
        Store::<felt252>::write_at_offset(address_domain, base, offset + 1, pack_roster(value.roster)).unwrap_syscall();
        return Store::<felt252>::write_at_offset(address_domain, base, offset + 2, survival);
    }

    #[inline(always)]
    fn size() -> u8 {
        return 3;
    }
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use array::{ArrayTrait, Span, SpanTrait};
    use core::starknet::SyscallResultTrait;
    use option::OptionTrait;
    use result::ResultTrait;
    use starknet::{ContractAddress, ContractAddressIntoFelt252, Felt252TryIntoContractAddress, SyscallResult,};
    use starknet::storage_access::{Store, StorageBaseAddress, storage_base_address_const};
    use traits::{Into, TryInto};

    use influence::common::{config::entities, packed};
    use influence::components::{ComponentTrait, resolve};
    use influence::types::entity::{Entity, EntityTrait};

    use super::{Crew, CrewImpl, CrewTrait, StoreCrew};

    #[test]
    fn test_retired_events_do_not_create_candidate() {
        let mut crew = CrewTrait::new(starknet::contract_address_const::<'PLAYER'>());
        crew.add_busy(100, 500);
        crew.set_action(1, EntityTrait::new(7, 1), 305000, 100);

        assert(crew.ready_at == 600, 'crew scheduling changed');
        assert(crew.action_type == 0, 'new candidate recorded');
        assert(crew.action_target == EntityTrait::new(0, 0), 'target changed');
        assert(crew.action_round == 0, 'round changed');
        assert(crew.action_weight == 0, 'weight changed');
        assert(crew.action_strategy == 0, 'strategy changed');
        crew.assert_ready(600);
    }

    #[test]
    fn test_retired_events_preserve_pending_candidate() {
        let mut crew = CrewTrait::new(starknet::contract_address_const::<'PLAYER'>());
        crew.action_type = 1;
        crew.action_target = EntityTrait::new(7, 1);
        crew.action_round = 2;
        crew.action_weight = 100;
        crew.action_strategy = 2;

        crew.add_busy(100, 500);
        crew.set_action(2, EntityTrait::new(5, 2), 305000, 100);

        assert(crew.ready_at == 600, 'crew scheduling changed');
        assert(crew.action_type == 1, 'pending type changed');
        assert(crew.action_target == EntityTrait::new(7, 1), 'pending target changed');
        assert(crew.action_round == 2, 'pending round changed');
        assert(crew.action_weight == 100, 'pending weight changed');
        assert(crew.action_strategy == 2, 'pending strategy changed');
    }

    #[test]
    #[available_gas(500000)]
    fn test_storage() {
        let base = starknet::storage_base_address_from_felt252(42);
        let crewmates = array![2, 4, 5];
        Store::<Crew>::write(0, base, Crew {
            delegated_to: starknet::contract_address_const::<'PLAYER'>(),
            roster: crewmates.span(),
            last_fed: 2345,
            ready_at: 3456,
            action_type: 1,
            action_target: EntityTrait::new(3, 1),
            action_round: 2,
            action_weight: 25000,
            action_strategy: 2
        }).unwrap_syscall();

        let read_crew = Store::<Crew>::read(0, base).unwrap_syscall();
        assert(read_crew.delegated_to.into() == 'PLAYER', 'should have delegated_to');
        assert(read_crew.roster.len() == 3, 'should have crewmates');
        assert(*read_crew.roster.at(2) == 5, 'should have crewmate 2');
        assert(read_crew.last_fed == 2345, 'should have last_fed');
        assert(read_crew.ready_at == 3456, 'should have rest_until');
        assert(read_crew.action_type == 1, 'should have action_type');
        assert(read_crew.action_target == EntityTrait::new(3, 1), 'should have action_target');
        assert(read_crew.action_round == 2, 'should have action_round');
        assert(read_crew.action_weight == 25000, 'should have action_weight');
        assert(read_crew.action_strategy == 2, 'should have action_strategy');
    }
}
