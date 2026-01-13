#[starknet::contract]
mod TypeComponent {
    use option::OptionTrait;

    use influence::components;
    use influence::config::errors;

    #[storage]
    struct Storage {}

    #[external(v0)]
    fn getBuilding(self: @ContractState, path: Span<felt252>) -> components::Building {
            let comp_data = components::get::<components::Building>(path).expect(errors::BUILDING_NOT_FOUND);
            return comp_data;
    }

    #[external(v0)]
    fn getBuildingType(self: @ContractState, path: Span<felt252>) -> components::BuildingType {
            let comp_data = components::get::<components::BuildingType>(path).expect(errors::BUILDING_TYPE_NOT_FOUND);
            return comp_data;
    }

    #[external(v0)]
    fn getCelestial(self: @ContractState, path: Span<felt252>) -> components::Celestial {
            let comp_data = components::get::<components::Celestial>(path).expect(errors::CELESTIAL_NOT_FOUND);
            return comp_data;
    }

    #[external(v0)]
    fn getControl(self: @ContractState, path: Span<felt252>) -> components::Control {
            let comp_data = components::get::<components::Control>(path).expect(errors::CONTROL_NOT_FOUND);
            return comp_data;
    }

    #[external(v0)]
    fn getCrew(self: @ContractState, path: Span<felt252>) -> components::Crew {
            let comp_data = components::get::<components::Crew>(path).expect(errors::CREW_NOT_FOUND);
            return comp_data;
    }

    #[external(v0)]
    fn getCrewmate(self: @ContractState, path: Span<felt252>) -> components::Crewmate {
            let comp_data = components::get::<components::Crewmate>(path).expect(errors::CREWMATE_NOT_FOUND);
            return comp_data;
    }

    #[external(v0)]
    fn getDelivery(self: @ContractState, path: Span<felt252>) -> components::Delivery {
            let comp_data = components::get::<components::Delivery>(path).expect(errors::DELIVERY_NOT_FOUND);
            return comp_data;
    }

    #[external(v0)]
    fn getDeposit(self: @ContractState, path: Span<felt252>) -> components::Deposit {
            let comp_data = components::get::<components::Deposit>(path).expect(errors::DEPOSIT_NOT_FOUND);
            return comp_data;
    }

    #[external(v0)]
    fn getDock(self: @ContractState, path: Span<felt252>) -> components::Dock {
            let comp_data = components::get::<components::Dock>(path).expect(errors::DOCK_NOT_FOUND);
            return comp_data;
    }

    #[external(v0)]
    fn getDockType(self: @ContractState, path: Span<felt252>) -> components::DockType {
            let comp_data = components::get::<components::DockType>(path).expect(errors::DOCK_TYPE_NOT_FOUND);
            return comp_data;
    }

    #[external(v0)]
    fn getDryDock(self: @ContractState, path: Span<felt252>) -> components::DryDock {
            let comp_data = components::get::<components::DryDock>(path).expect(errors::DRY_DOCK_NOT_FOUND);
            return comp_data;
    }

    #[external(v0)]
    fn getDryDockType(self: @ContractState, path: Span<felt252>) -> components::DryDockType {
            let comp_data = components::get::<components::DryDockType>(path).expect(errors::DRY_DOCK_TYPE_NOT_FOUND);
            return comp_data;
    }

    #[external(v0)]
    fn getExchange(self: @ContractState, path: Span<felt252>) -> components::Exchange {
            let comp_data = components::get::<components::Exchange>(path).expect(errors::EXCHANGE_NOT_FOUND);
            return comp_data;
    }

    #[external(v0)]
    fn getExchangeType(self: @ContractState, path: Span<felt252>) -> components::ExchangeType {
            let comp_data = components::get::<components::ExchangeType>(path).expect(errors::EXCHANGE_TYPE_NOT_FOUND);
            return comp_data;
    }

    #[external(v0)]
    fn getExtractor(self: @ContractState, path: Span<felt252>) -> components::Extractor {
            let comp_data = components::get::<components::Extractor>(path).expect(errors::EXTRACTOR_NOT_FOUND);
            return comp_data;
    }

    #[external(v0)]
    fn getInventory(self: @ContractState, path: Span<felt252>) -> components::Inventory {
            let comp_data = components::get::<components::Inventory>(path).expect(errors::INVENTORY_NOT_FOUND);
            return comp_data;
    }

    #[external(v0)]
    fn getInventoryType(self: @ContractState, path: Span<felt252>) -> components::InventoryType {
            let comp_data = components::get::<components::InventoryType>(path).expect(errors::INVENTORY_TYPE_NOT_FOUND);
            return comp_data;
    }

    #[external(v0)]
    fn getLocation(self: @ContractState, path: Span<felt252>) -> components::Location {
            let comp_data = components::get::<components::Location>(path).expect(errors::LOCATION_NOT_FOUND);
            return comp_data;
    }

    #[external(v0)]
    fn getModifierType(self: @ContractState, path: Span<felt252>) -> components::ModifierType {
            let comp_data = components::get::<components::ModifierType>(path).expect(errors::MODIFIER_TYPE_NOT_FOUND);
            return comp_data;
    }

    #[external(v0)]
    fn getName(self: @ContractState, path: Span<felt252>) -> components::Name {
            let comp_data = components::get::<components::Name>(path).expect(errors::NAME_NOT_FOUND);
            return comp_data;
    }

    #[external(v0)]
    fn getOrbit(self: @ContractState, path: Span<felt252>) -> components::Orbit {
            let comp_data = components::get::<components::Orbit>(path).expect(errors::ORBIT_NOT_FOUND);
            return comp_data;
    }

    #[external(v0)]
    fn getOrder(self: @ContractState, path: Span<felt252>) -> components::Order {
            let comp_data = components::get::<components::Order>(path).expect(errors::ORDER_NOT_FOUND);
            return comp_data;
    }

    #[external(v0)]
    fn getPrivateSale(self: @ContractState, path: Span<felt252>) -> components::PrivateSale {
            let comp_data = components::get::<components::PrivateSale>(path).expect(errors::PRIVATE_SALE_NOT_FOUND);
            return comp_data;
    }

    #[external(v0)]
    fn getProcessType(self: @ContractState, path: Span<felt252>) -> components::ProcessType {
            let comp_data = components::get::<components::ProcessType>(path).expect(errors::PROCESS_TYPE_NOT_FOUND);
            return comp_data;
    }

    #[external(v0)]
    fn getProcessor(self: @ContractState, path: Span<felt252>) -> components::Processor {
            let comp_data = components::get::<components::Processor>(path).expect(errors::PROCESSOR_NOT_FOUND);
            return comp_data;
    }

    #[external(v0)]
    fn getProductType(self: @ContractState, path: Span<felt252>) -> components::ProductType {
            let comp_data = components::get::<components::ProductType>(path).expect(errors::PRODUCT_TYPE_NOT_FOUND);
            return comp_data;
    }

    #[external(v0)]
    fn getShip(self: @ContractState, path: Span<felt252>) -> components::Ship {
            let comp_data = components::get::<components::Ship>(path).expect(errors::SHIP_NOT_FOUND);
            return comp_data;
    }

    #[external(v0)]
    fn getShipType(self: @ContractState, path: Span<felt252>) -> components::ShipType {
            let comp_data = components::get::<components::ShipType>(path).expect(errors::SHIP_TYPE_NOT_FOUND);
            return comp_data;
    }

    #[external(v0)]
    fn getShipVariantType(self: @ContractState, path: Span<felt252>) -> components::ShipVariantType {
        let comp_data = components::get::<components::ShipVariantType>(path).expect(errors::SHIP_VARIANT_TYPE_NOT_FOUND);
        return comp_data;
    }

    #[external(v0)]
    fn getStation(self: @ContractState, path: Span<felt252>) -> components::Station {
        let comp_data = components::get::<components::Station>(path).expect(errors::STATION_NOT_FOUND);
        return comp_data;
    }

    #[external(v0)]
    fn getStationType(self: @ContractState, path: Span<felt252>) -> components::StationType {
        let comp_data = components::get::<components::StationType>(path).expect(errors::STATION_TYPE_NOT_FOUND);
        return comp_data;
    }

    #[external(v0)]
    fn getUnique(self: @ContractState, path: Span<felt252>) -> components::Unique {
        let comp_data = components::get::<components::Unique>(path).expect(errors::UNIQUE_NOT_FOUND);
        return comp_data;
    }

    #[external(v0)]
    fn getContractPolicy(self: @ContractState, path: Span<felt252>) -> components::ContractPolicy {
        let comp_data = components::get::<components::ContractPolicy>(path).expect(errors::CONTRACT_POLICY_NOT_FOUND);
        return comp_data;
    }

    #[external(v0)]
    fn getPrepaidPolicy(self: @ContractState, path: Span<felt252>) -> components::PrepaidPolicy {
        let comp_data = components::get::<components::PrepaidPolicy>(path).expect(errors::PREPAID_POLICY_NOT_FOUND);
        return comp_data;
    }

    #[external(v0)]
    fn getPublicPolicy(self: @ContractState, path: Span<felt252>) -> components::PublicPolicy {
        let comp_data = components::get::<components::PublicPolicy>(path).expect(errors::PUBLIC_POLICY_NOT_FOUND);
        return comp_data;
    }

    #[external(v0)]
    fn getContractAgreement(self: @ContractState, path: Span<felt252>) -> components::ContractAgreement {
        let comp_data = components::get::<components::ContractAgreement>(path).expect(errors::CONTRACT_AGREEMENT_NOT_FOUND);
        return comp_data;
    }

    #[external(v0)]
    fn getPrepaidAgreement(self: @ContractState, path: Span<felt252>) -> components::PrepaidAgreement {
        let comp_data = components::get::<components::PrepaidAgreement>(path).expect(errors::PREPAID_AGREEMENT_NOT_FOUND);
        return comp_data;
    }

    #[external(v0)]
    fn getWhitelistAgreement(self: @ContractState, path: Span<felt252>) -> components::WhitelistAgreement {
        let comp_data = components::get::<components::WhitelistAgreement>(path).expect(errors::WHITELIST_AGREEMENT_NOT_FOUND);
        return comp_data;
    }
}
