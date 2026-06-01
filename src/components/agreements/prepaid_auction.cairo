use array::{ArrayTrait, SpanTrait};
use core::starknet::SyscallResultTrait;
use option::OptionTrait;
use result::ResultTrait;
use starknet::SyscallResult;
use starknet::storage_access::{Store, StorageBaseAddress, storage_base_address_const};
use traits::{Into, TryInto};

use influence::components::ComponentTrait;

mod modes {
    const MANUAL: u64 = 1;
    const AUTO: u64 = 2;
}

mod statuses {
    const INACTIVE: u64 = 0;
    const ACTIVE: u64 = 1;
}

const DEFAULT_GRACE_PERIOD: u64 = 0;

#[derive(Copy, Drop, Serde)]
struct PrepaidAgreementAuctionSettings {
    mode: u64,
    grace_period: u64
}

impl PrepaidAgreementAuctionSettingsComponent of ComponentTrait<PrepaidAgreementAuctionSettings> {
    fn name() -> felt252 {
        return 'PrepaidAgrAuctionSet';
    }

    fn is_set(data: PrepaidAgreementAuctionSettings) -> bool {
        return data.mode != 0;
    }

    fn version() -> u64 {
        return 0;
    }
}

trait PrepaidAgreementAuctionSettingsTrait {
    fn new(mode: u64, grace_period: u64) -> PrepaidAgreementAuctionSettings;
    fn defaults() -> PrepaidAgreementAuctionSettings;
}

impl PrepaidAgreementAuctionSettingsImpl of PrepaidAgreementAuctionSettingsTrait {
    fn new(mode: u64, grace_period: u64) -> PrepaidAgreementAuctionSettings {
        return PrepaidAgreementAuctionSettings {
            mode: mode,
            grace_period: grace_period
        };
    }

    fn defaults() -> PrepaidAgreementAuctionSettings {
        return PrepaidAgreementAuctionSettingsTrait::new(modes::MANUAL, DEFAULT_GRACE_PERIOD);
    }
}

#[derive(Copy, Drop, Serde)]
struct PrepaidAgreementAuction {
    status: u64,
    start_time: u64
}

impl PrepaidAgreementAuctionComponent of ComponentTrait<PrepaidAgreementAuction> {
    fn name() -> felt252 {
        return 'PrepaidAgreementAuction';
    }

    fn is_set(data: PrepaidAgreementAuction) -> bool {
        return data.status != statuses::INACTIVE;
    }

    fn version() -> u64 {
        return 0;
    }
}

trait PrepaidAgreementAuctionTrait {
    fn new(start_time: u64) -> PrepaidAgreementAuction;
    fn inactive() -> PrepaidAgreementAuction;
}

impl PrepaidAgreementAuctionImpl of PrepaidAgreementAuctionTrait {
    fn new(start_time: u64) -> PrepaidAgreementAuction {
        return PrepaidAgreementAuction { status: statuses::ACTIVE, start_time: start_time };
    }

    fn inactive() -> PrepaidAgreementAuction {
        return PrepaidAgreementAuction { status: statuses::INACTIVE, start_time: 0 };
    }
}

impl StorePrepaidAgreementAuctionSettings of Store<PrepaidAgreementAuctionSettings> {
    #[inline(always)]
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<PrepaidAgreementAuctionSettings> {
        return StorePrepaidAgreementAuctionSettings::read_at_offset(address_domain, base, 0);
    }

    #[inline(always)]
    fn write(address_domain: u32, base: StorageBaseAddress, value: PrepaidAgreementAuctionSettings) -> SyscallResult<()> {
        return StorePrepaidAgreementAuctionSettings::write_at_offset(address_domain, base, 0, value);
    }

    #[inline(always)]
    fn read_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8
    ) -> SyscallResult<PrepaidAgreementAuctionSettings> {
        let mode = Store::<u64>::read_at_offset(address_domain, base, offset)?;
        let grace_period = Store::<u64>::read_at_offset(address_domain, base, offset + 1)?;

        return Result::Ok(PrepaidAgreementAuctionSettings {
            mode: mode,
            grace_period: grace_period
        });
    }

    #[inline(always)]
    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: PrepaidAgreementAuctionSettings
    ) -> SyscallResult<()> {
        Store::<u64>::write_at_offset(address_domain, base, offset, value.mode)?;
        return Store::<u64>::write_at_offset(address_domain, base, offset + 1, value.grace_period);
    }

    #[inline(always)]
    fn size() -> u8 {
        return 5;
    }
}

impl StorePrepaidAgreementAuction of Store<PrepaidAgreementAuction> {
    #[inline(always)]
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<PrepaidAgreementAuction> {
        return StorePrepaidAgreementAuction::read_at_offset(address_domain, base, 0);
    }

    #[inline(always)]
    fn write(address_domain: u32, base: StorageBaseAddress, value: PrepaidAgreementAuction) -> SyscallResult<()> {
        return StorePrepaidAgreementAuction::write_at_offset(address_domain, base, 0, value);
    }

    #[inline(always)]
    fn read_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8
    ) -> SyscallResult<PrepaidAgreementAuction> {
        let status = Store::<u64>::read_at_offset(address_domain, base, offset)?;
        let start_time = Store::<u64>::read_at_offset(address_domain, base, offset + 1)?;

        return Result::Ok(PrepaidAgreementAuction { status: status, start_time: start_time });
    }

    #[inline(always)]
    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: PrepaidAgreementAuction
    ) -> SyscallResult<()> {
        Store::<u64>::write_at_offset(address_domain, base, offset, value.status)?;
        return Store::<u64>::write_at_offset(address_domain, base, offset + 1, value.start_time);
    }

    #[inline(always)]
    fn size() -> u8 {
        return 2;
    }
}

#[cfg(test)]
mod tests {
    use option::OptionTrait;
    use result::ResultTrait;
    use starknet::Store;

    use super::{
        modes, statuses, PrepaidAgreementAuction, PrepaidAgreementAuctionTrait, PrepaidAgreementAuctionSettings,
        PrepaidAgreementAuctionSettingsTrait
    };

    #[test]
    #[available_gas(1000000)]
    fn test_settings_storage() {
        let base = starknet::storage_base_address_from_felt252(42);
        let settings = PrepaidAgreementAuctionSettingsTrait::new(modes::AUTO, 10);

        Store::<PrepaidAgreementAuctionSettings>::write(0, base, settings);
        let read_settings = Store::<PrepaidAgreementAuctionSettings>::read(0, base).unwrap();

        assert(read_settings.mode == modes::AUTO, 'mode wrong');
        assert(read_settings.grace_period == 10, 'grace wrong');
    }

    #[test]
    #[available_gas(1000000)]
    fn test_auction_storage() {
        let base = starknet::storage_base_address_from_felt252(42);
        let auction = PrepaidAgreementAuctionTrait::new(1234);

        Store::<PrepaidAgreementAuction>::write(0, base, auction);
        let read_auction = Store::<PrepaidAgreementAuction>::read(0, base).unwrap();

        assert(read_auction.status == statuses::ACTIVE, 'status wrong');
        assert(read_auction.start_time == 1234, 'start wrong');
    }
}
