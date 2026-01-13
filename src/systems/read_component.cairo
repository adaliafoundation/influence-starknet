#[starknet::contract]
mod ReadComponent {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use serde::Serde;

    use influence::components;
    use influence::config::errors;
    use influence::types::{Context, Entity, EntityTrait};

    #[storage]
    struct Storage {}

    #[external(v0)]
    fn run(self: @ContractState, name: felt252, path: Span<felt252>, context: Context) -> Span<felt252> {
        let mut res: Array<felt252> = Default::default();

        if name == 'Building' {
            let comp_data = components::get::<components::Building>(path).expect(errors::BUILDING_NOT_FOUND);
            Serde::<components::Building>::serialize(@comp_data, ref res);
        } else if name == 'BuildingType' {
            let comp_data = components::get::<components::BuildingType>(path).expect(errors::BUILDING_TYPE_NOT_FOUND);
            Serde::<components::BuildingType>::serialize(@comp_data, ref res);
        } else if name == 'Celestial' {
            let comp_data = components::get::<components::Celestial>(path).expect(errors::CELESTIAL_NOT_FOUND);
            Serde::<components::Celestial>::serialize(@comp_data, ref res);
        } else if name == 'Control' {
            let comp_data = components::get::<components::Control>(path).expect(errors::CONTROL_NOT_FOUND);
            Serde::<components::Control>::serialize(@comp_data, ref res);
        } else if name == 'Crew' {
            let comp_data = components::get::<components::Crew>(path).expect(errors::CREW_NOT_FOUND);
            Serde::<components::Crew>::serialize(@comp_data, ref res);
        } else if name == 'Crewmate' {
            let comp_data = components::get::<components::Crewmate>(path).expect(errors::CREWMATE_NOT_FOUND);
            Serde::<components::Crewmate>::serialize(@comp_data, ref res);
        } else if name == 'Delivery' {
            let comp_data = components::get::<components::Delivery>(path).expect(errors::DELIVERY_NOT_FOUND);
            Serde::<components::Delivery>::serialize(@comp_data, ref res);
        } else if name == 'Deposit' {
            let comp_data = components::get::<components::Deposit>(path).expect(errors::DEPOSIT_NOT_FOUND);
            Serde::<components::Deposit>::serialize(@comp_data, ref res);
        } else if name == 'Dock' {
            let comp_data = components::get::<components::Dock>(path).expect(errors::DOCK_NOT_FOUND);
            Serde::<components::Dock>::serialize(@comp_data, ref res);
        } else if name == 'DockType' {
            let comp_data = components::get::<components::DockType>(path).expect(errors::DOCK_TYPE_NOT_FOUND);
            Serde::<components::DockType>::serialize(@comp_data, ref res);
        } else if name == 'DryDock' {
            let comp_data = components::get::<components::DryDock>(path).expect(errors::DRY_DOCK_NOT_FOUND);
            Serde::<components::DryDock>::serialize(@comp_data, ref res);
        } else if name == 'DryDockType' {
            let comp_data = components::get::<components::DryDockType>(path).expect(errors::DRY_DOCK_TYPE_NOT_FOUND);
            Serde::<components::DryDockType>::serialize(@comp_data, ref res);
        } else if name == 'Exchange' {
            let comp_data = components::get::<components::Exchange>(path).expect(errors::EXCHANGE_NOT_FOUND);
            Serde::<components::Exchange>::serialize(@comp_data, ref res);
        } else if name == 'ExchangeType' {
            let comp_data = components::get::<components::ExchangeType>(path).expect(errors::EXCHANGE_TYPE_NOT_FOUND);
            Serde::<components::ExchangeType>::serialize(@comp_data, ref res);
        } else if name == 'Extractor' {
            let comp_data = components::get::<components::Extractor>(path).expect(errors::EXTRACTOR_NOT_FOUND);
            Serde::<components::Extractor>::serialize(@comp_data, ref res);
        } else if name == 'Inventory' {
            let comp_data = components::get::<components::Inventory>(path).expect(errors::INVENTORY_NOT_FOUND);
            Serde::<components::Inventory>::serialize(@comp_data, ref res);
        } else if name == 'InventoryType' {
            let comp_data = components::get::<components::InventoryType>(path).expect(errors::INVENTORY_TYPE_NOT_FOUND);
            Serde::<components::InventoryType>::serialize(@comp_data, ref res);
        } else if name == 'Location' {
            let comp_data = components::get::<components::Location>(path).expect(errors::LOCATION_NOT_FOUND);
            Serde::<components::Location>::serialize(@comp_data, ref res);
        } else if name == 'ModifierType' {
            let comp_data = components::get::<components::ModifierType>(path).expect(errors::MODIFIER_TYPE_NOT_FOUND);
            Serde::<components::ModifierType>::serialize(@comp_data, ref res);
        } else if name == 'Name' {
            let comp_data = components::get::<components::Name>(path).expect(errors::NAME_NOT_FOUND);
            Serde::<components::Name>::serialize(@comp_data, ref res);
        } else if name == 'Orbit' {
            let comp_data = components::get::<components::Orbit>(path).expect(errors::ORBIT_NOT_FOUND);
            Serde::<components::Orbit>::serialize(@comp_data, ref res);
        } else if name == 'Order' {
            let comp_data = components::get::<components::Order>(path).expect(errors::ORDER_NOT_FOUND);
            Serde::<components::Order>::serialize(@comp_data, ref res);
        } else if name == 'PrivateSale' {
            let comp_data = components::get::<components::PrivateSale>(path).expect(errors::PRIVATE_SALE_NOT_FOUND);
            Serde::<components::PrivateSale>::serialize(@comp_data, ref res);
        } else if name == 'ProcessType' {
            let comp_data = components::get::<components::ProcessType>(path).expect(errors::PROCESS_TYPE_NOT_FOUND);
            Serde::<components::ProcessType>::serialize(@comp_data, ref res);
        } else if name == 'Processor' {
            let comp_data = components::get::<components::Processor>(path).expect(errors::PROCESSOR_NOT_FOUND);
            Serde::<components::Processor>::serialize(@comp_data, ref res);
        } else if name == 'ProductType' {
            let comp_data = components::get::<components::ProductType>(path).expect(errors::PRODUCT_TYPE_NOT_FOUND);
            Serde::<components::ProductType>::serialize(@comp_data, ref res);
        } else if name == 'Ship' {
            let comp_data = components::get::<components::Ship>(path).expect(errors::SHIP_NOT_FOUND);
            Serde::<components::Ship>::serialize(@comp_data, ref res);
        } else if name == 'ShipType' {
            let comp_data = components::get::<components::ShipType>(path).expect(errors::SHIP_TYPE_NOT_FOUND);
            Serde::<components::ShipType>::serialize(@comp_data, ref res);
        } else if name == 'ShipVariantType' {
            let comp_data = components::get::<components::ShipVariantType>(path)
                .expect(errors::SHIP_VARIANT_TYPE_NOT_FOUND);
            Serde::<components::ShipVariantType>::serialize(@comp_data, ref res);
        } else if name == 'Station' {
            let comp_data = components::get::<components::Station>(path).expect(errors::STATION_NOT_FOUND);
            Serde::<components::Station>::serialize(@comp_data, ref res);
        } else if name == 'StationType' {
            let comp_data = components::get::<components::StationType>(path).expect(errors::STATION_TYPE_NOT_FOUND);
            Serde::<components::StationType>::serialize(@comp_data, ref res);
        } else if name == 'Unique' {
            let comp_data = components::get::<components::Unique>(path).expect(errors::UNIQUE_NOT_FOUND);
            Serde::<components::Unique>::serialize(@comp_data, ref res);
        } else if name == 'ContractPolicy' {
            let comp_data = components::get::<components::ContractPolicy>(path).expect(errors::CONTRACT_POLICY_NOT_FOUND);
            Serde::<components::ContractPolicy>::serialize(@comp_data, ref res);
        } else if name == 'PrepaidPolicy' {
            let comp_data = components::get::<components::PrepaidPolicy>(path).expect(errors::PREPAID_POLICY_NOT_FOUND);
            Serde::<components::PrepaidPolicy>::serialize(@comp_data, ref res);
        } else if name == 'PublicPolicy' {
            let comp_data = components::get::<components::PublicPolicy>(path).expect(errors::PUBLIC_POLICY_NOT_FOUND);
            Serde::<components::PublicPolicy>::serialize(@comp_data, ref res);
        } else if name == 'ContractAgreement' {
            let comp_data = components::get::<components::ContractAgreement>(path).expect(errors::CONTRACT_AGREEMENT_NOT_FOUND);
            Serde::<components::ContractAgreement>::serialize(@comp_data, ref res);
        } else if name == 'PrepaidAgreement' {
            let comp_data = components::get::<components::PrepaidAgreement>(path).expect(errors::PREPAID_AGREEMENT_NOT_FOUND);
            Serde::<components::PrepaidAgreement>::serialize(@comp_data, ref res);
        } else if name == 'WhitelistAgreement' {
            let comp_data = components::get::<components::WhitelistAgreement>(path).expect(errors::WHITELIST_AGREEMENT_NOT_FOUND);
            Serde::<components::WhitelistAgreement>::serialize(@comp_data, ref res);
        } else {
            assert(false, 'unknown component');
        }

        return res.span();
    }
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use array::{ArrayTrait, SpanTrait};

    use influence::components;
    use influence::components::{Name, NameTrait};
    use influence::config::entities;
    use influence::types::{EntityTrait, StringTrait};
    use influence::test::mocks;

    use super::ReadComponent;

    #[test]
    #[available_gas(2000000)]
    fn test_read_name() {
        let entity = EntityTrait::new(entities::ASTEROID, 42);
        components::set::<Name>(entity.path(), Name { name: StringTrait::new('The Answer') });

        let mut state = ReadComponent::contract_state_for_testing();
        let res = ReadComponent::run(@state, 'Name', entity.path(), mocks::context('PLAYER'));
        assert(*res.at(0) == 'The Answer', 'wrong name');
    }
}