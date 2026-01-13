#[starknet::contract]
mod ScanResourcesFinish {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use starknet::ContractAddress;
    use traits::{Into, TryInto};

    use cubit::f128::{Fixed, FixedTrait, procgen::rand};

    use influence::components;
    use influence::common::{crew::CrewDetailsTrait, packed, random};
    use influence::config::errors;
    use influence::components::{celestial::{statuses, types, Celestial, CelestialTrait},
        product_type::types as product_types};
    use influence::systems::scanning::resource_commit_hash;
    use influence::types::{Context, Entity, EntityTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct ResourceScanFinished {
        asteroid: Entity,
        abundances: Span<u128>,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        ResourceScanFinished: ResourceScanFinished
    }

    #[external(v0)]
    fn run(ref self: ContractState, asteroid: Entity, caller_crew: Entity, context: Context) {
        // Check that crew is delegated
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_delegated_to(context.caller);

        caller_crew.assert_controls(asteroid);

        let mut celestial_data = components::get::<Celestial>(asteroid.path()).unwrap();
        assert(celestial_data.scan_status == statuses::RESOURCE_SCANNING, 'invalid scan status');
        assert(celestial_data.scan_finish_time < context.now, 'scan not finished');

        // Retrieve random value for commitment
        let seed = random::reveal(resource_commit_hash(asteroid));

        // Get spectral type of asteroid and generate appropriate resource abundances
        let resources = resources(celestial_data.celestial_type);
        let mut abundances: Array<u128> = Default::default();
        let mut total = 0;
        let mut iter = 0;

        loop {
            if iter >= resources.len() { break; }
            let (resource_type, min, max) = *resources.at(iter);

            if max == 0 {
                abundances.append(0);
            } else if max != 0 {
                let abundance = rand::u128_normal_between(rand::derive(seed, resource_type.into()), min, max);
                abundances.append(abundance);
                total += abundance;
            }

            iter += 1;
        };

        // Scale and record resource abundances in scans component
        let mut packed_abundances: felt252 = 0;
        let mut scaled_abundances: Array<u128> = Default::default();
        let mut shift: felt252 = 1;
        iter = 0;

        loop {
            if iter >= abundances.len() { break; }
            if iter == 11 { shift *= 0x40000; } // Shift up 18 bits to high u128 for second half

            let abundance = *abundances.at(iter) * 1000 / total;
            scaled_abundances.append(abundance);
            packed_abundances += shift * abundance.into();

            shift *= 0x400;
            iter += 1;
        };

        celestial_data.abundances = packed_abundances;
        celestial_data.scan_status = statuses::RESOURCE_SCANNED;
        celestial_data.scan_finish_time = 0;
        components::set::<Celestial>(asteroid.path(), celestial_data);
        self.emit(ResourceScanFinished {
            asteroid: asteroid,
            abundances: scaled_abundances.span(),
            caller_crew: caller_crew,
            caller: context.caller
        });
    }

    fn resources(t: u64) -> Span<(u64, u128, u128)> {
        let mut resources: Array<(u64, u128, u128)> = Default::default();

        if t == types::C_TYPE_ASTEROID {
            return array![
                (product_types::WATER, 0, 5000),
                (product_types::HYDROGEN, 0, 0),
                (product_types::AMMONIA, 0, 0),
                (product_types::NITROGEN, 0, 0),
                (product_types::SULFUR_DIOXIDE, 0, 0),
                (product_types::CARBON_DIOXIDE, 0, 909),
                (product_types::CARBON_MONOXIDE, 0, 642),
                (product_types::METHANE, 0, 200),
                (product_types::APATITE, 0, 1465),
                (product_types::BITUMEN, 0, 670),
                (product_types::CALCITE, 0, 1114),
                (product_types::FELDSPAR, 0, 0),
                (product_types::OLIVINE, 0, 0),
                (product_types::PYROXENE, 0, 0),
                (product_types::COFFINITE, 0, 0),
                (product_types::MERRILLITE, 0, 0),
                (product_types::XENOTIME, 0, 0),
                (product_types::RHABDITE, 0, 0),
                (product_types::GRAPHITE, 0, 0),
                (product_types::TAENITE, 0, 0),
                (product_types::TROILITE, 0, 0),
                (product_types::URANINITE, 0, 0)
            ].span();
        }

        if t == types::CM_TYPE_ASTEROID {
            return array![
                (product_types::WATER, 0, 2706),
                (product_types::HYDROGEN, 0, 0),
                (product_types::AMMONIA, 0, 0),
                (product_types::NITROGEN, 0, 0),
                (product_types::SULFUR_DIOXIDE, 0, 0),
                (product_types::CARBON_DIOXIDE, 0, 395),
                (product_types::CARBON_MONOXIDE, 0, 279),
                (product_types::METHANE, 0, 200),
                (product_types::APATITE, 0, 636),
                (product_types::BITUMEN, 0, 291),
                (product_types::CALCITE, 0, 484),
                (product_types::FELDSPAR, 0, 0),
                (product_types::OLIVINE, 0, 0),
                (product_types::PYROXENE, 0, 0),
                (product_types::COFFINITE, 0, 0),
                (product_types::MERRILLITE, 0, 0),
                (product_types::XENOTIME, 0, 0),
                (product_types::RHABDITE, 0, 308),
                (product_types::GRAPHITE, 0, 200),
                (product_types::TAENITE, 0, 3754),
                (product_types::TROILITE, 0, 547),
                (product_types::URANINITE, 0, 200)
            ].span();
        }

        if t == types::CI_TYPE_ASTEROID {
            return array![
                (product_types::WATER, 0, 2722),
                (product_types::HYDROGEN, 0, 2943),
                (product_types::AMMONIA, 0, 331),
                (product_types::NITROGEN, 0, 200),
                (product_types::SULFUR_DIOXIDE, 0, 1501),
                (product_types::CARBON_DIOXIDE, 0, 401),
                (product_types::CARBON_MONOXIDE, 0, 285),
                (product_types::METHANE, 0, 200),
                (product_types::APATITE, 0, 639),
                (product_types::BITUMEN, 0, 292),
                (product_types::CALCITE, 0, 486),
                (product_types::FELDSPAR, 0, 0),
                (product_types::OLIVINE, 0, 0),
                (product_types::PYROXENE, 0, 0),
                (product_types::COFFINITE, 0, 0),
                (product_types::MERRILLITE, 0, 0),
                (product_types::XENOTIME, 0, 0),
                (product_types::RHABDITE, 0, 0),
                (product_types::GRAPHITE, 0, 0),
                (product_types::TAENITE, 0, 0),
                (product_types::TROILITE, 0, 0),
                (product_types::URANINITE, 0, 0)
            ].span();
        }

        if t == types::CS_TYPE_ASTEROID {
            return array![
                (product_types::WATER, 0, 2721),
                (product_types::HYDROGEN, 0, 0),
                (product_types::AMMONIA, 0, 0),
                (product_types::NITROGEN, 0, 0),
                (product_types::SULFUR_DIOXIDE, 0, 0),
                (product_types::CARBON_DIOXIDE, 0, 397),
                (product_types::CARBON_MONOXIDE, 0, 280),
                (product_types::METHANE, 0, 200),
                (product_types::APATITE, 0, 640),
                (product_types::BITUMEN, 0, 292),
                (product_types::CALCITE, 0, 487),
                (product_types::FELDSPAR, 0, 889),
                (product_types::OLIVINE, 0, 902),
                (product_types::PYROXENE, 0, 1568),
                (product_types::COFFINITE, 0, 963),
                (product_types::MERRILLITE, 0, 200),
                (product_types::XENOTIME, 0, 460),
                (product_types::RHABDITE, 0, 0),
                (product_types::GRAPHITE, 0, 0),
                (product_types::TAENITE, 0, 0),
                (product_types::TROILITE, 0, 0),
                (product_types::URANINITE, 0, 0)
            ].span();
        }

        if t == types::CMS_TYPE_ASTEROID {
            return array![
                (product_types::WATER, 0, 1755),
                (product_types::HYDROGEN, 0, 0),
                (product_types::AMMONIA, 0, 0),
                (product_types::NITROGEN, 0, 0),
                (product_types::SULFUR_DIOXIDE, 0, 0),
                (product_types::CARBON_DIOXIDE, 0, 256),
                (product_types::CARBON_MONOXIDE, 0, 200),
                (product_types::METHANE, 0, 200),
                (product_types::APATITE, 0, 413),
                (product_types::BITUMEN, 0, 200),
                (product_types::CALCITE, 0, 314),
                (product_types::FELDSPAR, 0, 574),
                (product_types::OLIVINE, 0, 582),
                (product_types::PYROXENE, 0, 1012),
                (product_types::COFFINITE, 0, 621),
                (product_types::MERRILLITE, 0, 200),
                (product_types::XENOTIME, 0, 297),
                (product_types::RHABDITE, 0, 200),
                (product_types::GRAPHITE, 0, 200),
                (product_types::TAENITE, 0, 2435),
                (product_types::TROILITE, 0, 354),
                (product_types::URANINITE, 0, 200)
            ].span();
        }

        if t == types::CIS_TYPE_ASTEROID {
            return array![
                (product_types::WATER, 0, 1777),
                (product_types::HYDROGEN, 0, 1921),
                (product_types::AMMONIA, 0, 216),
                (product_types::NITROGEN, 0, 200),
                (product_types::SULFUR_DIOXIDE, 0, 980),
                (product_types::CARBON_DIOXIDE, 0, 262),
                (product_types::CARBON_MONOXIDE, 0, 200),
                (product_types::METHANE, 0, 200),
                (product_types::APATITE, 0, 417),
                (product_types::BITUMEN, 0, 200),
                (product_types::CALCITE, 0, 317),
                (product_types::FELDSPAR, 0, 580),
                (product_types::OLIVINE, 0, 588),
                (product_types::PYROXENE, 0, 1022),
                (product_types::COFFINITE, 0, 628),
                (product_types::MERRILLITE, 0, 200),
                (product_types::XENOTIME, 0, 300),
                (product_types::RHABDITE, 0, 0),
                (product_types::GRAPHITE, 0, 0),
                (product_types::TAENITE, 0, 0),
                (product_types::TROILITE, 0, 0),
                (product_types::URANINITE, 0, 0)
            ].span();
        }

        if t == types::S_TYPE_ASTEROID {
            return array![
                (product_types::WATER, 0, 0),
                (product_types::HYDROGEN, 0, 0),
                (product_types::AMMONIA, 0, 0),
                (product_types::NITROGEN, 0, 0),
                (product_types::SULFUR_DIOXIDE, 0, 0),
                (product_types::CARBON_DIOXIDE, 0, 0),
                (product_types::CARBON_MONOXIDE, 0, 0),
                (product_types::METHANE, 0, 0),
                (product_types::APATITE, 0, 0),
                (product_types::BITUMEN, 0, 0),
                (product_types::CALCITE, 0, 0),
                (product_types::FELDSPAR, 0, 1822),
                (product_types::OLIVINE, 0, 1848),
                (product_types::PYROXENE, 0, 3213),
                (product_types::COFFINITE, 0, 1974),
                (product_types::MERRILLITE, 0, 200),
                (product_types::XENOTIME, 0, 942),
                (product_types::RHABDITE, 0, 0),
                (product_types::GRAPHITE, 0, 0),
                (product_types::TAENITE, 0, 0),
                (product_types::TROILITE, 0, 0),
                (product_types::URANINITE, 0, 0)
            ].span();
        }

        if t == types::SM_TYPE_ASTEROID {
            return array![
                (product_types::WATER, 0, 0),
                (product_types::HYDROGEN, 0, 0),
                (product_types::AMMONIA, 0, 0),
                (product_types::NITROGEN, 0, 0),
                (product_types::SULFUR_DIOXIDE, 0, 0),
                (product_types::CARBON_DIOXIDE, 0, 0),
                (product_types::CARBON_MONOXIDE, 0, 0),
                (product_types::METHANE, 0, 0),
                (product_types::APATITE, 0, 0),
                (product_types::BITUMEN, 0, 0),
                (product_types::CALCITE, 0, 0),
                (product_types::FELDSPAR, 0, 888),
                (product_types::OLIVINE, 0, 900),
                (product_types::PYROXENE, 0, 1565),
                (product_types::COFFINITE, 0, 962),
                (product_types::MERRILLITE, 0, 200),
                (product_types::XENOTIME, 0, 459),
                (product_types::RHABDITE, 0, 309),
                (product_types::GRAPHITE, 0, 200),
                (product_types::TAENITE, 0, 3768),
                (product_types::TROILITE, 0, 549),
                (product_types::URANINITE, 0, 200)
            ].span();
        }

        if t == types::SI_TYPE_ASTEROID {
            return array![
                (product_types::WATER, 0, 200),
                (product_types::HYDROGEN, 0, 2711),
                (product_types::AMMONIA, 0, 305),
                (product_types::NITROGEN, 0, 200),
                (product_types::SULFUR_DIOXIDE, 0, 1383),
                (product_types::CARBON_DIOXIDE, 0, 200),
                (product_types::CARBON_MONOXIDE, 0, 200),
                (product_types::METHANE, 0, 200),
                (product_types::APATITE, 0, 0),
                (product_types::BITUMEN, 0, 0),
                (product_types::CALCITE, 0, 0),
                (product_types::FELDSPAR, 0, 818),
                (product_types::OLIVINE, 0, 830),
                (product_types::PYROXENE, 0, 1443),
                (product_types::COFFINITE, 0, 886),
                (product_types::MERRILLITE, 0, 200),
                (product_types::XENOTIME, 0, 423),
                (product_types::RHABDITE, 0, 0),
                (product_types::GRAPHITE, 0, 0),
                (product_types::TAENITE, 0, 0),
                (product_types::TROILITE, 0, 0),
                (product_types::URANINITE, 0, 0)
            ].span();
        }

        if t == types::I_TYPE_ASTEROID {
            return array![
                (product_types::WATER, 0, 200),
                (product_types::HYDROGEN, 0, 5000),
                (product_types::AMMONIA, 0, 723),
                (product_types::NITROGEN, 0, 200),
                (product_types::SULFUR_DIOXIDE, 0, 3277),
                (product_types::CARBON_DIOXIDE, 0, 200),
                (product_types::CARBON_MONOXIDE, 0, 200),
                (product_types::METHANE, 0, 200),
                (product_types::APATITE, 0, 0),
                (product_types::BITUMEN, 0, 0),
                (product_types::CALCITE, 0, 0),
                (product_types::FELDSPAR, 0, 0),
                (product_types::OLIVINE, 0, 0),
                (product_types::PYROXENE, 0, 0),
                (product_types::COFFINITE, 0, 0),
                (product_types::MERRILLITE, 0, 0),
                (product_types::XENOTIME, 0, 0),
                (product_types::RHABDITE, 0, 0),
                (product_types::GRAPHITE, 0, 0),
                (product_types::TAENITE, 0, 0),
                (product_types::TROILITE, 0, 0),
                (product_types::URANINITE, 0, 0),
            ].span();
        }

        if t == types::M_TYPE_ASTEROID {
            return array![
                (product_types::WATER, 0, 0),
                (product_types::HYDROGEN, 0, 0),
                (product_types::AMMONIA, 0, 0),
                (product_types::NITROGEN, 0, 0),
                (product_types::SULFUR_DIOXIDE, 0, 0),
                (product_types::CARBON_DIOXIDE, 0, 0),
                (product_types::CARBON_MONOXIDE, 0, 0),
                (product_types::METHANE, 0, 0),
                (product_types::APATITE, 0, 0),
                (product_types::BITUMEN, 0, 0),
                (product_types::CALCITE, 0, 0),
                (product_types::FELDSPAR, 0, 0),
                (product_types::OLIVINE, 0, 0),
                (product_types::PYROXENE, 0, 0),
                (product_types::COFFINITE, 0, 0),
                (product_types::MERRILLITE, 0, 0),
                (product_types::XENOTIME, 0, 0),
                (product_types::RHABDITE, 0, 1441),
                (product_types::GRAPHITE, 0, 534),
                (product_types::TAENITE, 0, 5000),
                (product_types::TROILITE, 0, 2558),
                (product_types::URANINITE, 0, 467),
            ].span();
        }

        assert(false, 'unknown celestial type');
        return resources.span();
    }
}
