use array::ArrayTrait;
use hash::LegacyHash;
use option::OptionTrait;
use starknet::{ClassHash, SyscallResultTrait, Felt252TryIntoClassHash, StorageAddress};
use traits::{Into, TryInto};

use influence::common::packed;
use influence::config;
use influence::types::array::ArrayHashTrait;

const RANDOM_COMMITS: felt252 = 0x29011fb882a9aa9869e71c29e12509ab39ede745d5ff572168c799084d4a42e; // random_commits

mod strategies {
    const ENTROPY: u64 = 1;
    const BLOCKHASH: u64 = 2;
}

fn commit(key: felt252, round_delay: u64) {
    let base = starknet::storage_base_address_from_felt252(LegacyHash::hash(RANDOM_COMMITS, key));
    let address = starknet::storage_address_from_base_and_offset(base, 0);

    // Check that it hasn't been committed to already
    assert(starknet::storage_read_syscall(0, address).unwrap_syscall() == 0, 'already committed');
    assert(round_delay != 0, 'must be one or more');
    let mut committed_round = 0;

    let strategy = get_strategy();
    if strategy == strategies::ENTROPY {
        committed_round = entropy::committed_round(round_delay);
    } else if strategy == strategies::BLOCKHASH {
        committed_round = blockhash::committed_round(round_delay);
    } else {
        assert(false, 'invalid randomness strategy');
    }

    // Save to storage
    let mut commitment = 0;
    packed::pack_u128(ref commitment, packed::EXP2_0, packed::EXP2_4, strategy.into());
    packed::pack_u128(ref commitment, packed::EXP2_4, packed::EXP2_36, committed_round.into());
    starknet::storage_write_syscall(0, address, commitment.into());
}

fn reveal(key: felt252) -> felt252 {
    // Check that the current round is later than committed round
    let (strategy, committed_round) = get_commitment(key);
    let mut random = 0;

    if strategy == strategies::ENTROPY {
        random = entropy::reveal(committed_round);
    } else if strategy == strategies::BLOCKHASH {
        random = blockhash::reveal(committed_round);
    } else {
        assert(false, 'invalid randomness strategy');
    }

    assert(random != 0, 'random not revealed');

    // Salt random with commitment key
    let mut to_hash: Array<felt252> = Default::default();
    to_hash.append(key);
    to_hash.append(random);
    return to_hash.hash();
}

// Retrieves a previous commitment
fn get_commitment(key: felt252) -> (u64, u64) {
    let base = starknet::storage_base_address_from_felt252(LegacyHash::hash(RANDOM_COMMITS, key));
    let address = starknet::storage_address_from_base_and_offset(base, 0);
    let commitment: u128 = starknet::storage_read_syscall(0, address).unwrap_syscall().try_into().unwrap();
    let strategy = packed::unpack_u128(commitment, packed::EXP2_0, packed::EXP2_4).try_into().unwrap();
    let committed_round = packed::unpack_u128(commitment, packed::EXP2_4, packed::EXP2_36).try_into().unwrap();
    return (strategy, committed_round);
}

fn get_current_round(strategy: u64) -> u64 {
    if strategy == strategies::ENTROPY {
        return entropy::committed_round(0);
    } else if strategy == strategies::BLOCKHASH {
        return blockhash::committed_round(0);
    } else {
        assert(false, 'invalid randomness strategy');
    }

    return 0;
}

fn get_random(strategy: u64, round: u64) -> felt252 {
    if strategy == strategies::ENTROPY {
        return entropy::reveal(round);
    } else if strategy == strategies::BLOCKHASH {
        return blockhash::reveal(round);
    } else {
        assert(false, 'invalid randomness strategy');
    }

    return 0;
}

// Returns the current randomness strategy
fn get_strategy() -> u64 {
    let strategy = config::get('RANDOM_STRATEGY').try_into().unwrap();

    if strategy == 0 {
        return strategies::ENTROPY; // default strategy
    } else {
        return strategy;
    }
}

// Sets the current randomness strategy
fn set_strategy(strategy: u64) {
    assert(strategy == strategies::ENTROPY || strategy == strategies::BLOCKHASH, 'invalid strategy');
    config::set('RANDOM_STRATEGY', strategy.into());
}

// Handles generating entropy based on the current block timestamp, and previous entropy
mod entropy {
    use array::ArrayTrait;
    use hash::LegacyHash;
    use option::OptionTrait;
    use starknet::{ClassHash, SyscallResultTrait};
    use traits::{Into, TryInto};

    use influence::common::packed;

    const ENTROPY_LAST: felt252 = 0x12ed0a68687678217e8e212e851aaaf26f24b745382184bac5b8f83e2089d09; // entropy_last
    const ENTROPY_ROUNDS: felt252 = 0x21a28c348e1955236f4b0effd28ed77690341014ef67914ca2d8258c6236237; // entropy_rounds

    fn committed_round(round_delay: u64) -> u64 {
        let (last_round, last_time) = get_last_random();
        return last_round + round_delay;
    }

    fn reveal(committed_round: u64) -> felt252 {
        let (last_round, last_time) = get_last_random();
        assert(last_round >= committed_round, 'round not reached');
        return get_random(committed_round);
    }

    // Returns whether a new random number was generated and the round
    fn generate() -> (felt252, u64) {
        let (last_round, last_time) = get_last_random();
        let current_time = starknet::get_block_timestamp();
        if current_time - last_time < 300 { return (0, last_round); } // generate every 5+ minutes

        let mut input: Array::<felt252> = Default::default();
        input.append(current_time.into());
        input.append(starknet::get_caller_address().into());
        let new_random = poseidon::poseidon_hash_span(input.span());

        let new_round = last_round.into() + 1;
        set_random_rounds(new_round, new_random);

        let mut last_random_info = 0;
        packed::pack_u128(ref last_random_info, packed::EXP2_0, packed::EXP2_64, new_round.into());
        packed::pack_u128(ref last_random_info, packed::EXP2_64, packed::EXP2_64, current_time.into());
        set_last_random(last_random_info.into());

        return (new_random, new_round);
    }

    // Returns (last_round, last_time)
    fn get_last_random() -> (u64, u64) {
        let base = starknet::storage_base_address_from_felt252(ENTROPY_LAST);
        let address = starknet::storage_address_from_base_and_offset(base, 0);
        let combined: u128 = starknet::storage_read_syscall(0, address).unwrap_syscall().try_into().unwrap();
        let last_round = packed::unpack_u128(combined, packed::EXP2_0, packed::EXP2_64);
        let last_time = packed::unpack_u128(combined, packed::EXP2_64, packed::EXP2_64);
        return (last_round.try_into().unwrap(), last_time.try_into().unwrap());
    }

    fn get_random(round: u64) -> felt252 {
        let base = starknet::storage_base_address_from_felt252(LegacyHash::hash(ENTROPY_ROUNDS, round));
        let address = starknet::storage_address_from_base_and_offset(base, 0);
        return starknet::storage_read_syscall(0, address).unwrap_syscall();
    }

    fn set_random_rounds(round: u64, random: felt252) {
        let base = starknet::storage_base_address_from_felt252(LegacyHash::hash(ENTROPY_ROUNDS, round));
        let address = starknet::storage_address_from_base_and_offset(base, 0);
        starknet::storage_write_syscall(0, address, random);
    }

    fn set_last_random(last: felt252) {
        let base = starknet::storage_base_address_from_felt252(ENTROPY_LAST);
        let address = starknet::storage_address_from_base_and_offset(base, 0);
        starknet::storage_write_syscall(0, address, last);
    }
}

mod blockhash {
    use starknet::SyscallResultTrait;

    // Currently the blockhash is only returned after 10 blocks
    fn committed_round(round_delay: u64) -> u64 {
        return starknet::info::get_block_number() + round_delay;
    }

    fn reveal(committed_round: u64) -> felt252 {
        let current_block = starknet::info::get_block_number();
        assert(current_block > (committed_round + 10), 'round not reached'); // 10 block lag for getting hash
        return starknet::get_block_hash_syscall(committed_round).unwrap_syscall();
    }
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::{blockhash, entropy, strategies};

    #[test]
    #[available_gas(5000000)]
    fn test_committing_to_round() {
        let key = 0x123456789abcdef123456789abcdef123456789abcdef123456789abcdef;
        let round_delay = 1;
        super::commit(key, round_delay);
        let (strategy, committed_round) = super::get_commitment(key);
        assert(strategy == strategies::ENTROPY, 'wrong strategy');
        assert(committed_round == 1, 'wrong committed round');
    }

    #[test]
    #[available_gas(5000000)]
    fn test_generate_random() {
        let key = 0x123456789abcdef123456789abcdef123456789abcdef123456789abcdef;
        let round_delay = 1;

        starknet::testing::set_block_timestamp(100);
        super::commit(key, round_delay);
        let (strategy, committed_round) = super::get_commitment(key);
        assert(strategy == strategies::ENTROPY, 'wrong strategy');
        assert(committed_round == 1, 'wrong committed round');

        starknet::testing::set_block_timestamp(1000);
        entropy::generate();

        let (last_round, last_time) = entropy::get_last_random();
        assert(last_round == 1, 'wrong last round');
        assert(last_time == 1000, 'wrong last time');
    }

    #[test]
    #[available_gas(5000000)]
    fn test_setting_strategy() {
        assert(super::get_strategy() == strategies::ENTROPY, 'wrong strategy');
        super::set_strategy(strategies::BLOCKHASH);
        assert(super::get_strategy() == strategies::BLOCKHASH, 'wrong strategy');
    }
}
