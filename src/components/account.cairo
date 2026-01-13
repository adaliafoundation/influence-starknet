use array::{ArrayTrait, Span, SpanTrait};
use core::starknet::SyscallResultTrait;
use option::OptionTrait;
use result::ResultTrait;
use starknet::SyscallResult;
use starknet::storage_access::{Store, StorageBaseAddress, storage_base_address_const};
use traits::{Into, TryInto};

use influence::common::{config::entities, packed};
use influence::components::{ComponentTrait, resolve};
use influence::types::entity::{Entity, EntityTrait, EntityIntoFelt252, Felt252TryIntoEntity};

#[derive(Copy, Drop, Serde)]
struct Account {
    messaging_key_x: u256,
    messaging_key_y: u256
}

impl AccountComponent of ComponentTrait<Account> {
    fn name() -> felt252 {
        return 'Account';
    }

    fn is_set(data: Account) -> bool {
        return data.messaging_key_x != 0;
    }

    fn version() -> u64 {
        return 0;
    }
}

trait AccountTrait {
    fn new(messaging_key_x: u256, messaging_key_y: u256) -> Account;
}

impl AccountImpl of AccountTrait {
    fn new(messaging_key_x: u256, messaging_key_y: u256) -> Account {
        return Account {
            messaging_key_x: messaging_key_x,
            messaging_key_y: messaging_key_y
        };
    }
}

// Storage Access -----------------------------------------------------------------------------------------------------

impl StoreAccount of Store<Account> {
    #[inline(always)]
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<Account> {
        return StoreAccount::read_at_offset(address_domain, base, 0);
    }

    #[inline(always)]
    fn write(address_domain: u32, base: StorageBaseAddress, value: Account) -> SyscallResult<()> {
        return StoreAccount::write_at_offset(address_domain, base, 0, value);
    }

    #[inline(always)]
    fn read_at_offset(address_domain: u32, base: StorageBaseAddress, offset: u8) -> SyscallResult<Account> {
        let messaging_key_x = Store::<u256>::read_at_offset(address_domain, base, offset)?;
        let messaging_key_y = Store::<u256>::read_at_offset(address_domain, base, offset + 2)?;
        return Result::Ok(Account { messaging_key_x: messaging_key_x, messaging_key_y: messaging_key_y });
    }

    #[inline(always)]
    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: Account
    ) -> SyscallResult<()> {
        Store::<u256>::write_at_offset(address_domain, base, offset, value.messaging_key_x);
        return Store::<u256>::write_at_offset(address_domain, base, offset + 2, value.messaging_key_y);
    }

    #[inline(always)]
    fn size() -> u8 {
        return 4;
    }
}

// Tests --------------------------------------------------------------------------------------------------------------
#[cfg(test)]
mod tests {
    use array::{ArrayTrait, Span, SpanTrait};
    use core::starknet::SyscallResultTrait;
    use option::OptionTrait;
    use result::ResultTrait;
    use starknet::SyscallResult;
    use starknet::storage_access::{Store, StorageBaseAddress, storage_base_address_const};
    use traits::{Into, TryInto};

    use influence::common::{config::entities, packed};
    use influence::components::{ComponentTrait, resolve};
    use influence::types::entity::{Entity, EntityTrait, EntityIntoFelt252, Felt252TryIntoEntity};

    use super::{AccountTrait, AccountImpl, AccountComponent, Account, StoreAccount};
use debug::PrintTrait;
    #[test]
    #[available_gas(1000000)]
    fn test_storage() {
        let key_x = 0x1234567890abcdef;
        let key_y = 0xabcdef1234567890;
        let account = AccountTrait::new(key_x, key_y);
        let base = starknet::storage_base_address_from_felt252(42);

        // Should now have key
        Store::<Account>::write(0, base, account);
        let mut read_account = Store::<Account>::read(0, base).unwrap_syscall();
        assert(read_account.messaging_key_x == key_x, 'should have key x');
        assert(read_account.messaging_key_y == key_y, 'should have key y');

        // Clear control and check
        let empty_account = AccountTrait::new(0, 0);
        Store::<Account>::write(0, base, empty_account);
        read_account = Store::<Account>::read(0, base).unwrap_syscall();
        assert(read_account.messaging_key_x == 0, 'should not have key x');
        assert(read_account.messaging_key_y == 0, 'should not have key y');
    }
}
