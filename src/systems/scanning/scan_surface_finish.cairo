#[starknet::contract]
mod ScanSurfaceFinish {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use starknet::ContractAddress;

    use cubit::f64::{Fixed, FixedTrait, procgen::rand};

    use influence::components;
    use influence::common::{crew::CrewDetailsTrait, random};
    use influence::components::{celestial::{types, statuses, Celestial}};
    use influence::config::{errors, resource_bonuses};
    use influence::systems::scanning::surface_commit_hash;
    use influence::types::{Context, Entity, EntityTrait, String, StringTrait};

    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct SurfaceScanFinished {
        asteroid: Entity,
        bonuses: u64,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        SurfaceScanFinished: SurfaceScanFinished
    }

    #[external(v0)]
    fn run(ref self: ContractState, asteroid: Entity, caller_crew: Entity, context: Context) {
        // Check that crew is delegated
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_delegated_to(context.caller);

        caller_crew.assert_controls(asteroid);

        let mut celestial = components::get::<Celestial>(asteroid.path()).expect(errors::CELESTIAL_NOT_FOUND);
        assert(celestial.scan_status == statuses::SURFACE_SCANNING, 'scan not started');
        assert(celestial.scan_finish_time <= context.now, 'scan not finished');

        // Retrieve random value from commitment
        let seed = random::reveal(surface_commit_hash(asteroid));

        // Generate bonuses and store in scans component
        let mut roll_max: u64 = 10001;

        if (celestial.purchase_order > 0) {
            if (celestial.purchase_order <= 100) {
                roll_max = 3441; // 4x increase
            } else if (celestial.purchase_order <= 1100) {
                roll_max = 4143; // 3x increase
            } else if (celestial.purchase_order <= 11100) {
                roll_max = 5588; // 2x increase
            }
        }

        let categories = categories(celestial.celestial_type);
        let mut bonuses: u64 = 1; // first bit is always set to indicate scanned (legacy from L1)
        let mut iter = 0;

        loop {
            if iter >= categories.len() { break; }
            let category: felt252 = *categories.at(iter);
            let roll = rand::u64_between(rand::derive(seed, category), 0, roll_max);

            if category == 'YIELD' { bonuses += generate_yield(roll); }
            if category == 'VOLATILE' { bonuses += generate_volatile(roll); }
            if category == 'METAL' { bonuses += generate_metal(roll); }
            if category == 'ORGANIC' { bonuses += generate_organic(roll); }
            if category == 'RARE_EARTH' { bonuses += generate_rare_earth(roll); }
            if category == 'FISSILE' { bonuses += generate_fissile(roll); }

            iter += 1;
        };

        // Apply guaranteed bonus for early adopters if none present
        if bonuses == 1 && celestial.purchase_order > 0 && celestial.purchase_order <= 11100 {
            bonuses += 0x2; // YIELD_1
        }

        celestial.bonuses = bonuses;
        celestial.scan_status = statuses::SURFACE_SCANNED;
        celestial.scan_finish_time = 0;

        // Store updated data
        components::set::<Celestial>(asteroid.path(), celestial);
        self.emit(SurfaceScanFinished {
            asteroid: asteroid,
            bonuses: bonuses,
            caller_crew: caller_crew,
            caller: context.caller
        });
    }

    // Generate Yield bonuses
    fn generate_yield(roll: u64) -> u64 {
        if roll > 2100 {
            return 0;
        } else if roll > 600 {
            return 0x2; // YIELD_1
        } else if roll > 100 {
            return 0x4; // YIELD_2
        }

        return 0x8; // YIELD_3
    }

    // Generate Volatile bonuses
    fn generate_volatile(roll: u64) -> u64 {
        if roll > 2100 {
            return 0;
        } else if roll > 600 {
            return 0x10; // VOLATILE_1
        } else if roll > 100 {
            return 0x20; // VOLATILE_2
        }

        return 0x40; // VOLATILE_3
    }

    // Generate Metal bonuses
    fn generate_metal(roll: u64) -> u64 {
        if roll > 2100 {
            return 0;
        } else if roll > 600 {
            return 0x80; // METAL_1
        } else if roll > 100 {
            return 0x100; // METAL_2
        }

        return 0x200; // METAL_3
    }

    // Generate Organic bonuses
    fn generate_organic(roll: u64) -> u64 {
        if roll > 2100 {
            return 0;
        } else if roll > 600 {
            return 0x400; // ORGANIC_1
        } else if roll > 100 {
            return 0x800; // ORGANIC_2
        }

        return 0x1000; // ORGANIC_3
    }

    // Generate Rare Earth bonuses
    fn generate_rare_earth(roll: u64) -> u64 {
        if roll > 250 { return 0; }
        return 0x2000; // RARE_EARTH
    }

    // Generate Fissile bonuses
    fn generate_fissile(roll: u64) -> u64 {
        if roll > 250 { return 0; }
        return 0x4000; // FISSILE
    }

    fn categories(t: u64) -> Span<felt252> {
        let mut categories: Array<felt252> = Default::default();
        categories.append('YIELD');

        if t == types::C_TYPE_ASTEROID {
            categories.append('VOLATILE');
            categories.append('ORGANIC');
            return categories.span();
        }

        if t == types::CM_TYPE_ASTEROID {
            categories.append('VOLATILE');
            categories.append('METAL');
            categories.append('ORGANIC');
            categories.append('FISSILE');
            return categories.span();
        }

        if t == types::CI_TYPE_ASTEROID {
            categories.append('VOLATILE');
            categories.append('ORGANIC');
            return categories.span();
        }

        if t == types::CS_TYPE_ASTEROID {
            categories.append('VOLATILE');
            categories.append('METAL');
            categories.append('ORGANIC');
            categories.append('RARE_EARTH');
            categories.append('FISSILE');
            return categories.span();
        }

        if t == types::CMS_TYPE_ASTEROID {
            categories.append('VOLATILE');
            categories.append('METAL');
            categories.append('ORGANIC');
            categories.append('RARE_EARTH');
            categories.append('FISSILE');
            return categories.span();
        }

        if t == types::CIS_TYPE_ASTEROID {
            categories.append('VOLATILE');
            categories.append('METAL');
            categories.append('ORGANIC');
            categories.append('RARE_EARTH');
            categories.append('FISSILE');
            return categories.span();
        }

        if t == types::S_TYPE_ASTEROID {
            categories.append('METAL');
            categories.append('RARE_EARTH');
            categories.append('FISSILE');
            return categories.span();
        }

        if t == types::SM_TYPE_ASTEROID {
            categories.append('METAL');
            categories.append('RARE_EARTH');
            categories.append('FISSILE');
            return categories.span();
        }

        if t == types::SI_TYPE_ASTEROID {
            categories.append('VOLATILE');
            categories.append('METAL');
            categories.append('RARE_EARTH');
            categories.append('FISSILE');
            return categories.span();
        }

        if t == types::M_TYPE_ASTEROID {
            categories.append('METAL');
            categories.append('FISSILE');
            return categories.span();
        }

        if t == types::I_TYPE_ASTEROID {
            categories.append('VOLATILE');
            return categories.span();
        }


        assert(false, 'unknown celestial type');
        return categories.span();
    }
}
