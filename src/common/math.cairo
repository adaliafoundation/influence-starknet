use integer::{u64_safe_divmod, u64_as_non_zero, u128_safe_divmod, u128_as_non_zero};
use traits::{Into, TryInto};

trait RoundedDivTrait<T> {
    fn div_floor(self: T, other: T) -> T;
    fn div_ceil(self: T, other: T) -> T;
    fn div_round(self: T, other: T) -> T;
}

impl U128RoundedDivImpl of RoundedDivTrait<u128> {
    fn div_ceil(self: u128, other: u128) -> u128 {
        let (div, rem) = u128_safe_divmod(self, u128_as_non_zero(other));
        if rem == 0 { return div; }
        return div + 1;
    }

    fn div_floor(self: u128, other: u128) -> u128 {
        return self / other;
    }

    fn div_round(self: u128, other: u128) -> u128 {
        let (div, rem) = u128_safe_divmod(self, u128_as_non_zero(other));
        if rem * 2 >= other { return div + 1; }
        return div;
    }
}

impl U64RoundedDivImpl of RoundedDivTrait<u64> {
    fn div_ceil(self: u64, other: u64) -> u64 {
        let (div, rem) = u64_safe_divmod(self, u64_as_non_zero(other));
        if rem == 0 { return div; }
        return div + 1;
    }

    fn div_floor(self: u64, other: u64) -> u64 {
        return self / other;
    }

    fn div_round(self: u64, other: u64) -> u64 {
        let (div, rem) = u64_safe_divmod(self, u64_as_non_zero(other));
        if rem * 2 >= other { return div + 1; }
        return div;
    }
}

fn exp2(exp: u64) -> felt252 {
    // Scale into 64-bit range
    if exp > 64 {
        return 18446744073709551616 * exp2(exp - 64);
    }

    if exp <= 16 {
        if exp == 0 { return 1; }
        if exp == 1 { return 2; }
        if exp == 2 { return 4; }
        if exp == 3 { return 8; }
        if exp == 4 { return 16; }
        if exp == 5 { return 32; }
        if exp == 6 { return 64; }
        if exp == 7 { return 128; }
        if exp == 8 { return 256; }
        if exp == 9 { return 512; }
        if exp == 10 { return 1024; }
        if exp == 11 { return 2048; }
        if exp == 12 { return 4096; }
        if exp == 13 { return 8192; }
        if exp == 14 { return 16384; }
        if exp == 15 { return 32768; }
        if exp == 16 { return 65536; }
    } else if exp <= 32 {
        if exp == 17 { return 131072; }
        if exp == 18 { return 262144; }
        if exp == 19 { return 524288; }
        if exp == 20 { return 1048576; }
        if exp == 21 { return 2097152; }
        if exp == 22 { return 4194304; }
        if exp == 23 { return 8388608; }
        if exp == 24 { return 16777216; }
        if exp == 25 { return 33554432; }
        if exp == 26 { return 67108864; }
        if exp == 27 { return 134217728; }
        if exp == 28 { return 268435456; }
        if exp == 29 { return 536870912; }
        if exp == 30 { return 1073741824; }
        if exp == 31 { return 2147483648; }
        if exp == 32 { return 4294967296; }
    } else if exp <= 48 {
        if exp == 33 { return 8589934592; }
        if exp == 34 { return 17179869184; }
        if exp == 35 { return 34359738368; }
        if exp == 36 { return 68719476736; }
        if exp == 37 { return 137438953472; }
        if exp == 38 { return 274877906944; }
        if exp == 39 { return 549755813888; }
        if exp == 40 { return 1099511627776; }
        if exp == 41 { return 2199023255552; }
        if exp == 42 { return 4398046511104; }
        if exp == 43 { return 8796093022208; }
        if exp == 44 { return 17592186044416; }
        if exp == 45 { return 35184372088832; }
        if exp == 46 { return 70368744177664; }
        if exp == 47 { return 140737488355328; }
        if exp == 48 { return 281474976710656; }
    } else {
        if exp == 49 { return 562949953421312; }
        if exp == 50 { return 1125899906842624; }
        if exp == 51 { return 2251799813685248; }
        if exp == 52 { return 4503599627370496; }
        if exp == 53 { return 9007199254740992; }
        if exp == 54 { return 18014398509481984; }
        if exp == 55 { return 36028797018963968; }
        if exp == 56 { return 72057594037927936; }
        if exp == 57 { return 144115188075855872; }
        if exp == 58 { return 288230376151711744; }
        if exp == 59 { return 576460752303423488; }
        if exp == 60 { return 1152921504606846976; }
        if exp == 61 { return 2305843009213693952; }
        if exp == 62 { return 4611686018427387904; }
        if exp == 63 { return 9223372036854775808; }
    }

    return 18446744073709551616;
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use integer::{u64_safe_divmod, u64_as_non_zero, u128_safe_divmod, u128_as_non_zero};
    use traits::{Into, TryInto};
    use super::{RoundedDivTrait, U128RoundedDivImpl, U64RoundedDivImpl};

    #[test]
    #[available_gas(100000)]
    fn test_exp2() {
        assert(super::exp2(7) == 128, 'wrong exp2(7)');
        assert(super::exp2(71) == 2361183241434822606848, 'wrong exp2(71)');
        assert(super::exp2(135) == 43556142965880123323311949751266331066368, 'wrong exp2(135)');
    }

    #[test]
    fn test_div_ceil() {
        assert(17_u128.div_ceil(10) == 2, 'wrong div_ceil');
        assert(0_u128.div_ceil(10) == 0, 'wrong div_ceil');
        assert(10_u128.div_ceil(3) == 4, 'wrong div_ceil');
    }

    #[test]
    fn test_div_floor() {
        assert(17_u128.div_floor(10) == 1, 'wrong div_floor');
        assert(0_u128.div_floor(10) == 0, 'wrong div_floor');
        assert(10_u128.div_floor(3) == 3, 'wrong div_floor');
    }

    #[test]
    fn test_div_round() {
        assert(17_u128.div_round(10) == 2, 'wrong div_round');
        assert(0_u128.div_round(10) == 0, 'wrong div_round');
        assert(10_u128.div_round(3) == 3, 'wrong div_round');
    }
}