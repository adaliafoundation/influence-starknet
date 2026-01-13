use array::SpanTrait;
use debug::PrintTrait;
use hash::LegacyHash;
use integer::{u256_safe_div_rem, u256_as_non_zero};
use option::OptionTrait;
use traits::{Into, TryInto};
use serde::Serde;
use starknet::{Store, StorageBaseAddress, SyscallResult};

#[derive(Copy, Drop)]
struct String {
    value: u256
}

trait StringTrait {
    fn new(value: felt252) -> String;
    fn length(self: @String) -> u8;
    fn is_empty(self: @String) -> bool;
    fn is_valid(self: @String, min: u8, max: u8, alpha: bool, num: bool, sym: bool) -> bool;
    fn to_lower(self: String) -> String;
    fn to_upper(self: String) -> String;
}

impl StringImpl of StringTrait {
    fn new(value: felt252) -> String {
        return String { value: value.into() };
    }

    fn length(self: @String) -> u8 {
        let mut str = *self.value;
        let mut len = 0;

        loop {
            if str == 0 {
                break ();
            }

            len += 1;
            str = str / 256;
        };

        return len;
    }

    fn is_empty(self: @String) -> bool {
        return *self.value == 0;
    }

    fn to_lower(self: String) -> String {
        let mut extract = extract_last_char(self.value);
        let mut str_lower: u256 = 0;
        let mut multi: u256 = 1;

        loop {
            let (str_rem, last_char) = extract;
            let low_char: u256 = last_char.to_lower().into();
            str_lower = low_char * multi + str_lower;

            if str_rem == 0 {
                break ();
            }

            extract = extract_last_char(str_rem);
            multi *= 256;
        };

        return String { value: str_lower };
    }

    fn to_upper(self: String) -> String {
        let mut extract = extract_last_char(self.value);
        let mut str_upper: u256 = 0;
        let mut multi: u256 = 1;

        loop {
            let (str_rem, last_char) = extract;
            let low_char: u256 = last_char.to_upper().into();
            str_upper = low_char * multi + str_upper;

            if str_rem == 0 {
                break ();
            }

            extract = extract_last_char(str_rem);
            multi *= 256;
        };

        return String { value: str_upper };
    }

    fn is_valid(self: @String, min: u8, max: u8, alpha: bool, num: bool, sym: bool) -> bool {
        let SPACE = 32_u8;
        let mut extract = extract_last_char(*self.value);
        let mut prev_char: u8 = 0;
        let mut length = 0;

        let valid = loop {
            let (str_rem, last_char) = extract;

            if (last_char == 0) {
                break (true);
            }

            let char_space = last_char == SPACE;
            if (str_rem == 0) && char_space { break (false); }; // check for leading space
            if (prev_char == 0) && char_space { break (false); }; // check for trailing space
            if (prev_char == SPACE) && char_space { break (false); }; // check for double space

            let char_alpha = last_char.is_alpha();
            let char_num = last_char.is_number();

            if !alpha && char_alpha { break (false); } // check for alpha
            if !num && char_num { break (false); } // check for number
            // NOTE: check for symbols

            if !char_alpha && !char_num && !char_space { break (false); } // check for invalid char

            length += 1;
            prev_char = last_char;
            extract = extract_last_char(str_rem);
        };

        if (length < min) || (length > max) {
            return false;
        } else {
            return valid;
        }
    }
}

impl StringPrint of PrintTrait<String> {
    fn print(self: String) {
        self.value.print();
    }
}

impl StringPartialEq of PartialEq<String> {
    fn eq(lhs: @String, rhs: @String) -> bool {
        return *lhs.value == *rhs.value;
    }

    fn ne(lhs: @String, rhs: @String) -> bool {
        return *lhs.value != *rhs.value;
    }
}

impl StringSerde of Serde<String> {
    fn serialize(self: @String, ref output: Array<felt252>) {
        let to_serialize: felt252 = (*self.value).try_into().unwrap();
        to_serialize.serialize(ref output);
    }

    fn deserialize(ref serialized: Span<felt252>) -> Option<String> {
        return Option::Some(StringTrait::new(*serialized.pop_front()?));
    }
}

trait CharTrait {
    fn is_alpha(self: @u8) -> bool;
    fn is_lower(self: @u8) -> bool;
    fn is_number(self: @u8) -> bool;
    fn is_upper(self: @u8) -> bool;
    fn to_lower(self: u8) -> u8;
    fn to_upper(self: u8) -> u8;
}

impl CharImpl of CharTrait {
    fn is_alpha(self: @u8) -> bool {
        return self.is_upper() || self.is_lower();
    }

    fn is_lower(self: @u8) -> bool {
        return (*self > 96) && (*self < 123);
    }

    fn is_number(self: @u8) -> bool {
        return (*self > 47) && (*self < 58);
    }

    fn is_upper(self: @u8) -> bool {
        return (*self > 64) && (*self < 91);
    }

    fn to_lower(self: u8) -> u8 {
        if self.is_upper() { return self + 32_u8; }
        return self;
    }

    fn to_upper(self: u8) -> u8 {
        if self.is_lower() { return self - 32_u8; }
        return self;
    }
}

fn stringify_u256(mut num: u256) -> u256 {
    let mut str: u256 = 0;
    let mut shift = 1;

    loop {
        if num == 0 { break(); }
        let (div, char) = u256_safe_div_rem(num, u256_as_non_zero(10));
        num = div;
        str += (char + 48) * shift;
        shift *= 256;
    };

    return str;
}

// Returns the remaining string and the last character of the string
fn extract_last_char(value: u256) -> (u256, u8) {
    let (rest, char) = u256_safe_div_rem(value, u256_as_non_zero(256));
    return (rest, char.try_into().unwrap());
}

// Tests --------------------------------------------------------------------------------------------------------------
#[cfg(test)]
mod tests {
    use super::{CharTrait, StringTrait, stringify_u256};

    #[test]
    #[available_gas(750000)]
    fn test_str_new() {
        let str = StringTrait::new('ThisIsAThirtyOneCharacterString');
        let expected: u256 = 'ThisIsAThirtyOneCharacterString';
        assert(str.value == expected, 'Not equal to `Foo`');
        assert(str.length() == 31_u8, 'Not equal to 31')
    }

    #[test]
    #[available_gas(1000000)]
    fn test_string_to_lower() {
        let str = StringTrait::new('Foo');
        let result = str.to_lower();
        assert(result.value == 'foo'_u256, 'Not equal to `foo`');
    }

    #[test]
    #[available_gas(1000000)]
    fn test_string_to_upper() {
        let str = StringTrait::new('Foo');
        let result = str.to_upper();
        assert(result.value == 'FOO'_u256, 'Not equal to `foo`');
    }

    #[test]
    #[available_gas(1000000)]
    fn test_string_validate() {
        let string = StringTrait::new('Foo B3r');

        let mut valid = string.is_valid(3, 10, true, true, true);
        assert(valid == true, 'Should be valid');

        valid = string.is_valid(8, 10, true, true, true);
        assert(valid == false, 'Should be invalid');

        valid = string.is_valid(3, 6, true, true, true);
        assert(valid == false, 'Should be invalid');
    }

    #[test]
    #[available_gas(1000000)]
    fn test_string_validate_numbers() {
        let string = StringTrait::new('Foo3Bar');
        let mut valid = string.is_valid(3, 10, true, false, true);
        assert(valid == false, 'Should be invalid');
    }

    #[test]
    #[available_gas(1000000)]
    fn test_string_validate_trailing_space() {
        let string = StringTrait::new('Foo Bar ');
        let mut valid = string.is_valid(3, 10, true, true, true);
        assert(valid == false, 'Should be invalid');
    }

    #[test]
    #[available_gas(1000000)]
    fn test_string_validate_leading_space() {
        let string = StringTrait::new(' Foo Bar');
        let mut valid = string.is_valid(3, 10, true, true, true);
        assert(valid == false, 'Should be invalid');
    }

    #[test]
    #[available_gas(1000000)]
    fn test_string_validate_double_space() {
        let string = StringTrait::new('Foo  Bar');
        let mut valid = string.is_valid(3, 10, true, true, true);
        assert(valid == false, 'Should be invalid');
    }

    #[test]
    #[available_gas(1000000)]
    fn test_char_to_lower() {
        let result = CharTrait::to_lower('A'_u8);
        assert(result == 'a'_u8, 'Should be a number');
        let result = CharTrait::to_lower('B'_u8);
        assert(result == 'b'_u8, 'Should be a number');
        let result = CharTrait::to_lower('c'_u8);
        assert(result == 'c'_u8, 'Should not be a number');
    }

    #[test]
    #[available_gas(1000000)]
    fn test_char_is_number() {
        let result = CharTrait::is_number(@'0'_u8);
        assert(result == true, 'Should be a number');
        let result = CharTrait::is_number(@'9'_u8);
        assert(result == true, 'Should be a number');
        let result = CharTrait::is_number(@'a'_u8);
        assert(result == false, 'Should not be a number');
    }

    #[test]
    #[available_gas(1000000)]
    fn test_char_is_upper() {
        let result = CharTrait::is_upper(@'A'_u8);
        assert(result == true, 'Should be upper');
        let result = CharTrait::is_upper(@'a'_u8);
        assert(result == false, 'Should not be upper');
    }

    #[test]
    #[available_gas(1000000)]
    fn test_string_is_lower() {
        let result = CharTrait::is_lower(@'a'_u8);
        assert(result == true, 'Should be upper');
        let result = CharTrait::is_lower(@'A'_u8);
        assert(result == false, 'Should not be upper');
    }

    #[test]
    #[available_gas(1000000)]
    fn test_string_is_alpha() {
        let result = CharTrait::is_alpha(@'a'_u8);
        assert(result == true, 'Should be alpha');
        let result = CharTrait::is_alpha(@'A'_u8);
        assert(result == true, 'Should be alpha');
    }

    #[test]
    #[available_gas(2000000)]
    fn test_num_to_string() {
        let result = stringify_u256(123);
        assert(result == '123'_u256, 'should be 123');
    }
}