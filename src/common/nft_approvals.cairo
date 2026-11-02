use starknet::ContractAddress;

// Marketplace and NFT transfer-manager callers observed in the November 2026 incident.
// Keep these checks independent of storage so upgrades invalidate existing approvals.
const PYRAMID_MARKETPLACE: felt252 = 0x364847c4f39b869760a8b213186b5b553127e9420e594075d13d1ce8a1d9157;
const PYRAMID_TRANSFER_MANAGER: felt252 = 0x578a25fe5fe8f4749651be751dff8fc68d8f3d16b175d3e6ae4f99645a7d100;
const MINT_SQUARE_MARKETPLACE: felt252 = 0x79b882cb8200c1c1d20e849a2ef19124b0b8985358c1313ea6af588cfe4fec8;
const MINT_SQUARE_TRANSFER_MANAGER: felt252 = 0x4767b873669406d25dddbf67356e385a14480979e5358a411955d692576aa30;
const MINT_SQUARE_LEGACY_MARKETPLACE: felt252 = 0x713273b1982c3b870b963418843ff8cbdb8f92481cd7f663f0f0e1c94848833;
const MINT_SQUARE_LEGACY_TRANSFER_MANAGER: felt252 = 0x41682b0bcd5db29046130db68a7f6650433acabc0792db559dac247305df783;

fn is_revoked(operator: ContractAddress) -> bool {
    let address: felt252 = operator.into();
    return address == PYRAMID_MARKETPLACE
        || address == PYRAMID_TRANSFER_MANAGER
        || address == MINT_SQUARE_MARKETPLACE
        || address == MINT_SQUARE_TRANSFER_MANAGER
        || address == MINT_SQUARE_LEGACY_MARKETPLACE
        || address == MINT_SQUARE_LEGACY_TRANSFER_MANAGER;
}

#[cfg(test)]
fn revoked_operators() -> Span<felt252> {
    array![
        PYRAMID_MARKETPLACE, PYRAMID_TRANSFER_MANAGER,
        MINT_SQUARE_MARKETPLACE, MINT_SQUARE_TRANSFER_MANAGER,
        MINT_SQUARE_LEGACY_MARKETPLACE, MINT_SQUARE_LEGACY_TRANSFER_MANAGER
    ].span()
}
