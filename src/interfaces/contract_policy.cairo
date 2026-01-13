use starknet::ContractAddress;

use influence::types::Entity;

#[starknet::interface]
trait IContractPolicy<TContractState> {
    fn accept(ref self: TContractState, target: Entity, permission: u64, permitted: Entity) -> bool;
    fn can(self: @TContractState, target: Entity, permission: u64, permitted: Entity) -> bool;
}