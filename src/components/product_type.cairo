use array::{ArrayTrait, SpanTrait};
use core::starknet::SyscallResultTrait;
use option::OptionTrait;
use result::ResultTrait;
use starknet::SyscallResult;
use starknet::storage_access::{Store, StorageBaseAddress, storage_base_address_const};
use traits::{Into, TryInto};

use influence::common::{packed, packed::{pack_u128, unpack_u128}};
use influence::components::{ComponentTrait, get};
use influence::config::errors;
use influence::types::entity::{Entity, EntityTrait, Felt252TryIntoEntity};

// Constants ----------------------------------------------------------------------------------------------------------

mod types {
    const WATER: u64 = 1;
    const HYDROGEN: u64 = 2;
    const AMMONIA: u64 = 3;
    const NITROGEN: u64 = 4;
    const SULFUR_DIOXIDE: u64 = 5;
    const CARBON_DIOXIDE: u64 = 6;
    const CARBON_MONOXIDE: u64 = 7;
    const METHANE: u64 = 8;
    const APATITE: u64 = 9;
    const BITUMEN: u64 = 10;
    const CALCITE: u64 = 11;
    const FELDSPAR: u64 = 12;
    const OLIVINE: u64 = 13;
    const PYROXENE: u64 = 14;
    const COFFINITE: u64 = 15;
    const MERRILLITE: u64 = 16;
    const XENOTIME: u64 = 17;
    const RHABDITE: u64 = 18;
    const GRAPHITE: u64 = 19;
    const TAENITE: u64 = 20;
    const TROILITE: u64 = 21;
    const URANINITE: u64 = 22;
    const OXYGEN: u64 = 23;
    const DEIONIZED_WATER: u64 = 24;
    const RAW_SALTS: u64 = 25;
    const SILICA: u64 = 26;
    const NAPHTHA: u64 = 27;
    const SODIUM_BICARBONATE: u64 = 28;
    const IRON: u64 = 29;
    const COPPER: u64 = 30;
    const NICKEL: u64 = 31;
    const QUICKLIME: u64 = 32;
    const ACETYLENE: u64 = 33;
    const AMMONIUM_CARBONATE: u64 = 34;
    const TRIPLE_SUPERPHOSPHATE: u64 = 35;
    const PHOSPHATE_AND_SULFATE_SALTS: u64 = 36;
    const IRON_SULFIDE: u64 = 37;
    const LEAD_SULFIDE: u64 = 38;
    const TIN_SULFIDE: u64 = 39;
    const MOLYBDENUM_DISULFIDE: u64 = 40;
    const FUSED_QUARTZ: u64 = 41;
    const FIBERGLASS: u64 = 42;
    const BARE_COPPER_WIRE: u64 = 43;
    const CEMENT: u64 = 44;
    const SODIUM_CHLORIDE: u64 = 45;
    const POTASSIUM_CHLORIDE: u64 = 46;
    const BORAX: u64 = 47;
    const LITHIUM_CARBONATE: u64 = 48;
    const MAGNESIUM_CHLORIDE: u64 = 49;
    const PROPYLENE: u64 = 50;
    const SULFUR: u64 = 51;
    const STEEL: u64 = 52;
    const SILICON: u64 = 53;
    const NITRIC_ACID: u64 = 54;
    const SULFURIC_ACID: u64 = 55;
    const SOIL: u64 = 56;
    const FERROSILICON: u64 = 57;
    const WEATHERED_OLIVINE: u64 = 58;
    const OXALIC_ACID: u64 = 59;
    const SILVER: u64 = 60;
    const GOLD: u64 = 61;
    const TIN: u64 = 62;
    const IRON_OXIDE: u64 = 63;
    const SPIRULINA_AND_CHLORELLA_ALGAE: u64 = 64;
    const MOLYBDENUM_TRIOXIDE: u64 = 65;
    const SILICA_POWDER: u64 = 66;
    const SOLDER: u64 = 67;
    const FIBER_OPTIC_CABLE: u64 = 68;
    const STEEL_BEAM: u64 = 69;
    const STEEL_SHEET: u64 = 70;
    const STEEL_PIPE: u64 = 71;
    const STEEL_WIRE: u64 = 72;
    const ACRYLONITRILE: u64 = 73;
    const POLYPROPYLENE: u64 = 74;
    const MAGNESIUM: u64 = 75;
    const CHLORINE: u64 = 76;
    const SODIUM_CARBONATE: u64 = 77;
    const CALCIUM_CHLORIDE: u64 = 78;
    const BORIA: u64 = 79;
    const LITHIUM_SULFATE: u64 = 80;
    const HYDROCHLORIC_ACID: u64 = 81;
    const HYDROFLUORIC_ACID: u64 = 82;
    const PHOSPHORIC_ACID: u64 = 83;
    const BORIC_ACID: u64 = 84;
    const ZINC_OXIDE: u64 = 85;
    const NICKEL_OXIDE: u64 = 86;
    const MAGNESIA: u64 = 87;
    const ALUMINA: u64 = 88;
    const SODIUM_HYDROXIDE: u64 = 89;
    const POTASSIUM_HYDROXIDE: u64 = 90;
    const SOYBEANS: u64 = 91;
    const POTATOES: u64 = 92;
    const AMMONIUM_OXALATE: u64 = 93;
    const RARE_EARTH_SULFATES: u64 = 94;
    const FERROCHROMIUM: u64 = 95;
    const YELLOWCAKE: u64 = 96;
    const ALUMINA_CERAMIC: u64 = 97;
    const AUSTENITIC_NICHROME: u64 = 98;
    const COPPER_WIRE: u64 = 99;
    const SILICON_WAFER: u64 = 100;
    const STEEL_CABLE: u64 = 101;
    const POLYACRYLONITRILE: u64 = 102;
    const NATURAL_FLAVORINGS: u64 = 103;
    const PLATINUM: u64 = 104;
    const LITHIUM_CHLORIDE: u64 = 105;
    const ZINC: u64 = 106;
    const EPICHLOROHYDRIN: u64 = 107;
    const BISPHENOL_A: u64 = 108;
    const RARE_EARTH_OXIDES: u64 = 109;
    const AMMONIUM_CHLORIDE: u64 = 110;
    const ALUMINIUM: u64 = 111;
    const CALCIUM: u64 = 112;
    const SODIUM_CHROMATE: u64 = 113;
    const LEACHED_COFFINITE: u64 = 114;
    const URANYL_NITRATE: u64 = 115;
    const FLUORINE: u64 = 116;
    const SODIUM_TUNGSTATE: u64 = 117;
    const FERRITE: u64 = 118;
    const DIODE: u64 = 119;
    const LASER_DIODE: u64 = 120;
    const BALL_VALVE: u64 = 121;
    const ALUMINIUM_BEAM: u64 = 122;
    const ALUMINIUM_SHEET: u64 = 123;
    const ALUMINIUM_PIPE: u64 = 124;
    const POLYACRYLONITRILE_FABRIC: u64 = 125;
    const COLD_GAS_THRUSTER: u64 = 126;
    const COLD_GAS_TORQUE_THRUSTER: u64 = 127;
    const CARBON_FIBER: u64 = 128;
    const FOOD: u64 = 129;
    const SMALL_PROPELLANT_TANK: u64 = 130;
    const BOROSILICATE_GLASS: u64 = 131;
    const BALL_BEARING: u64 = 132;
    const LARGE_THRUST_BEARING: u64 = 133;
    const BORON: u64 = 134;
    const LITHIUM: u64 = 135;
    const EPOXY: u64 = 136;
    const NEODYMIUM_OXIDE: u64 = 137;
    const YTTRIA: u64 = 138;
    const SODIUM_DICHROMATE: u64 = 139;
    const NOVOLAK_PREPOLYMER_RESIN: u64 = 140;
    const FERROMOLYBDENUM: u64 = 141;
    const AMMONIUM_DIURANATE: u64 = 142;
    const AMMONIUM_PARATUNGSTATE: u64 = 143;
    const ENGINE_BELL: u64 = 144;
    const STEEL_TRUSS: u64 = 145;
    const ALUMINIUM_HULL_PLATE: u64 = 146;
    const ALUMINIUM_TRUSS: u64 = 147;
    const CARGO_MODULE: u64 = 148;
    const PRESSURE_VESSEL: u64 = 149;
    const PROPELLANT_TANK: u64 = 150;
    const STAINLESS_STEEL: u64 = 151;
    const BARE_CIRCUIT_BOARD: u64 = 152;
    const FERRITE_BEAD_INDUCTOR: u64 = 153;
    const CORE_DRILL_BIT: u64 = 154;
    const CORE_DRILL_THRUSTER: u64 = 155;
    const PARABOLIC_DISH: u64 = 156;
    const PHOTOVOLTAIC_PANEL: u64 = 157;
    const LIPO_BATTERY: u64 = 158;
    const NEODYMIUM_TRICHLORIDE: u64 = 159;
    const CHROMIA: u64 = 161;
    const PHOTORESIST_EPOXY: u64 = 162;
    const URANIUM_DIOXIDE: u64 = 163;
    const TUNGSTEN: u64 = 164;
    const SHUTTLE_HULL: u64 = 165;
    const LIGHT_TRANSPORT_HULL: u64 = 166;
    const CARGO_RING: u64 = 167;
    const HEAVY_TRANSPORT_HULL: u64 = 168;
    const TUNGSTEN_POWDER: u64 = 169;
    const HYDROGEN_PROPELLANT: u64 = 170;
    const STAINLESS_STEEL_SHEET: u64 = 171;
    const STAINLESS_STEEL_PIPE: u64 = 172;
    const CCD: u64 = 173;
    const COMPUTER_CHIP: u64 = 174;
    const CORE_DRILL: u64 = 175;
    const NEODYMIUM: u64 = 176;
    const CHROMIUM: u64 = 178;
    const URANIUM_TETRAFLUORIDE: u64 = 179;
    const PURE_NITROGEN: u64 = 180;
    const ND_YAG_LASER_ROD: u64 = 181;
    const NICHROME: u64 = 182;
    const NEODYMIUM_MAGNET: u64 = 183;
    const UNENRICHED_URANIUM_HEXAFLUORIDE: u64 = 184;
    const HIGHLY_ENRICHED_URANIUM_HEXAFLUORIDE: u64 = 185;
    const ND_YAG_LASER: u64 = 186;
    const THIN_FILM_RESISTOR: u64 = 187;
    const HIGHLY_ENRICHED_URANIUM_POWDER: u64 = 188;
    const LEACHED_FELDSPAR: u64 = 189;
    const ROASTED_RHABDITE: u64 = 190;
    const RHABDITE_SLAG: u64 = 191;
    const POTASSIUM_CARBONATE: u64 = 192;
    const HYDROGEN_HEPTAFLUOROTANTALATE_AND_NIOBATE: u64 = 193;
    const LEAD: u64 = 194;
    const POTASSIUM_FLUORIDE: u64 = 195;
    const POTASSIUM_HEPTAFLUOROTANTALATE: u64 = 196;
    const DIEPOXY_PREPOLYMER_RESIN: u64 = 197;
    const TANTALUM: u64 = 199;
    const PEDOT: u64 = 200;
    const POLYMER_TANTALUM_CAPACITOR: u64 = 201;
    const SURFACE_MOUNT_DEVICE_REEL: u64 = 202;
    const CIRCUIT_BOARD: u64 = 203;
    const BRUSHLESS_MOTOR_STATOR: u64 = 204;
    const BRUSHLESS_MOTOR_ROTOR: u64 = 205;
    const BRUSHLESS_MOTOR: u64 = 206;
    const LANDING_LEG: u64 = 207;
    const LANDING_AUGER: u64 = 208;
    const PUMP: u64 = 209;
    const RADIO_ANTENNA: u64 = 210;
    const FIBER_OPTIC_GYROSCOPE: u64 = 211;
    const STAR_TRACKER: u64 = 212;
    const COMPUTER: u64 = 213;
    const CONTROL_MOMENT_GYROSCOPE: u64 = 214;
    const ROBOTIC_ARM: u64 = 215;
    const BERYLLIUM_CARBONATE: u64 = 217;
    const BERYLLIA: u64 = 218;
    const BERYLLIA_CERAMIC: u64 = 219;
    const NEON: u64 = 220;
    const HEAT_EXCHANGER: u64 = 221;
    const TURBOPUMP: u64 = 222;
    const NEON_FUEL_SEPARATOR_CENTRIFUGE: u64 = 224;
    const FUEL_MAKE_UP_TANK: u64 = 225;
    const NEON_MAKE_UP_TANK: u64 = 226;
    const LIGHTBULB_END_MODERATORS: u64 = 227;
    const FUSED_QUARTZ_LIGHTBULB_TUBE: u64 = 229;
    const REACTOR_PLUMBING_ASSEMBLY: u64 = 230;
    const FLOW_DIVIDER_MODERATOR: u64 = 231;
    const NUCLEAR_LIGHTBULB: u64 = 232;
    const COMPOSITE_OVERWRAPPED_REACTOR_SHELL: u64 = 233;
    const CLOSED_CYCLE_GAS_CORE_NUCLEAR_REACTOR_ENGINE: u64 = 234;
    const HABITATION_MODULE: u64 = 235;
    const MOBILITY_MODULE: u64 = 236;
    const FLUIDS_AUTOMATION_MODULE: u64 = 237;
    const SOLIDS_AUTOMATION_MODULE: u64 = 238;
    const TERRAIN_INTERFACE_MODULE: u64 = 239;
    const AVIONICS_MODULE: u64 = 240;
    const ESCAPE_MODULE: u64 = 241;
    const ATTITUDE_CONTROL_MODULE: u64 = 242;
    const POWER_MODULE: u64 = 243;
    const THERMAL_MODULE: u64 = 244;
    const PROPULSION_MODULE: u64 = 245;
}

// Component ----------------------------------------------------------------------------------------------------------

#[derive(Copy, Drop, Serde)]
struct ProductType {
    mass: u64, // in g
    volume: u64 // in cm^3
}

impl ProductTypeComponent of ComponentTrait<ProductType> {
    fn name() -> felt252 {
        return 'ProductType';
    }

    fn is_set(data: ProductType) -> bool {
        return data.mass != 0 || data.volume != 0;
    }

    fn version() -> u64 {
        return 0;
    }
}

trait ProductTypeTrait {
    fn by_type(id: u64) -> ProductType;
}

impl ProductTypeImpl of ProductTypeTrait {
    fn by_type(id: u64) -> ProductType {
        let mut path: Array<felt252> = Default::default();
        path.append(id.into());
        return get(path.span()).expect(errors::PRODUCT_TYPE_NOT_FOUND);
    }
}

// Storage Access -----------------------------------------------------------------------------------------------------

impl StoreProductType of Store<ProductType> {
    #[inline(always)]
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<ProductType> {
        return StoreProductType::read_at_offset(address_domain, base, 0);
    }

    #[inline(always)]
    fn write(address_domain: u32, base: StorageBaseAddress, value: ProductType) -> SyscallResult<()> {
        return StoreProductType::write_at_offset(address_domain, base, 0, value);
    }

    #[inline(always)]
    fn read_at_offset(address_domain: u32, base: StorageBaseAddress, offset: u8) -> SyscallResult<ProductType> {
        let low = Store::<u128>::read_at_offset(address_domain, base, offset)?;

        return Result::Ok(ProductType {
            mass: unpack_u128(low, packed::EXP2_0, packed::EXP2_50).try_into().unwrap(),
            volume: unpack_u128(low, packed::EXP2_50, packed::EXP2_50).try_into().unwrap()
        });
    }

    #[inline(always)]
    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: ProductType
    ) -> SyscallResult<()> {
        let mut low: u128 = 0;

        pack_u128(ref low, packed::EXP2_0, packed::EXP2_50, value.mass.into());
        pack_u128(ref low, packed::EXP2_50, packed::EXP2_50, value.volume.into());

        return Store::<u128>::write_at_offset(address_domain, base, offset, low);
    }

    #[inline(always)]
    fn size() -> u8 {
        return 1;
    }
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use array::{ArrayTrait, SpanTrait};
    use core::starknet::SyscallResultTrait;
    use option::OptionTrait;
    use result::ResultTrait;
    use starknet::SyscallResult;
    use starknet::storage_access::{Store, StorageBaseAddress, storage_base_address_const};
    use traits::{Into, TryInto};

    use super::{ProductType, StoreProductType};

    #[test]
    #[available_gas(500000)]
    fn test_storage() {
        let base = starknet::storage_base_address_from_felt252(42);
        let mut to_store = ProductType { mass: 1234, volume: 2345 };

        StoreProductType::write(0, base, to_store);
        let mut to_read = StoreProductType::read(0, base).unwrap();
        assert(to_read.mass == 1234, 'wrong mass');
        assert(to_read.volume == 2345, 'wrong volume');

        to_store.mass = 3456;
        to_store.volume = 4567;
        StoreProductType::write(0, base, to_store);
        to_read = StoreProductType::read(0, base).unwrap();
        assert(to_read.mass == 3456, 'wrong mass');
        assert(to_read.volume == 4567, 'wrong volume');
    }
}