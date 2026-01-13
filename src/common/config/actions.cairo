use array::{ArrayTrait, SpanTrait};

use influence::config::{errors, random_events};

const SAMPLE_DEPOSIT_STARTED: u64 = 1;
const EXTRACT_RESOURCE_STARTED: u64 = 2;
const PROCESS_PRODUCTS_STARTED: u64 = 3;
const ASSEMBLE_SHIP_STARTED: u64 = 4;
const TRANSIT_BETWEEN_STARTED: u64 = 5;

#[derive(Destruct)]
struct Config {
    random_events: Span<u64>
}

fn config(t: u64) -> @Config {
    let mut config = Config { random_events: array![].span() };

    if t == SAMPLE_DEPOSIT_STARTED {
        config.random_events = array![random_events::STARDUST].span();
    } else if t == EXTRACT_RESOURCE_STARTED {
        config.random_events = array![random_events::GROUNDBREAKING].span();
    } else if t == PROCESS_PRODUCTS_STARTED {
        config.random_events = array![
            random_events::KEEP_EM_SEPARATED,
            random_events::NO_SOUND_IN_SPACE,
            random_events::THE_CAKE_IS_A_HALF_TRUTH
        ].span();
    } else if t == ASSEMBLE_SHIP_STARTED {
        config.random_events = array![random_events::FLY_ME_TO_THE_MOON].span();
    } else if t == TRANSIT_BETWEEN_STARTED {
        config.random_events = array![random_events::ALWAYS_LEAVE_A_NOTE].span();
    } else {
        assert(false, errors::ACTION_NOT_FOUND);
    }

    return @config;
}
