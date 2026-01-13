// Allows a crew delegated to the actual account owner of a ship to regain control of it

#[starknet::contract]
mod CommandeerShip {
    use array::{Array, ArrayTrait};
    use option::OptionTrait;
    use starknet::{contract_address_const, ContractAddress};
    use traits::Into;

    use influence::{components, contracts};
    use influence::common::{nft, crew::CrewDetailsTrait};
    use influence::config::{entities, errors};
    use influence::components::{Control, ControlTrait, Crew, CrewTrait};
    use influence::types::{Context, Entity, EntityTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct ShipCommandeered {
        ship: Entity,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        ShipCommandeered: ShipCommandeered
    }

    #[external(v0)]
    fn run(ref self: ContractState, ship: Entity, caller_crew: Entity, context: Context) {
        // Check that crew is delegated, and ready
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_delegated_to(context.caller);
        crew_details.assert_manned();
        crew_details.assert_ready(context.now);
        let mut crew_data = crew_details.component;

        // Ensure the caller owns the ship
        let contract_address = contracts::get('Ship');
        nft::assert_owner('Ship', ship, context.caller);

        // If present on a ship in flight, update crew ready time
        let (crew_ship, crew_ship_data) = crew_details.ship();

        if crew_ship == ship && crew_ship_data.ready_at > crew_data.ready_at {
            crew_data.ready_at = crew_ship_data.ready_at;
            components::set::<Crew>(caller_crew.path(), crew_data);
        }

        components::set::<Control>(ship.path(), ControlTrait::new(caller_crew));
        self.emit(ShipCommandeered {
            ship: ship,
            caller_crew: caller_crew,
            caller: context.caller
        });
    }
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use option::OptionTrait;
    use traits::TryInto;
    use starknet::testing;

    use influence::components;
    use influence::components::{Control, Location, LocationTrait, Ship, ShipTrait};
    use influence::contracts::ship::{IShipDispatcher, IShipDispatcherTrait};
    use influence::types::entity::EntityTrait;
    use influence::test::{helpers, mocks};

    use super::CommandeerShip;

    #[test]
    #[available_gas(15000000)]
    fn test_commandeer_ship() {
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        helpers::init();
        let ship_address = helpers::deploy_ship();

        starknet::testing::set_contract_address(starknet::contract_address_const::<'ADMIN'>());
        IShipDispatcher { contract_address: ship_address }
            .add_grant(starknet::contract_address_const::<'DISPATCHER'>(), 2);

        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        let id = IShipDispatcher { contract_address: ship_address }.mint_with_auto_id(
            starknet::contract_address_const::<'PLAYER'>()
        );

        let crew = influence::test::mocks::delegated_crew(1, 'PLAYER');
        let ship = influence::test::mocks::controlled_light_transport(crew, id.try_into().unwrap());
        let caller_crew = influence::test::mocks::delegated_crew(2, 'PLAYER');
        components::set::<Location>(caller_crew.path(), LocationTrait::new(ship));

        let mut state = CommandeerShip::contract_state_for_testing();
        CommandeerShip::run(ref state, ship, caller_crew, mocks::context('PLAYER'));

        let control_data = components::get::<Control>(ship.path()).expect('control not set');
        assert(control_data.controller == caller_crew, 'control not transferred');
    }

    #[test]
    #[available_gas(15000000)]
    #[should_panic(expected: ('E2004: incorrect delegate', ))]
    fn test_commandeer_ship_fail() {
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        helpers::init();
        let ship_address = helpers::deploy_ship();

        starknet::testing::set_contract_address(starknet::contract_address_const::<'ADMIN'>());
        IShipDispatcher { contract_address: ship_address }
            .add_grant(starknet::contract_address_const::<'DISPATCHER'>(), 2);

        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        let id = IShipDispatcher { contract_address: ship_address }.mint_with_auto_id(
            starknet::contract_address_const::<'PLAYER'>()
        );

        let crew = influence::test::mocks::delegated_crew(1, 'PLAYER');
        let ship = influence::test::mocks::controlled_light_transport(crew, id.try_into().unwrap());
        let caller_crew = influence::test::mocks::delegated_crew(2, 'PLAYER');
        let mut state = CommandeerShip::contract_state_for_testing();
        CommandeerShip::run(ref state, ship, caller_crew, mocks::context('OTHER_PLAYER'));
    }

    #[test]
    #[available_gas(15000000)]
    fn test_in_flight() {
        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        helpers::init();
        let ship_address = helpers::deploy_ship();

        starknet::testing::set_contract_address(starknet::contract_address_const::<'ADMIN'>());
        IShipDispatcher { contract_address: ship_address }
            .add_grant(starknet::contract_address_const::<'DISPATCHER'>(), 2);

        starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
        let id = IShipDispatcher { contract_address: ship_address }.mint_with_auto_id(
            starknet::contract_address_const::<'PLAYER'>()
        );

        let crew = influence::test::mocks::delegated_crew(1, 'PLAYER');
        let ship = influence::test::mocks::controlled_light_transport(crew, id.try_into().unwrap());
        let origin = mocks::adalia_prime();
        let destination = mocks::asteroid();

        // Put ship in flight
        let mut ship_data = components::get::<Ship>(ship.path()).unwrap();
        ship_data.ready_at = 12345;
        ship_data.transit_origin = origin;
        ship_data.transit_departure = 1;
        ship_data.transit_destination = destination;
        ship_data.transit_arrival = 123456789;
        components::set::<Ship>(ship.path(), ship_data);

        let caller_crew = influence::test::mocks::delegated_crew(2, 'PLAYER');
        components::set::<Location>(caller_crew.path(), LocationTrait::new(ship));

        let mut state = CommandeerShip::contract_state_for_testing();
        CommandeerShip::run(ref state, ship, caller_crew, mocks::context('PLAYER'));

        let control_data = components::get::<Control>(ship.path()).expect('control not set');
        assert(control_data.controller == caller_crew, 'control not transferred');

        let crew_data = components::get::<influence::components::Crew>(caller_crew.path()).unwrap();
        assert(crew_data.ready_at == 12345, 'time not updated');
    }
}