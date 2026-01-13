use core::starknet::SyscallResultTrait;
use array::{ArrayTrait, SpanTrait};
use option::OptionTrait;
use result::ResultTrait;
use serde::Serde;
use starknet::SyscallResult;
use starknet::storage_access::{Store, StorageBaseAddress, storage_base_address_const};
use traits::{Into, TryInto};

use influence::common::{config::entities, packed, packed::{split_felt252, pack_u128, unpack_u128}};
use influence::components::{ComponentTrait, resolve};
use influence::types::entity::{Entity, EntityTrait};

// Constants ----------------------------------------------------------------------------------------------------------

mod statuses {
    const UNINITIALIZED: u64 = 0;
    const INITIALIZED: u64 = 1;
}

// Classes
mod classes {
    const PILOT: u64 = 1;
    const ENGINEER: u64 = 2;
    const MINER: u64 = 3;
    const MERCHANT: u64 = 4;
    const SCIENTIST: u64 = 5;
}

// Collections
mod collections {
    const ARVAD_SPECIALIST: u64 = 1;
    const ARVAD_CITIZEN: u64 = 2;
    const ARVAD_LEADERSHIP: u64 = 3;
    const ADALIAN: u64 = 4;
}

mod departments {
    const NAVIGATION: u64 = 1;
    const EDUCATION: u64 = 2;
    const KNOWLEDGE: u64 = 3;
    const MEDICINE: u64 = 4;
    const SECURITY: u64 = 5;
    const LOGISTICS: u64 = 6;
    const MAINTENANCE: u64 = 7;
    const TECHNOLOGY: u64 = 8;
    const ENGINEERING: u64 = 9;
    const FOOD_PRODUCTION: u64 = 10;
    const FOOD_PREPARATION: u64 = 11;
    const ARTS_ENTERTAINMENT: u64 = 12;
    const MANAGEMENT: u64 = 13;
}

// Traits
mod crewmate_traits {
    const DRIVE_SURVIVAL: u64 = 1;
    const DRIVE_SERVICE: u64 = 2;
    const DRIVE_GLORY: u64 = 3;
    const DRIVE_COMMAND: u64 = 4;
    const ADVENTUROUS: u64 = 5;
    const AMBITIOUS: u64 = 6;
    const ARROGANT: u64 = 7;
    const CAUTIOUS: u64 = 8;
    const CREATIVE: u64 = 9;
    const CURIOUS: u64 = 10;
    const FIERCE: u64 = 11;
    const FLEXIBLE: u64 = 12;
    const FRANTIC: u64 = 13;
    const HOPEFUL: u64 = 14;
    const INDEPENDENT: u64 = 15;
    const IRRATIONAL: u64 = 16;
    const LOYAL: u64 = 17;
    const PRAGMATIC: u64 = 18;
    const RATIONAL: u64 = 19;
    const RECKLESS: u64 = 20;
    const REGRESSIVE: u64 = 21;
    const SERIOUS: u64 = 22;
    const STEADFAST: u64 = 23;
    const COUNCIL_LOYALIST: u64 = 24;
    const COUNCIL_MODERATE: u64 = 25;
    const INDEPENDENT_MODERATE: u64 = 26;
    const INDEPENDENT_RADICAL: u64 = 27;
    const NAVIGATOR: u64 = 28; // impactful
    const DIETITIAN: u64 = 29; // impactful
    const REFINER: u64 = 30; // impactful
    const SURVEYOR: u64 = 31; // impactful
    const HAULER: u64 = 32; // impactful
    const OPTIMISTIC: u64 = 33;
    const THOUGHTFUL: u64 = 34;
    const PESSIMISTIC: u64 = 35;
    const RIGHTEOUS: u64 = 36;
    const COMMUNAL: u64 = 37;
    const IMPARTIAL: u64 = 38;
    const ENTERPRISING: u64 = 39;
    const OPPORTUNISTIC: u64 = 40;
    const BUSTER: u64 = 41; // impactful
    const MOGUL: u64 = 42; // impactful
    const SCHOLAR: u64 = 43;  // impactful
    const RECYCLER: u64 = 44; // impactful
    const MECHANIC: u64 = 45; // impactful
    const OPERATOR: u64 = 46; // impactful
    const LOGISTICIAN: u64 = 47; // impactful
    const EXPERIMENTER: u64 = 48; // impactful
    const BUILDER: u64 = 49; // impactful
    const PROSPECTOR: u64 = 50; // impactful
}

// Titles
mod titles {
    const COMMUNICATIONS_OFFICER: u64 = 1;
    const TEACHING_ASSISTANT: u64 = 2;
    const LIBRARIAN: u64 = 3;
    const NURSE: u64 = 4;
    const PUBLIC_SAFETY_OFFICER: u64 = 5;
    const WAREHOUSE_WORKER: u64 = 6;
    const MAINTENANCE_TECHNICIAN: u64 = 7;
    const SYSTEMS_ADMINISTRATOR: u64 = 8;
    const STRUCTURAL_ENGINEER: u64 = 9;
    const FARMER: u64 = 10;
    const LINE_COOK: u64 = 11;
    const ARTIST: u64 = 12;
    const BLOCK_CAPTAIN: u64 = 13;
    const OBSERVATORY_TECHNICIAN: u64 = 14;
    const TEACHER: u64 = 15;
    const HISTORIAN: u64 = 16;
    const PHYSICIAN_ASSISTANT: u64 = 17;
    const SECURITY_OFFICER: u64 = 18;
    const LOGISTICS_SPECIALIST: u64 = 19;
    const ELECTRICIAN: u64 = 20;
    const SOFTWARE_ENGINEER: u64 = 21;
    const LIFE_SUPPORT_ENGINEER: u64 = 22;
    const FIELD_BOTANIST: u64 = 23;
    const SECTION_COOK: u64 = 24;
    const AUTHOR: u64 = 25;
    const DELEGATE: u64 = 26;
    const CARTOGRAPHER: u64 = 27;
    const PROFESSOR: u64 = 28;
    const ARCHIVIST: u64 = 29;
    const RESIDENT_PHYSICIAN: u64 = 30;
    const TACTICAL_OFFICER: u64 = 31;
    const WAREHOUSE_MANAGER: u64 = 32;
    const EVA_TECHNICIAN: u64 = 33;
    const EMBEDDED_ENGINEER: u64 = 34;
    const PROPULSION_ENGINEER: u64 = 35;
    const NUTRITIONIST: u64 = 36;
    const KITCHEN_MANAGER: u64 = 37;
    const MUSICIAN: u64 = 38;
    const COUNCILOR: u64 = 39;
    const NAVIGATOR: u64 = 40;
    const DISTINGUISHED_PROFESSOR: u64 = 41;
    const CURATOR: u64 = 42;
    const PHYSICIAN: u64 = 43;
    const INTELLIGENCE_OFFICER: u64 = 44;
    const LOGISTICS_MANAGER: u64 = 45;
    const FACILITIES_SUPERVISOR: u64 = 46;
    const SYSTEMS_ARCHITECT: u64 = 47;
    const REACTOR_ENGINEER: u64 = 48;
    const PLANT_GENETICIST: u64 = 49;
    const CHEF: u64 = 50;
    const ACTOR: u64 = 51;
    const JUSTICE: u64 = 52;
    const CHIEF_NAVIGATOR: u64 = 53;
    const PROVOST: u64 = 54;
    const CHIEF_ARCHIVIST: u64 = 55;
    const CHIEF_MEDICAL_OFFICER: u64 = 56;
    const HEAD_OF_SECURITY: u64 = 57;
    const CHIEF_LOGISTICS_OFFICER: u64 = 58;
    const CHIEF_STEWARD: u64 = 59;
    const CHIEF_TECHNOLOGY_OFFICER: u64 = 60;
    const HEAD_OF_ENGINEERING: u64 = 61;
    const CHIEF_BOTANIST: u64 = 62;
    const CHIEF_COOK: u64 = 63;
    const ENTERTAINMENT_DIRECTOR: u64 = 64;
    const HIGH_COMMANDER: u64 = 65;
    const ADALIAN_PRIME_COUNCIL: u64 = 66;
    const FIRST_GENERATION: u64 = 67;
}

// Component ----------------------------------------------------------------------------------------------------------

#[derive(Copy, Drop, Serde)]
struct Crewmate {
    status: u64,
    collection: u64,
    class: u64,
    title: u64,
    appearance: u128,
    cosmetic: Span<u64>, // up to 6 traits
    impactful: Span<u64> // up to 6 traits
}

impl CrewmateComponent of ComponentTrait<Crewmate> {
    fn name() -> felt252 {
        return 'Crewmate';
    }

    fn is_set(data: Crewmate) -> bool {
        return data.collection != 0;
    }

    fn version() -> u64 {
        return 0;
    }
}

trait CrewmateTrait {
    fn new(collection: u64) -> Crewmate;
    fn pack_appearance(
        gender: u64, body: u64, face: u64, hair: u64, hair_color: u64, clothes: u64, head: u64, item: u64
    ) -> u128;
}

impl CrewmateImpl of CrewmateTrait {
    fn new(collection: u64) -> Crewmate {
        return Crewmate {
            status: statuses::UNINITIALIZED,
            collection: collection,
            class: 0,
            title: 0,
            appearance: 0,
            cosmetic: Default::default().span(),
            impactful: Default::default().span()
        };
    }

    fn pack_appearance(
        gender: u64, body: u64, face: u64, hair: u64, hair_color: u64, clothes: u64, head: u64, item: u64
    ) -> u128 {
        let mut appearance: u128 = 0;
        pack_u128(ref appearance, packed::EXP2_0, packed::EXP2_4, gender.into());
        pack_u128(ref appearance, packed::EXP2_4, packed::EXP2_16, body.into());
        pack_u128(ref appearance, packed::EXP2_20, packed::EXP2_16, face.into());
        pack_u128(ref appearance, packed::EXP2_36, packed::EXP2_16, hair.into());
        pack_u128(ref appearance, packed::EXP2_52, packed::EXP2_16, hair_color.into());
        pack_u128(ref appearance, packed::EXP2_68, packed::EXP2_16, clothes.into());
        pack_u128(ref appearance, packed::EXP2_84, packed::EXP2_16, head.into());
        pack_u128(ref appearance, packed::EXP2_100, packed::EXP2_8, item.into());

        return appearance;
    }
}

// Storage Access -----------------------------------------------------------------------------------------------------

fn pack_traits(traits: Span<u64>) -> u128 {
    let mut combined: u128 = 0;
    let len = traits.len();

    if len > 0 { pack_u128(ref combined, packed::EXP2_0, packed::EXP2_20, (*traits.at(0)).into()); }
    if len > 1 { pack_u128(ref combined, packed::EXP2_20, packed::EXP2_20, (*traits.at(1)).into()); }
    if len > 2 { pack_u128(ref combined, packed::EXP2_40, packed::EXP2_20, (*traits.at(2)).into()); }
    if len > 3 { pack_u128(ref combined, packed::EXP2_60, packed::EXP2_20, (*traits.at(3)).into()); }
    if len > 4 { pack_u128(ref combined, packed::EXP2_80, packed::EXP2_20, (*traits.at(4)).into()); }
    if len > 5 { pack_u128(ref combined, packed::EXP2_100, packed::EXP2_20, (*traits.at(5)).into()); }

    return combined;
}

fn unpack_traits(combined: u128) -> Span<u64> {
    let mut traits: Array<u64> = Default::default();

    let pos0 = unpack_u128(combined, packed::EXP2_0, packed::EXP2_20);
    if pos0 != 0 {
        traits.append(pos0.try_into().unwrap());
    } else {
        return traits.span();
    }

    let pos1 = unpack_u128(combined, packed::EXP2_20, packed::EXP2_20);
    if pos1 != 0 {
        traits.append(pos1.try_into().unwrap());
    } else {
        return traits.span();
    }

    let pos2 = unpack_u128(combined, packed::EXP2_40, packed::EXP2_20);
    if pos2 != 0 {
        traits.append(pos2.try_into().unwrap());
    } else {
        return traits.span();
    }

    let pos3 = unpack_u128(combined, packed::EXP2_60, packed::EXP2_20);
    if pos3 != 0 {
        traits.append(pos3.try_into().unwrap());
    } else {
        return traits.span();
    }

    let pos4 = unpack_u128(combined, packed::EXP2_80, packed::EXP2_20);
    if pos4 != 0 {
        traits.append(pos4.try_into().unwrap());
    } else {
        return traits.span();
    }

    let pos5 = unpack_u128(combined, packed::EXP2_100, packed::EXP2_20);
    if pos5 != 0 {
        traits.append(pos5.try_into().unwrap());
    }

    return traits.span();
}

impl StoreCrewmate of Store<Crewmate> {
    #[inline(always)]
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<Crewmate> {
        return StoreCrewmate::read_at_offset(address_domain, base, 0);
    }

    #[inline(always)]
    fn write(address_domain: u32, base: StorageBaseAddress, value: Crewmate) -> SyscallResult<()> {
        return StoreCrewmate::write_at_offset(
            address_domain, base, 0, value
        );
    }

    #[inline(always)]
    fn read_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8
    ) -> SyscallResult<Crewmate> {
        let features = Store::<felt252>::read_at_offset(address_domain, base, offset)?;
        let (appearance, high) = split_felt252(features);

        let traits = Store::<felt252>::read_at_offset(address_domain, base, offset + 1)?;
        let (impactful, cosmetic) = split_felt252(traits);

        return Result::Ok(Crewmate {
            status: unpack_u128(high, packed::EXP2_0, packed::EXP2_4).try_into().unwrap(),
            collection: unpack_u128(high, packed::EXP2_4, packed::EXP2_8).try_into().unwrap(),
            class: unpack_u128(high, packed::EXP2_12, packed::EXP2_8).try_into().unwrap(),
            title: unpack_u128(high, packed::EXP2_20, packed::EXP2_16).try_into().unwrap(),
            appearance: appearance,
            cosmetic: unpack_traits(cosmetic),
            impactful: unpack_traits(impactful)
        });
    }

    #[inline(always)]
    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: Crewmate
    ) -> SyscallResult<()> {
        let mut high: u128 = 0;
        pack_u128(ref high, packed::EXP2_0, packed::EXP2_4, value.status.into());
        pack_u128(ref high, packed::EXP2_4, packed::EXP2_8, value.collection.into());
        pack_u128(ref high, packed::EXP2_12, packed::EXP2_8, value.class.into());
        pack_u128(ref high, packed::EXP2_20, packed::EXP2_16, value.title.into());
        let features = value.appearance.into() + high.into() * packed::EXP2_128;

        let cosmetic = pack_traits(value.cosmetic);
        let impactful = pack_traits(value.impactful);
        let traits = impactful.into() + cosmetic.into() * packed::EXP2_128;

        Store::<felt252>::write_at_offset(address_domain, base, offset, features);
        return Store::<felt252>::write_at_offset(address_domain, base, offset + 1, traits);
    }

    #[inline(always)]
    fn size() -> u8 {
        return 2;
    }
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use core::starknet::SyscallResultTrait;
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use result::ResultTrait;
    use serde::Serde;
    use starknet::SyscallResult;
    use starknet::storage_access::{Store, StorageBaseAddress, storage_base_address_const};
    use traits::{Into, TryInto};

    use influence::common::{config::entities, packed};
    use influence::components::{ComponentTrait, resolve};
    use influence::types::entity::{Entity, EntityTrait};

    use super::{Crewmate, CrewmateTrait, statuses, StoreCrewmate};

    #[test]
    #[available_gas(500000)]
    fn test_storage() {
        let base = starknet::storage_base_address_from_felt252(42);
        let cosmetic = array![2, 4];
        let impactful = array![6, 8];
        let crewmate_data = Crewmate {
            status: statuses::INITIALIZED,
            collection: 2,
            class: 4,
            title: 5,
            appearance: 10141340203288541999790327595041,
            cosmetic: cosmetic.span(),
            impactful: impactful.span()
        };

        let entity = EntityTrait::new(entities::CREWMATE, 1);
        Store::<Crewmate>::write(0, base, crewmate_data); // 24k gas

        let read_data = Store::<Crewmate>::read(0, base).unwrap(); // 23k
        assert(read_data.status == statuses::INITIALIZED, 'Wrong status');
        assert(read_data.collection == 2, 'Wrong collection');
        assert(read_data.class == 4, 'Wrong class');
        assert(read_data.title == 5, 'Wrong title');
        assert(read_data.appearance == 10141340203288541999790327595041, 'Wrong appearance');
        assert(read_data.cosmetic.len() == 2, 'Wrong cosmetic length');
        assert(read_data.impactful.len() == 2, 'Wrong cosmetic length');
    }

    #[test]
    #[available_gas(500000)]
    fn test_appearance() {
        let packed = CrewmateTrait::pack_appearance(1, 2, 3, 4, 5, 6, 7, 8);
        assert(packed == 10141340203288541999790327595041, 'Wrong appearance');
    }
}
