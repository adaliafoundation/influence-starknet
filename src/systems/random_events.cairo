mod check_for;
mod resolve;

mod always_leave_a_note;
mod fly_me_to_the_moon;
mod greatness;
mod groundbreaking;
mod keep_em_separated;
mod no_sound_in_space;
mod stardust;
mod the_cake_is_a_half_truth;

use always_leave_a_note::AlwaysLeaveANote;
use fly_me_to_the_moon::FlyMeToTheMoon;
use greatness::Greatness;
use groundbreaking::Groundbreaking;
use keep_em_separated::KeepEmSeparated;
use no_sound_in_space::NoSoundInSpace;
use stardust::Stardust;
use the_cake_is_a_half_truth::TheCakeIsAHalfTruth;

mod helpers {
    use option::OptionTrait;
    use traits::Into;

    use cubit::f64::FixedTrait;
    use cubit::f64::procgen::rand::{derive, fixed_between};

    use influence::common::random;
    use influence::common::crew::{CrewDetails, CrewDetailsTrait};
    use influence::config::random_events;

    use super::{AlwaysLeaveANote, FlyMeToTheMoon, Greatness, Groundbreaking,
        KeepEmSeparated, NoSoundInSpace, Stardust, TheCakeIsAHalfTruth};

    fn resolve_event(event: u64, choice: u64, crew_details: CrewDetails) -> bool {
        let rand = random::get_random(crew_details.component.action_strategy, crew_details.component.action_round);
        let seed = derive(rand, event.into());
        let roll = fixed_between(seed, FixedTrait::ZERO(), FixedTrait::ONE());

        if event == random_events::ALWAYS_LEAVE_A_NOTE {
            return AlwaysLeaveANote::resolve(choice, roll, crew_details);
        } else if event == random_events::FLY_ME_TO_THE_MOON {
            return FlyMeToTheMoon::resolve(choice, roll, crew_details);
        } else if event == random_events::GREATNESS {
            return Greatness::resolve(choice, roll, crew_details);
        } else if event == random_events::GROUNDBREAKING {
            return Groundbreaking::resolve(choice, roll, crew_details);
        } else if event == random_events::KEEP_EM_SEPARATED {
            return KeepEmSeparated::resolve(choice, roll, crew_details);
        } else if event == random_events::NO_SOUND_IN_SPACE {
            return NoSoundInSpace::resolve(choice, roll, crew_details);
        } else if event == random_events::STARDUST {
            return Stardust::resolve(choice, roll, crew_details);
        } else if event == random_events::THE_CAKE_IS_A_HALF_TRUTH {
            return TheCakeIsAHalfTruth::resolve(choice, roll, crew_details);
        }

        return false;
    }
}
