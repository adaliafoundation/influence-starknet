use array::{Array, ArrayTrait};
use hash::LegacyHash;
use option::OptionTrait;
use starknet::{ClassHash, SyscallResultTrait};
use starknet::storage_access::StorageAddress;
use traits::{Into, TryInto};

use influence::config::entities;
use influence::types::entity::{Entity, EntityTrait};

const selector: felt252 = 0x33d651fd171d8726702acd5048eae65acee9a1974492e523dee2e62b1bcc1f9; // scoped_ids

// Retrives the current scoped id
fn current_id(scope: felt252) -> u64 {
    let base = starknet::storage_base_address_from_felt252(LegacyHash::hash(selector, scope));
    let address = starknet::storage_address_from_base_and_offset(base, 0);
    let id = starknet::storage_read_syscall(0, address).unwrap_syscall();
    return id.try_into().unwrap();
}

// Generates a new scoped id
fn next_id(scope: felt252) -> u64 {
    let base = starknet::storage_base_address_from_felt252(LegacyHash::hash(selector, scope));
    let address = starknet::storage_address_from_base_and_offset(base, 0);
    let previous_id = starknet::storage_read_syscall(0, address).unwrap_syscall();
    let next_id = previous_id + 1;
    starknet::storage_write_syscall(0, address, next_id);
    return next_id.try_into().unwrap();
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
  use array::{Array, ArrayTrait};
  use hash::LegacyHash;
  use option::OptionTrait;
  use starknet::{ClassHash, SyscallResultTrait};
  use starknet::storage_access::StorageAddress;
  use traits::{Into, TryInto};

  #[test]
  #[available_gas(1000000)]
  fn test_get_new_id() {
      let mut next_id = super::next_id(super::entities::ASTEROID.into());
      assert(next_id == 1, 'next_id should be 1');

      next_id = super::next_id(super::entities::ASTEROID.into());
      assert(next_id == 2, 'next_id should be 2');
  }
}
