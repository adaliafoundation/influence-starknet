#[starknet::contract]
mod WriteComponent {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use serde::Serde;

    use influence::components;
    use influence::config::errors;
    use influence::types::{Context, ContextTrait, Entity, EntityTrait};

    #[storage]
    struct Storage {}

    #[external(v0)]
    fn run(
        self: @ContractState,
        name: felt252,
        path: Span<felt252>,
        mut data: Span<felt252>,
        context: Context
    ) {
        // Check the caller is the admin
        assert(context.is_admin(), 'only admin can write');

        if name == 'Building' {
            let comp_data = Serde::<components::Building>::deserialize(ref data).unwrap();
            components::set::<components::Building>(path, comp_data);
        } else if name == 'BuildingType' {
            let comp_data = Serde::<components::BuildingType>::deserialize(ref data).unwrap();
            components::set::<components::BuildingType>(path, comp_data);
        } else if name == 'Celestial' {
            let comp_data = Serde::<components::Celestial>::deserialize(ref data).unwrap();
            components::set::<components::Celestial>(path, comp_data);
        } else if name == 'Control' {
            let comp_data = Serde::<components::Control>::deserialize(ref data).unwrap();
            components::set::<components::Control>(path, comp_data);
        } else if name == 'Crew' {
            let comp_data = Serde::<components::Crew>::deserialize(ref data).unwrap();
            components::set::<components::Crew>(path, comp_data);
        } else if name == 'Crewmate' {
            let comp_data = Serde::<components::Crewmate>::deserialize(ref data).unwrap();
            components::set::<components::Crewmate>(path, comp_data);
        } else if name == 'Delivery' {
            let comp_data = Serde::<components::Delivery>::deserialize(ref data).unwrap();
            components::set::<components::Delivery>(path, comp_data);
        } else if name == 'Deposit' {
            let comp_data = Serde::<components::Deposit>::deserialize(ref data).unwrap();
            components::set::<components::Deposit>(path, comp_data);
        } else if name == 'Dock' {
            let comp_data = Serde::<components::Dock>::deserialize(ref data).unwrap();
            components::set::<components::Dock>(path, comp_data);
        } else if name == 'DockType' {
            let comp_data = Serde::<components::DockType>::deserialize(ref data).unwrap();
            components::set::<components::DockType>(path, comp_data);
        } else if name == 'DryDock' {
            let comp_data = Serde::<components::DryDock>::deserialize(ref data).unwrap();
            components::set::<components::DryDock>(path, comp_data);
        } else if name == 'DryDockType' {
            let comp_data = Serde::<components::DryDockType>::deserialize(ref data).unwrap();
            components::set::<components::DryDockType>(path, comp_data);
        } else if name == 'Exchange' {
            let comp_data = Serde::<components::Exchange>::deserialize(ref data).unwrap();
            components::set::<components::Exchange>(path, comp_data);
        } else if name == 'ExchangeType' {
            let comp_data = Serde::<components::ExchangeType>::deserialize(ref data).unwrap();
            components::set::<components::ExchangeType>(path, comp_data);
        } else if name == 'Extractor' {
            let comp_data = Serde::<components::Extractor>::deserialize(ref data).unwrap();
            components::set::<components::Extractor>(path, comp_data);
        } else if name == 'Inventory' {
            let comp_data = Serde::<components::Inventory>::deserialize(ref data).unwrap();
            components::set::<components::Inventory>(path, comp_data);
        } else if name == 'InventoryType' {
            let comp_data = Serde::<components::InventoryType>::deserialize(ref data).unwrap();
            components::set::<components::InventoryType>(path, comp_data);
        } else if name == 'Location' {
            let comp_data = Serde::<components::Location>::deserialize(ref data).unwrap();
            components::set::<components::Location>(path, comp_data);
        } else if name == 'Name' {
            let comp_data = Serde::<components::Name>::deserialize(ref data).unwrap();
            components::set::<components::Name>(path, comp_data);
        } else if name == 'ModifierType' {
            let comp_data = Serde::<components::ModifierType>::deserialize(ref data).unwrap();
            components::set::<components::ModifierType>(path, comp_data);
        } else if name == 'Orbit' {
            let comp_data = Serde::<components::Orbit>::deserialize(ref data).unwrap();
            components::set::<components::Orbit>(path, comp_data);
        } else if name == 'Order' {
            let comp_data = Serde::<components::Order>::deserialize(ref data).unwrap();
            components::set::<components::Order>(path, comp_data);
        } else if name == 'PrivateSale' {
            let comp_data = Serde::<components::PrivateSale>::deserialize(ref data).unwrap();
            components::set::<components::PrivateSale>(path, comp_data);
        } else if name == 'ProcessType' {
            let comp_data = Serde::<components::ProcessType>::deserialize(ref data).unwrap();
            components::set::<components::ProcessType>(path, comp_data);
        } else if name == 'Processor' {
            let comp_data = Serde::<components::Processor>::deserialize(ref data).unwrap();
            components::set::<components::Processor>(path, comp_data);
        } else if name == 'ProductType' {
            let comp_data = Serde::<components::ProductType>::deserialize(ref data).unwrap();
            components::set::<components::ProductType>(path, comp_data);
        } else if name == 'Ship' {
            let comp_data = Serde::<components::Ship>::deserialize(ref data).unwrap();
            components::set::<components::Ship>(path, comp_data);
        } else if name == 'ShipType' {
            let comp_data = Serde::<components::ShipType>::deserialize(ref data).unwrap();
            components::set::<components::ShipType>(path, comp_data);
        } else if name == 'ShipVariantType' {
            let comp_data = Serde::<components::ShipVariantType>::deserialize(ref data).unwrap();
            components::set::<components::ShipVariantType>(path, comp_data);
        } else if name == 'Station' {
            let comp_data = Serde::<components::Station>::deserialize(ref data).unwrap();
            components::set::<components::Station>(path, comp_data);
        } else if name == 'StationType' {
            let comp_data = Serde::<components::StationType>::deserialize(ref data).unwrap();
            components::set::<components::StationType>(path, comp_data);
        } else if name == 'Unique' {
            let comp_data = Serde::<components::Unique>::deserialize(ref data).unwrap();
            components::set::<components::Unique>(path, comp_data);
        } else if name == 'ContractPolicy' {
            let comp_data = Serde::<components::ContractPolicy>::deserialize(ref data).unwrap();
            components::set::<components::ContractPolicy>(path, comp_data);
        } else if name == 'PrepaidPolicy' {
            let comp_data = Serde::<components::PrepaidPolicy>::deserialize(ref data).unwrap();
            components::set::<components::PrepaidPolicy>(path, comp_data);
        } else if name == 'PublicPolicy' {
            let comp_data = Serde::<components::PublicPolicy>::deserialize(ref data).unwrap();
            components::set::<components::PublicPolicy>(path, comp_data);
        } else if name == 'ContractAgreement' {
            let comp_data = Serde::<components::ContractAgreement>::deserialize(ref data).unwrap();
            components::set::<components::ContractAgreement>(path, comp_data);
        } else if name == 'PrepaidAgreement' {
            let comp_data = Serde::<components::PrepaidAgreement>::deserialize(ref data).unwrap();
            components::set::<components::PrepaidAgreement>(path, comp_data);
        } else if name == 'WhitelistAgreement' {
            let comp_data = Serde::<components::WhitelistAgreement>::deserialize(ref data).unwrap();
            components::set::<components::WhitelistAgreement>(path, comp_data);
        } else {
            assert(false, 'unknown component');
        }
    }
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;

    use influence::components;
    use influence::components::{Name, NameTrait};
    use influence::config::entities;
    use influence::types::{EntityTrait, StringTrait};
    use influence::test::{helpers, mocks};

    use super::WriteComponent;

    #[test]
    #[available_gas(2000000)]
    #[should_panic(expected: ('only admin can write', ))]
    fn test_no_admin() {
        let entity = EntityTrait::new(entities::ASTEROID, 42);
        let name_data = Name { name: StringTrait::new('The Answer') };

        let mut state = WriteComponent::contract_state_for_testing();
        let mut serialized: Array<felt252> = Default::default();
        Serde::<Name>::serialize(@name_data, ref serialized);
        WriteComponent::run(@state, 'Name', entity.path(), serialized.span(), mocks::context('PLAYER'));
    }

    #[test]
    #[available_gas(2000000)]
    fn test_write_name() {
        helpers::init();

        let entity = EntityTrait::new(entities::ASTEROID, 42);
        let name_data = Name { name: StringTrait::new('The Answer') };

        let mut state = WriteComponent::contract_state_for_testing();
        let mut serialized: Array<felt252> = Default::default();
        Serde::<Name>::serialize(@name_data, ref serialized);
        WriteComponent::run(@state, 'Name', entity.path(), serialized.span(), mocks::context('ADMIN'));

        let res = components::get::<Name>(entity.path()).unwrap();
        assert(res.name.value == 'The Answer', 'wrong name');
    }
}