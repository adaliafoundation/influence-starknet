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
use influence::types::array::{ArrayHashTrait, SpanHashTrait};
use influence::types::entity::{Entity, EntityTrait, Felt252TryIntoEntity};
use influence::types::inventory_item::{InventoryItem, InventoryItemTrait, InventoryContentsTrait};

// Constants ----------------------------------------------------------------------------------------------------------

mod types {
    const WATER_ELECTROLYSIS: u64 = 23;
    const WATER_VACUUM_EVAPORATION_DESALINATION: u64 = 24;
    const SABATIER_PROCESS: u64 = 25;
    const OLIVINE_ENHANCED_WEATHERING: u64 = 26;
    const BITUMEN_HYDRO_CRACKING: u64 = 27;
    const TAENITE_ELECTROLYTIC_REFINING: u64 = 28;
    const CALCITE_CALCINATION: u64 = 29;
    const HUELS_PROCESS: u64 = 30;
    const AMMONIA_CARBONATION: u64 = 31;
    const SALT_SULFIDIZATION_AND_PHOSPHORIZATION: u64 = 32;
    const BASIC_FOOD_COOKING_AND_PACKAGING: u64 = 33;
    const TROILITE_CENTRIFUGAL_FROTH_FLOTATION: u64 = 34;
    const SILICA_FUSING: u64 = 35;
    const SILICA_PULTRUSION: u64 = 36;
    const COPPER_WIRE_DRAWING: u64 = 37;
    const SALTY_CEMENT_MIXING: u64 = 38;
    const SALT_SELECTIVE_CRYSTALLIZATION: u64 = 39;
    const NAPHTHA_STEAM_CRACKING: u64 = 40;
    const STEEL_ALLOYING: u64 = 41;
    const SILICA_CARBOTHERMIC_REDUCTION: u64 = 42;
    const OSTWALD_PROCESS: u64 = 43;
    const WET_SULFURIC_ACID_PROCESS: u64 = 44;
    const FUNGAL_SOILBUILDING: u64 = 45;
    const IRON_OXIDE_AND_SILICA_CARBOTHERMIC_REDUCTION: u64 = 46;
    const METHANE_STEAM_REFORMING_AND_WATER_GAS_SHIFT: u64 = 47;
    const ACETYLENE_OXALIC_ACID_PRODUCTION: u64 = 48;
    const LEAD_SULFIDE_SMELTING: u64 = 49;
    const TIN_SULFIDE_SMELTING: u64 = 50;
    const IRON_SULFIDE_ROASTING: u64 = 51;
    const HABER_BOSCH_PROCESS: u64 = 52;
    const MOLYBDENUM_DISULFIDE_ROASTING: u64 = 53;
    const SILICA_GAS_ATOMIZATION: u64 = 54;
    const SOLDER_MANUFACTURING: u64 = 55;
    const QUARTZ_FILAMENT_DRAWING_AND_WRAPPING: u64 = 56;
    const STEEL_BEAM_ROLLING: u64 = 57;
    const STEEL_SHEET_ROLLING: u64 = 58;
    const STEEL_PIPE_ROLLING: u64 = 59;
    const STEEL_WIRE_DRAWING: u64 = 60;
    const PROPYLENE_AMMOXIDATION: u64 = 61;
    const PROPYLENE_POLYMERIZATION: u64 = 62;
    const MAGNESIUM_CHLORIDE_MOLTEN_SALT_ELECTROLYSIS: u64 = 63;
    const SOLVAY_PROCESS: u64 = 64;
    const BORIA_HYDRATION: u64 = 65;
    const PYROXENE_ACID_LEACHING_DIGESTION_AND_ION_EXCHANGE: u64 = 66;
    const APATITE_ACID_EXTRACTION: u64 = 67;
    const HYDROGEN_COMBUSTION: u64 = 68;
    const CARBON_MONOXIDE_COMBUSTION: u64 = 69;
    const BORAX_ACID_EXTRACTION: u64 = 70;
    const NITROGEN_CRYOCOOLING_AND_FRACTIONAL_DISTILLATION: u64 = 71;
    const OLIVINE_ACID_LEACHING_AND_CALCINING: u64 = 72;
    const ANORTHITE_FELDSPAR_ACID_LEACHING_AND_CARBONATION: u64 = 73;
    const SODIUM_CHLORALKALI_PROCESS: u64 = 74;
    const POTASSIUM_CHLORALKALI_PROCESS: u64 = 75;
    const APATITE_ACID_RE_EXTRACTION: u64 = 76;
    const AMMONIUM_CARBONATE_OXALATION: u64 = 77;
    const XENOTIME_HOT_ACID_LEACHING: u64 = 78;
    const MERRILLITE_HOT_ACID_LEACHING: u64 = 79;
    const AMMONIA_CATALYTIC_CRACKING: u64 = 80;
    const URANINITE_ACID_LEACHING_SOLVENT_EXTRACTION_AND_PRECIPITATION: u64 = 81;
    const COFFINITE_ACID_LEACHING_SOLVENT_EXTRACTION_AND_PRECIPITATION: u64 = 82;
    const ALUMINA_FORMING_AND_SINTERING: u64 = 83;
    const AUSTENITIC_NICHROME_ALLOYING: u64 = 84;
    const COPPER_WIRE_INSULATING: u64 = 85;
    const SILICON_CZOCHRALSKI_PROCESS_AND_WAFER_SLICING: u64 = 86;
    const STEEL_CABLE_LAYING: u64 = 87;
    const ACRYLONITRILE_POLYMERIZATION: u64 = 88;
    const SOYBEAN_GROWING: u64 = 89;
    const BORIC_ACID_THERMAL_DECOMPOSITION: u64 = 90;
    const LITHIUM_CARBONATE_CHLORINATION: u64 = 91;
    const LITHIUM_SULFATE_CARBONATION: u64 = 92;
    const IRON_OXIDE_DIRECT_REDUCTION: u64 = 93;
    const ZINC_OXIDE_DIRECT_REDUCTION: u64 = 94;
    const NICKEL_OXIDE_DIRECT_REDUCTION: u64 = 95;
    const PIDGEON_PROCESS: u64 = 96;
    const POLYPROPYLENE_CHLORINATION_AND_BASIFICATION: u64 = 97;
    const POTATO_GROWING: u64 = 98;
    const RARE_EARTH_SULFATES_OXALATION_AND_CALCINATION: u64 = 99;
    const AMMONIA_CHLORINATION: u64 = 100;
    const HALL_HEROULT_PROCESS: u64 = 101;
    const CALCIUM_CHLORIDE_MOLTEN_SALT_ELECTROLYSIS: u64 = 102;
    const CEMENT_MIXING: u64 = 103;
    const NATURAL_FLAVORINGS_GROWING: u64 = 104;
    const YELLOWCAKE_DIGESTION_SOLVENT_EXTRACTION_AND_PRECIPITATION: u64 = 105;
    const HYDROFLUORIC_ACID_COLD_ELECTROLYSIS: u64 = 106;
    const RHABDITE_ROASTING_AND_ACID_EXTRACTION: u64 = 107;
    const FERRITE_SINTERING: u64 = 108;
    const DIODE_DOPING_AND_ASSEMBLY: u64 = 109;
    const BALL_VALVE_MACHINING: u64 = 110;
    const ALUMINIUM_BEAM_ROLLING: u64 = 111;
    const ALUMINIUM_SHEET_ROLLING: u64 = 112;
    const ALUMINIUM_PIPE_ROLLING: u64 = 113;
    const POLYACRYLONITRILE_WEAVING: u64 = 114;
    const COLD_GAS_THRUSTER_PRINTING: u64 = 115;
    const POLYACRYLONITRILE_OXIDATION_AND_CARBONIZATION: u64 = 116;
    const ALUMINIUM_SMALL_PROPELLANT_TANK_ASSEMBLY: u64 = 117;
    const BOROSILICATE_GLASSMAKING: u64 = 118;
    const BALL_BEARING_MACHINING_AND_ASSEMBLY: u64 = 119;
    const LARGE_THRUST_BEARING_MACHINING_AND_ASSEMBLY: u64 = 120;
    const BORIA_MAGNESIOTHERMIC_REDUCTION: u64 = 121;
    const LITHIUM_CHLORIDE_MOLTEN_SALT_ELECTROLYSIS: u64 = 122;
    const DIEPOXY_STEP_GROWTH_POLYMERIZATION: u64 = 123;
    const RARE_EARTH_OXIDES_ION_EXCHANGE: u64 = 124;
    const CALCIUM_OXIDE_ALUMINOTHERMIC_REDUCTION: u64 = 125;
    const SODIUM_CHROMATE_ACIDIFICATION_AND_CRYSTALLIZATION: u64 = 126;
    const SULFURIC_ACID_HOT_CATALYTIC_REDUCTION: u64 = 127;
    const MOLYBDENUM_TRIOXIDE_ALUMINOTHERMIC_REDUCTION_AND_ALLOYING: u64 = 128;
    const URANYL_NITRATE_REDOX_AND_PRECIPITATION: u64 = 129;
    const SODIUM_TUNGSTATE_ION_EXCHANGE_PRECIPITATION_AND_CRYSTALLIZATION: u64 = 130;
    const STAINLESS_STEEL_ALLOYING: u64 = 131;
    const BOARD_PRINTING: u64 = 132;
    const FERRITE_BEAD_INDUCTOR_WINDING: u64 = 133;
    const CORE_DRILL_BIT_MILLING: u64 = 134;
    const CORE_DRILL_THRUSTER_ASSEMBLY: u64 = 135;
    const PARABOLIC_DISH_ASSEMBLY: u64 = 136;
    const PHOTOVOLTAIC_PANEL_AMORPHIZATION_AND_ASSEMBLY: u64 = 137;
    const LIPO_BATTERY_ASSEMBLY: u64 = 138;
    const NEODYMIUM_OXIDE_CHLORINATION: u64 = 139;
    const SODIUM_DICHROMATE_HOT_SULFUR_REDUCTION: u64 = 141;
    const PHOTORESIST_EPOXY_STOICHIOMETRY_AND_PACKAGING: u64 = 142;
    const AMMONIUM_DIURANATE_CALCINATION_AND_HYDROGEN_REDUCTION: u64 = 143;
    const AMMONIUM_PARATUNGSTATE_CALCINATION_AND_HYDROGEN_REDUCTION: u64 = 144;
    const ENGINE_BELL_ADDITIVE_MANUFACTURING: u64 = 145;
    const STEEL_TRUSS_CONSTRUCTION: u64 = 146;
    const ALUMINIUM_HULL_PLATE_CONSTRUCTION: u64 = 147;
    const ALUMINIUM_TRUSS_CONSTRUCTION: u64 = 148;
    const CARGO_MODULE_CONSTRUCTION: u64 = 149;
    const ALUMINIUM_PRESSURE_VESSEL_CONSTRUCTION: u64 = 150;
    const ALUMINIUM_PROPELLANT_TANK_CONSTRUCTION: u64 = 151;
    const SHUTTLE_HULL_CONSTRUCTION: u64 = 152;
    const LIGHT_TRANSPORT_HULL_CONSTRUCTION: u64 = 153;
    const CARGO_RING_CONSTRUCTION: u64 = 154;
    const HEAVY_TRANSPORT_HULL_CONSTRUCTION: u64 = 155;
    const TUNGSTEN_GAS_ATOMIZATION: u64 = 156;
    const HYDROGEN_CRYOCOOLING_AND_REACTOR_CONSUMABLES_STOICHIOMETRY: u64 = 157;
    const STAINLESS_STEEL_SHEET_ROLLING: u64 = 158;
    const STAINLESS_STEEL_PIPE_ROLLING: u64 = 159;
    const SILICON_WAFER_CPU_PHOTOLITHOGRAPHY_BALL_BONDING_AND_ENCAPSULATION: u64 = 160;
    const CORE_DRILL_ASSEMBLY: u64 = 161;
    const NEODYMIUM_TRICHLORIDE_VACUUM_CALCIOTHERMIC_REDUCTION: u64 = 162;
    const NEODYMIUM_TRICHLORIDE_MOLTEN_SALT_ELECTROLYSIS: u64 = 163;
    const CHROMIA_ALUMINOTHERMIC_REDUCTION: u64 = 165;
    const URANIUM_DIOXIDE_OXIDATION: u64 = 166;
    const LEACHED_COFFINITE_FROTH_FLOTATION_SOLVENT_EXTRACTION_AND_PRECIPITATION: u64 = 167;
    const ND_YAG_CZOCHRALSKI_PROCESS: u64 = 168;
    const NICHROME_ALLOYING: u64 = 169;
    const MAGNET_SINTERING_AND_MAGNETIZATION: u64 = 170;
    const URANIUM_TETRAFLUORIDE_OXIDATION: u64 = 171;
    const URANIUM_HEXAFLUORIDE_CENTRIFUGE_CASCADE_ENRICHMENT: u64 = 172;
    const ND_YAG_LASER_ASSEMBLY: u64 = 173;
    const THIN_FILM_RESISTOR_SPUTTERING_AND_LASER_TRIMMING: u64 = 174;
    const HEUF6_MAGNESIOTHERMIC_REDUCTION_AND_FINE_DIVISION: u64 = 175;
    const SPIRULINA_AND_CHLORELLA_ALGAE_GROWING: u64 = 176;
    const PEDOT_BACTERIA_CULTURING: u64 = 177;
    const BPA_BACTERIA_CULTURING: u64 = 178;
    const POTASSIUM_HYDROXIDE_CARBONATION: u64 = 179;
    const NOVOLAK_BACTERIA_CULTURING: u64 = 180;
    const FERROCHROMIUM_ALLOYING: u64 = 181;
    const POTASSIUM_CARBONATE_OXIDATION: u64 = 182;
    const RHABDITE_SLAG_ACID_LEACHING: u64 = 183;
    const TANTALATE_NIOBATE_LIQUID_LIQUID_EXTRACTION_AND_REDOX: u64 = 184;
    const CARBON_DIOXIDE_FERROCATALYSIS: u64 = 185;
    const POTASSIUM_HEPTAFLUOROTANTALATE_SODIOTHERMIC_REDUCTION: u64 = 186;
    const RHABDITE_CARBOTHERMIC_REDUCTION: u64 = 187;
    const POLYMER_TANTALUM_CAPACITOR_ASSEMBLY: u64 = 188;
    const SURFACE_MOUNT_DEVICE_REEL_ASSEMBLY: u64 = 189;
    const PICK_AND_PLACE_BOARD_POPULATION: u64 = 190;
    const MOTOR_STATOR_ASSEMBLY: u64 = 191;
    const MOTOR_ROTOR_ASSEMBLY: u64 = 192;
    const BRUSHLESS_MOTOR_ASSEMBLY: u64 = 193;
    const LANDING_LEG_ASSEMBLY: u64 = 194;
    const LANDING_AUGER_ASSEMBLY: u64 = 195;
    const PUMP_ASSEMBLY: u64 = 196;
    const ANTENNA_ASSEMBLY: u64 = 197;
    const FIBER_OPTIC_GYROSCOPE_ASSEMBLY: u64 = 198;
    const STAR_TRACKER_ASSEMBLY: u64 = 199;
    const COMPUTER_ASSEMBLY: u64 = 200;
    const CONTROL_MOMENT_GYROSCOPE_ASSEMBLY: u64 = 201;
    const ROBOTIC_ARM_ASSEMBLY: u64 = 202;
    const FELDSPAR_ALUMINIUM_HYDROXIDE_CALCINATION: u64 = 203;
    const FERROCHROMIUM_ROASTING_AND_HOT_BASE_LEACHING: u64 = 204;
    const BERYLLIUM_CARBONATE_CALCINATION: u64 = 205;
    const BERYLLIA_FORMING_AND_SINTERING: u64 = 206;
    const SILICON_WAFER_CCD_PHOTOLITHOGRAPHY_BALL_BONDING_AND_PACKAGING: u64 = 207;
    const HEAT_EXCHANGER_ASSEMBLY: u64 = 208;
    const TURBOPUMP_ASSEMBLY: u64 = 209;
    const LASER_DIODE_DOPING_AMORPHIZATION_AND_ASSEMBLY: u64 = 210;
    const SEPARATOR_CENTRIFUGE_ASSEMBLY: u64 = 211;
    const FUEL_MAKE_UP_TANK_ASSEMBLY: u64 = 212;
    const NEON_MAKE_UP_TANK_ASSEMBLY: u64 = 213;
    const LIGHTBULB_END_MODERATORS_ASSEMBLY: u64 = 214;
    const COLD_GAS_TORQUE_THRUSTER_PRINTING: u64 = 215;
    const FUSED_QUARTZ_LIGHTBULB_ADDITIVE_SUBTRACTIVE_ASSEMBLY: u64 = 216;
    const REACTOR_PLUMBING_ASSEMBLY_SQUARED: u64 = 217;
    const FLOW_DIVIDER_MODERATOR_ASSEMBLY: u64 = 218;
    const NUCLEAR_LIGHTBULB_ASSEMBLY: u64 = 219;
    const REACTOR_SHELL_ASSEMBLY: u64 = 220;
    const CLOSED_CYCLE_GAS_CORE_NUCLEAR_REACTOR_ENGINE_ASSEMBLY: u64 = 221;
    const HABITATION_MODULE_ASSEMBLY: u64 = 222;
    const MOBILITY_MODULE_ASSEMBLY: u64 = 223;
    const FLUIDS_AUTOMATION_MODULE_ASSEMBLY: u64 = 224;
    const SOLIDS_AUTOMATION_MODULE_ASSEMBLY: u64 = 225;
    const TERRAIN_INTERFACE_MODULE_ASSEMBLY: u64 = 226;
    const AVIONICS_MODULE_ASSEMBLY: u64 = 227;
    const ESCAPE_MODULE_ASSEMBLY: u64 = 228;
    const ATTITUDE_CONTROL_MODULE_ASSEMBLY: u64 = 229;
    const POWER_MODULE_ASSEMBLY: u64 = 230;
    const THERMAL_MODULE_ASSEMBLY: u64 = 231;
    const PROPULSION_MODULE_ASSEMBLY: u64 = 232;
    const SULFUR_DIOXIDE_PLASMA_CATALYSIS: u64 = 233;
    const PARKES_PROCESS: u64 = 234;
    const BICARBONATE_SOLVAY_PROCESS: u64 = 235;
    const SOLVAY_HOU_PROCESS: u64 = 236;
    const BICARBONATE_SOLVAY_HOU_PROCESS: u64 = 237;
    const SODIUM_BICARBONATE_CALCINATION: u64 = 238;
    const EPOXY_STOICHIOMETRY_AND_PACKAGING: u64 = 239;
    const PEDOT_ALGAE_GROWING: u64 = 240;
    const BPA_ALGAE_GROWING: u64 = 241;
    const NOVOLAK_ALGAE_GROWING: u64 = 242;
    const HYDROCHLORIC_REDOX: u64 = 243;
    const HYDROFLUORIC_REDOX: u64 = 244;
    const METHANE_COMBUSTION: u64 = 245;
    const CARBON_MONOXIDE_ARC_DECOMPOSITION: u64 = 246;
    const HYDROGEN_PROPELLANT_UNBUNDLING: u64 = 247;
    const SHUTTLE_INTEGRATION: u64 = 250;
    const LIGHT_TRANSPORT_INTEGRATION: u64 = 251;
    const HEAVY_TRANSPORT_INTEGRATION: u64 = 252;
    const WAREHOUSE_CONSTRUCTION: u64 = 300;
    const EXTRACTOR_CONSTRUCTION: u64 = 301;
    const REFINERY_CONSTRUCTION: u64 = 302;
    const BIOREACTOR_CONSTRUCTION: u64 = 303;
    const FACTORY_CONSTRUCTION: u64 = 304;
    const SHIPYARD_CONSTRUCTION: u64 = 305;
    const SPACEPORT_CONSTRUCTION: u64 = 306;
    const MARKETPLACE_CONSTRUCTION: u64 = 307;
    const HABITAT_CONSTRUCTION: u64 = 308;
    const TANK_FARM_CONSTRUCTION: u64 = 309;
}

// Component ----------------------------------------------------------------------------------------------------------

#[derive(Copy, Drop, Serde)]
struct ProcessType {
    setup_time: u64,
    recipe_time: u64,
    batched: bool,
    processor_type: u64, // the processor type that can execute this process
    inputs: Span<InventoryItem>,
    outputs: Span<InventoryItem>
}

impl ProcessTypeComponent of ComponentTrait<ProcessType> {
    fn name() -> felt252 {
        return 'ProcessType';
    }

    fn is_set(data: ProcessType) -> bool {
        return data.setup_time != 0 || data.recipe_time != 0;
    }

    fn version() -> u64 {
        return 0;
    }
}

trait ProcessTypeTrait {
    fn by_type(id: u64) -> ProcessType;
}

impl ProcessTypeImpl of ProcessTypeTrait {
    fn by_type(id: u64) -> ProcessType {
        let mut path: Array<felt252> = Default::default();
        path.append(id.into());
        return get(path.span()).expect(errors::PROCESS_TYPE_NOT_FOUND);
    }
}

// Storage Access -----------------------------------------------------------------------------------------------------

impl StoreProcessType of Store<ProcessType> {
    #[inline(always)]
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<ProcessType> {
        return StoreProcessType::read_at_offset(address_domain, base, 0);
    }

    #[inline(always)]
    fn write(address_domain: u32, base: StorageBaseAddress, value: ProcessType) -> SyscallResult<()> {
        return StoreProcessType::write_at_offset(address_domain, base, 0, value);
    }

    #[inline(always)]
    fn read_at_offset(address_domain: u32, base: StorageBaseAddress, offset: u8) -> SyscallResult<ProcessType> {
        let low = Store::<u128>::read_at_offset(address_domain, base, offset)?;

        let inputs_len = unpack_u128(low, packed::EXP2_73, packed::EXP2_8).try_into().unwrap();
        let inputs_base = contents_base(base, 'inputs');
        let inputs = InventoryContentsTrait::read_storage(address_domain, inputs_base, offset, inputs_len);

        let outputs_len = unpack_u128(low, packed::EXP2_81, packed::EXP2_8).try_into().unwrap();
        let outputs_base = contents_base(base, 'outputs');
        let outputs = InventoryContentsTrait::read_storage(address_domain, outputs_base, offset, outputs_len);

        return Result::Ok(ProcessType {
            setup_time: unpack_u128(low, packed::EXP2_0, packed::EXP2_36).try_into().unwrap(),
            recipe_time: unpack_u128(low, packed::EXP2_36, packed::EXP2_36).try_into().unwrap(),
            batched: unpack_u128(low, packed::EXP2_72, packed::EXP2_1) == 1,
            processor_type: unpack_u128(low, packed::EXP2_89, packed::EXP2_16).try_into().unwrap(),
            inputs: inputs,
            outputs: outputs
        });
    }

    #[inline(always)]
    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: ProcessType
    ) -> SyscallResult<()> {
        let inputs_base = contents_base(base, 'inputs');
        let inputs_len = value.inputs.write_storage(address_domain, inputs_base, offset);

        let outputs_base = contents_base(base, 'outputs');
        let outputs_len = value.outputs.write_storage(address_domain, outputs_base, offset);

        let mut low: u128 = 0;
        let mut batched: u128 = 0;

        if value.batched {
            batched = 1;
        }

        pack_u128(ref low, packed::EXP2_0, packed::EXP2_36, value.setup_time.into());
        pack_u128(ref low, packed::EXP2_36, packed::EXP2_36, value.recipe_time.into());
        pack_u128(ref low, packed::EXP2_72, packed::EXP2_1, batched);
        pack_u128(ref low, packed::EXP2_89, packed::EXP2_18, value.processor_type.into());
        pack_u128(ref low, packed::EXP2_73, packed::EXP2_8, inputs_len.into());
        pack_u128(ref low, packed::EXP2_81, packed::EXP2_8, outputs_len.into());

        return Store::<u128>::write_at_offset(address_domain, base, offset, low);
    }

    #[inline(always)]
    fn size() -> u8 {
        return 255;
    }
}

fn contents_base(base: StorageBaseAddress, contents_type: felt252) -> StorageBaseAddress {
    let mut contents_base_to_hash: Array<felt252> = Default::default();
    contents_base_to_hash.append(starknet::storage_address_from_base(base).into());
    contents_base_to_hash.append(contents_type);
    return starknet::storage_base_address_from_felt252(contents_base_to_hash.hash());
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

    use influence::components::product_type::types as product_types;
    use influence::types::inventory_item::{InventoryItem, InventoryItemTrait};

    use super::{ProcessType, StoreProcessType};

    #[test]
    #[available_gas(2000000)]
    fn test_storage() {
        let base = starknet::storage_base_address_from_felt252(42);

        let mut inputs: Array<InventoryItem> = Default::default();
        inputs.append(InventoryItemTrait::new(product_types::CARBON_DIOXIDE, 1936));
        inputs.append(InventoryItemTrait::new(product_types::OLIVINE, 4526));

        let mut outputs: Array<InventoryItem> = Default::default();
        outputs.append(InventoryItemTrait::new(product_types::SILICA, 1322));
        outputs.append(InventoryItemTrait::new(product_types::WEATHERED_OLIVINE, 5140));

        let mut to_store = ProcessType {
            setup_time: 1209600,
            recipe_time: 464400,
            batched: true,
            processor_type: 4,
            inputs: inputs.span(),
            outputs: outputs.span()
        };

        StoreProcessType::write(0, base, to_store);
        let mut to_read = StoreProcessType::read(0, base).unwrap();
        assert(to_read.setup_time == 1209600, 'wrong setup time');
        assert(to_read.recipe_time == 464400, 'wrong recipe time');
        assert(to_read.batched, 'not batched');
        assert(to_read.processor_type == 4, 'wrong processor');
        assert(to_read.inputs.len() == 2, 'wrong inputs length');
        assert(to_read.outputs.len() == 2, 'wrong outputs length');

        assert((*to_read.inputs.at(0)).product == product_types::CARBON_DIOXIDE, 'wrong input product');
        assert((*to_read.inputs.at(0)).amount == 1936, 'wrong input quantity');
        assert((*to_read.inputs.at(1)).product == product_types::OLIVINE, 'wrong input product');
        assert((*to_read.inputs.at(1)).amount == 4526, 'wrong input quantity');

        assert((*to_read.outputs.at(0)).product == product_types::SILICA, 'wrong output product');
        assert((*to_read.outputs.at(0)).amount == 1322, 'wrong output quantity');
        assert((*to_read.outputs.at(1)).product == product_types::WEATHERED_OLIVINE, 'wrong output product');
        assert((*to_read.outputs.at(1)).amount == 5140, 'wrong output quantity');
    }
}