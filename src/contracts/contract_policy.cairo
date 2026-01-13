// Mock contract to simulate contract policies
#[starknet::contract]
mod ContractPolicy {
    use influence::types::Entity;

    #[storage]
    struct Storage {
        permitted: bool
    }

    #[constructor]
    fn constructor(ref self: ContractState, permitted: bool) {
        self.permitted.write(permitted);
    }

    #[external(v0)]
    fn set_permitted(ref self: ContractState, permitted: bool) {
        self.permitted.write(permitted);
    }

    #[external(v0)]
    fn accept(ref self: ContractState, target: Entity, permission: u64, permitted: Entity) -> bool {
        return self.permitted.read();
    }

    #[external(v0)]
    fn can(self: @ContractState, target: Entity, permission: u64, permitted: Entity) -> bool {
        return self.permitted.read();
    }
}
