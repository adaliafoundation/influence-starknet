const YIELD_1: u64 = 1;
const YIELD_2: u64 = 2;
const YIELD_3: u64 = 3;
const VOLATILE_1: u64 = 4;
const VOLATILE_2: u64 = 5;
const VOLATILE_3: u64 = 6;
const METAL_1: u64 = 7;
const METAL_2: u64 = 8;
const METAL_3: u64 = 9;
const ORGANIC_1: u64 = 10;
const ORGANIC_2: u64 = 11;
const ORGANIC_3: u64 = 12;
const RARE_EARTH: u64 = 13;
const FISSILE: u64 = 14;

struct Config {
    modifier: u64 // in hundredths of a percent
}

fn config(t: u64) -> Config {
    if t == YIELD_1 { return Config { modifier: 300 }; }
    if t == YIELD_2 { return Config { modifier: 600 }; }
    if t == YIELD_3 { return Config { modifier: 1500 }; }
    if t == VOLATILE_1 { return Config { modifier: 1000 }; }
    if t == VOLATILE_2 { return Config { modifier: 2000 }; }
    if t == VOLATILE_3 { return Config { modifier: 5000 }; }
    if t == METAL_1 { return Config { modifier: 1000 }; }
    if t == METAL_2 { return Config { modifier: 2000 }; }
    if t == METAL_3 { return Config { modifier: 5000 }; }
    if t == ORGANIC_1 { return Config { modifier: 1000 }; }
    if t == ORGANIC_2 { return Config { modifier: 2000 }; }
    if t == ORGANIC_3 { return Config { modifier: 5000 }; }
    if t == RARE_EARTH { return Config { modifier: 3000 }; }
    if t == FISSILE { return Config { modifier: 3000 }; }

    assert(false, 'unknown bonus');
    return Config { modifier: 0 };
}
