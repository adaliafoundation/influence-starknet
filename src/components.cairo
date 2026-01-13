use array::{ArrayTrait, SpanTrait};
use option::OptionTrait;
use serde::Serde;
use starknet::{emit_event_syscall, ClassHash, Felt252TryIntoClassHash, SyscallResultTrait, Store, StorageBaseAddress,
    storage_base_address_const};
use traits::{Into, TryInto};

use influence::types::array::{ArrayHashTrait, SpanHashTrait};
use influence::types::entity::{Entity, EntityIntoFelt252, EntityTrait};

mod agreements;
mod policies;

mod account;
mod asteroid_sale;
mod building;
mod building_type;
mod celestial;
mod control;
mod crew;
mod crewmate;
mod delivery;
mod deposit;
mod dock;
mod dock_type;
mod dry_dock;
mod dry_dock_type;
mod exchange;
mod exchange_type;
mod extractor;
mod inventory;
mod inventory_type;
mod location;
mod modifier_type;
mod name;
mod orbit;
mod order;
mod private_sale;
mod process_type;
mod processor;
mod product_type;
mod ship;
mod ship_type;
mod ship_variant_type;
mod station;
mod station_type;
mod unique;

use agreements::contract::{ContractAgreement, ContractAgreementTrait};
use agreements::prepaid::{PrepaidAgreement, PrepaidAgreementTrait};
use agreements::whitelist::{WhitelistAgreement, WhitelistAgreementTrait};

// Types and configs
use building_type::{BuildingType, BuildingTypeTrait};
use dock_type::{DockType, DockTypeTrait};
use dry_dock_type::{DryDockType, DryDockTypeTrait};
use exchange_type::{ExchangeType, ExchangeTypeTrait};
use inventory_type::{InventoryType, InventoryTypeTrait};
use modifier_type::{ModifierType, ModifierTypeTrait};
use process_type::{ProcessType, ProcessTypeTrait};
use product_type::{ProductType, ProductTypeTrait};
use ship_type::{ShipType, ShipTypeTrait};
use ship_variant_type::{ShipVariantType, ShipVariantTypeTrait};
use station_type::{StationType, StationTypeTrait};

use policies::contract::{ContractPolicy, ContractPolicyTrait};
use policies::prepaid::{PrepaidPolicy, PrepaidPolicyTrait};
use policies::prepaid_merkle::{PrepaidMerklePolicy, PrepaidMerklePolicyTrait};
use policies::public::{PublicPolicy, PublicPolicyTrait};

use account::{Account, AccountTrait};
use asteroid_sale::AsteroidSale;
use building::{Building, BuildingTrait};
use celestial::{Celestial, CelestialTrait};
use control::{Control, ControlTrait};
use crew::{Crew, CrewTrait};
use crewmate::{Crewmate, CrewmateTrait};
use delivery::Delivery;
use deposit::{Deposit, DepositTrait};
use dock::{Dock, DockTrait};
use dry_dock::{DryDock, DryDockTrait};
use exchange::{Exchange, ExchangeTrait};
use extractor::{Extractor, ExtractorTrait};
use inventory::{Inventory, InventoryTrait};
use location::{Location, LocationTrait};
use name::{Name, NameTrait};
use orbit::{Orbit, OrbitTrait};
use order::Order;
use private_sale::{PrivateSale, PrivateSaleTrait};
use processor::{Processor, ProcessorTrait};
use ship::{Ship, ShipTrait};
use station::{Station, StationTrait};
use unique::{Unique, UniqueTrait};

const STORAGE_STRATEGY: u32 = 0; // rollup
const EVENT_NAME: felt252 = 0x297be67eb977068ccd2304c6440368d4a6114929aeb860c98b6a7e91f96e2ef; // ComponentUpdated

trait ComponentTrait<T> {
    fn name() -> felt252;
    fn is_set(data: T) -> bool;
    fn version() -> u64;
}

fn get<
    T,
    impl TComponent: ComponentTrait<T>,
    impl TStorage: Store<T>,
    impl TSerde: Serde<T>,
    impl TDrop: Copy<T>,
    impl TDrop: Drop<T>,
    impl TSerde: Serde<T>
>(
    path: Span<felt252>
) -> Option<T> {
    let base = resolve(ComponentTrait::<T>::name(), path);
    let data = Store::<T>::read(STORAGE_STRATEGY, base).unwrap_syscall();

    if ComponentTrait::<T>::is_set(data) {
        return Option::Some(data);
    } else {
        return Option::None(());
    }
}

fn set<
    T,
    impl TComponent: ComponentTrait<T>,
    impl TStorage: Store<T>,
    impl TDrop: Copy<T>,
    impl TDrop: Drop<T>,
    impl TSerde: Serde<T>
>(
    path: Span<felt252>, data: T
) {
    let component_name = ComponentTrait::<T>::name();
    let version = ComponentTrait::<T>::version();
    let base = resolve(component_name, path);
    Store::<T>::write(STORAGE_STRATEGY, base, data);

    // Emit event
    let mut event_keys: Array<felt252> = array![EVENT_NAME, component_name];

    if version != 0 {
        event_keys.append(version.into());
    }

    let mut values = Default::default();
    serde::Serde::<Array<felt252>>::serialize(path.snapshot, ref values);
    serde::Serde::<T>::serialize(@data, ref values);
    emit_event_syscall(event_keys.span(), values.span());
}

fn resolve(name: felt252, path: Span<felt252>) -> StorageBaseAddress {
    let to_hash: Array<felt252> = array!['component', name, path.hash()];
    return starknet::storage_base_address_from_felt252(to_hash.hash());
}
