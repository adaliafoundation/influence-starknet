use option::OptionTrait;
use starknet::{ContractAddress, Felt252TryIntoContractAddress};
use traits::{Into, TryInto};

use influence::{contracts, config, components};
use influence::components::{Crew, CrewTrait, crewmate::{Crewmate, CrewmateTrait, collections}};
use influence::config::{entities, errors};
use influence::contracts::crew::{ICrewDispatcher, ICrewDispatcherTrait};
use influence::contracts::crewmate::{ICrewmateDispatcher, ICrewmateDispatcherTrait};
use influence::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
use influence::interfaces::erc721::{IERC721Dispatcher, IERC721DispatcherTrait};
use influence::types::entity::{Entity, EntityTrait};

// Modifies the potentially empty crewmate and returns the Crewmate component
fn find_or_purchase_crewmate(ref crewmate: Entity, caller: ContractAddress) -> Crewmate {
    assert(crewmate.label == entities::CREWMATE, 'must be a crewmate entity');

    match components::get::<Crewmate>(crewmate.path()) {
        Option::Some(crewmate_data) => crewmate_data,
        Option::None(_) => {
            let (new_crewmate, crewmate_data) = purchase_crewmate(collections::ADALIAN, caller);
            crewmate.id = new_crewmate.id;
            return crewmate_data;
        }
    }
}

fn purchase_crewmate(collection: u64, caller: ContractAddress) -> (Entity, Crewmate) {
    let price = _crewmate_price(collection);

    // Transfer ERC20 tokens to Influence receivables account
    let token = IERC20Dispatcher { contract_address: config::get('ADALIAN_PURCHASE_TOKEN').try_into().unwrap() };
    token.transferFrom(caller, contracts::get('ReceivablesAccount'), price.into());

    let id = ICrewmateDispatcher { contract_address: contracts::get('Crewmate') }.mint_with_auto_id(caller);
    let crewmate = EntityTrait::new(entities::CREWMATE, id.try_into().unwrap());
    let crewmate_data = CrewmateTrait::new(collection);
    components::set::<Crewmate>(crewmate.path(), crewmate_data);

    return (crewmate, crewmate_data);
}

fn _crewmate_price(collection: u64) -> u128 {
    let price: u128 = config::get('ADALIAN_PURCHASE_PRICE').try_into().unwrap();
    assert(price > 0, errors::SALE_NOT_ACTIVE);
    assert(collection == collections::ADALIAN, errors::SALE_NOT_ACTIVE);
    return price;
}

fn assert_owner(name: felt252, nft: Entity, caller: ContractAddress) {
    let contract_address = contracts::get(name);
    let exists = IERC721Dispatcher { contract_address: contract_address }.exists(nft.id.into());
    assert(exists, 'does not exist');

    let owner = IERC721Dispatcher { contract_address: contract_address }.owner_of(nft.id.into());
    assert(owner.into() == caller, 'not owner');
}
