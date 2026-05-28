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

const DEFAULT_MAX_PRICE: u64 = 100000000000000000; // 100 billion SWAY
const DEFAULT_MIN_PRICE: u64 = 1000000; // 1 SWAY
const DEFAULT_INITIAL_PERIOD: u64 = 0;
const DEFAULT_DESCENDING_PERIOD: u64 = 604800; // 7 days

#[derive(Copy, Drop, Serde)]
struct PrepaidAgreementAuctionSettings {
    mode: u64,
    initial_period: u64,
    descending_period: u64,
    max_price: u64,
    min_price: u64
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
    fn new(
        mode: u64, initial_period: u64, descending_period: u64, max_price: u64, min_price: u64
    ) -> PrepaidAgreementAuctionSettings;
    fn defaults() -> PrepaidAgreementAuctionSettings;
}

impl PrepaidAgreementAuctionSettingsImpl of PrepaidAgreementAuctionSettingsTrait {
    fn new(
        mode: u64, initial_period: u64, descending_period: u64, max_price: u64, min_price: u64
    ) -> PrepaidAgreementAuctionSettings {
        return PrepaidAgreementAuctionSettings {
            mode: mode,
            initial_period: initial_period,
            descending_period: descending_period,
            max_price: max_price,
            min_price: min_price
        };
    }

    fn defaults() -> PrepaidAgreementAuctionSettings {
        return PrepaidAgreementAuctionSettingsTrait::new(
            modes::MANUAL, DEFAULT_INITIAL_PERIOD, DEFAULT_DESCENDING_PERIOD, DEFAULT_MAX_PRICE, DEFAULT_MIN_PRICE
        );
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
        let initial_period = Store::<u64>::read_at_offset(address_domain, base, offset + 1)?;
        let descending_period = Store::<u64>::read_at_offset(address_domain, base, offset + 2)?;
        let max_price = Store::<u64>::read_at_offset(address_domain, base, offset + 3)?;
        let min_price = Store::<u64>::read_at_offset(address_domain, base, offset + 4)?;

        return Result::Ok(PrepaidAgreementAuctionSettings {
            mode: mode,
            initial_period: initial_period,
            descending_period: descending_period,
            max_price: max_price,
            min_price: min_price
        });
    }

    #[inline(always)]
    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: PrepaidAgreementAuctionSettings
    ) -> SyscallResult<()> {
        Store::<u64>::write_at_offset(address_domain, base, offset, value.mode)?;
        Store::<u64>::write_at_offset(address_domain, base, offset + 1, value.initial_period)?;
        Store::<u64>::write_at_offset(address_domain, base, offset + 2, value.descending_period)?;
        Store::<u64>::write_at_offset(address_domain, base, offset + 3, value.max_price)?;
        return Store::<u64>::write_at_offset(address_domain, base, offset + 4, value.min_price);
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
        let settings = PrepaidAgreementAuctionSettingsTrait::new(modes::AUTO, 10, 20, 30, 40);

        Store::<PrepaidAgreementAuctionSettings>::write(0, base, settings);
        let read_settings = Store::<PrepaidAgreementAuctionSettings>::read(0, base).unwrap();

        assert(read_settings.mode == modes::AUTO, 'mode wrong');
        assert(read_settings.initial_period == 10, 'initial wrong');
        assert(read_settings.descending_period == 20, 'descending wrong');
        assert(read_settings.max_price == 30, 'max wrong');
        assert(read_settings.min_price == 40, 'min wrong');
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
