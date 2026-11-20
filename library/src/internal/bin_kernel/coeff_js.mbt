///|
#external
pub type Coeff

///|
pub impl Debug for Coeff with fn to_repr(self) {
  @debug.Repr::integer(self.to_string())
}

///|
#external
priv type CoeffOutcome

///|
extern "js" fn CoeffOutcome::is_ok(self : CoeffOutcome) -> Bool =
  #|(value) => typeof value === "bigint"

///|
fn CoeffOutcome::as_coeff(self : CoeffOutcome) -> Coeff = "%identity"

///|
fn CoeffOutcome::as_error(self : CoeffOutcome) -> String = "%identity"

///|
#external
priv type CoeffDivOutcome

///|
extern "js" fn CoeffDivOutcome::is_ok(self : CoeffDivOutcome) -> Bool =
  #|(value) => typeof value !== "string"

///|
extern "js" fn CoeffDivOutcome::quotient(self : CoeffDivOutcome) -> Coeff =
  #|(value) => value[0]

///|
extern "js" fn CoeffDivOutcome::remainder(self : CoeffDivOutcome) -> Coeff =
  #|(value) => value[1]

///|
fn CoeffDivOutcome::as_error(self : CoeffDivOutcome) -> String = "%identity"

///|
#external
priv type CoeffSqrtOutcome

///|
extern "js" fn CoeffSqrtOutcome::root(self : CoeffSqrtOutcome) -> Coeff =
  #|(value) => value[0]

///|
extern "js" fn CoeffSqrtOutcome::remainder(self : CoeffSqrtOutcome) -> Coeff =
  #|(value) => value[1]

///|
extern "js" fn bin_coeff_sqrt_rem_js(value : Coeff) -> CoeffSqrtOutcome =
  #|(value) => {
  #|  if (value < 2n) return [value, 0n];
  #|  const hex = value.toString(16);
  #|  const code = hex.charCodeAt(0);
  #|  const top = code <= 57 ? code - 48 : code - 87;
  #|  const topBits = top >= 8 ? 4 : top >= 4 ? 3 : top >= 2 ? 2 : 1;
  #|  const bitLength = (hex.length - 1) * 4 + topBits;
  #|  let root = 1n << BigInt((bitLength + 1) >> 1);
  #|  let next = (root + value / root) >> 1n;
  #|  while (next < root) {
  #|    root = next;
  #|    next = (root + value / root) >> 1n;
  #|  }
  #|  return [root, value - root * root];
  #|}

///|
pub fn bin_coeff_sqrt_rem_kernel(value : Coeff) -> (Coeff, Coeff) {
  let outcome = bin_coeff_sqrt_rem_js(value)
  (outcome.root(), outcome.remainder())
}

///|
pub extern "js" fn Coeff::zero() -> Coeff =
  #|() => 0n

///|
pub extern "js" fn Coeff::one() -> Coeff =
  #|() => 1n

///|
pub fn Coeff::from_uint64(value : UInt64) -> Coeff = "%identity"

///|
pub extern "js" fn Coeff::is_zero(self : Coeff) -> Bool =
  #|(value) => value === 0n

///|
pub extern "js" fn Coeff::is_odd(self : Coeff) -> Bool =
  #|(value) => (value & 1n) !== 0n

///|
pub extern "js" fn Coeff::bit_length(self : Coeff) -> Int32 =
  #|(value) => {
  #|  if (value === 0n) return 0;
  #|  const hex = value.toString(16);
  #|  const code = hex.charCodeAt(0);
  #|  const top = code <= 57 ? code - 48 : code - 87;
  #|  const topBits = top >= 8 ? 4 : top >= 4 ? 3 : top >= 2 ? 2 : 1;
  #|  return (hex.length - 1) * 4 + topBits;
  #|}

///|
pub extern "js" fn Coeff::ctz(self : Coeff) -> Int32 =
  #|(value) => {
  #|  if (value === 0n) return 0;
  #|  let count = 0;
  #|  while ((value & 0xffffffffn) === 0n) {
  #|    value >>= 32n;
  #|    count += 32;
  #|  }
  #|  const low = Number(value & 0xffffffffn);
  #|  return count + 31 - Math.clz32(low & -low);
  #|}

///|
extern "js" fn bin_coeff_fits_uint64(value : Coeff) -> Bool =
  #|(value) => value <= 0xffffffffffffffffn

///|
fn bin_coeff_as_uint64(value : Coeff) -> UInt64 = "%identity"

///|
pub fn Coeff::to_uint64(self : Coeff) -> UInt64? {
  if bin_coeff_fits_uint64(self) {
    Some(bin_coeff_as_uint64(self))
  } else {
    None
  }
}

///|
pub extern "js" fn Coeff::test_bit(self : Coeff, index : Int32) -> Bool =
  #|(value, index) => index >= 0 && ((value >> BigInt(index)) & 1n) !== 0n

///|
pub extern "js" fn Coeff::compare(self : Coeff, other : Coeff) -> Int32 =
  #|(left, right) => left < right ? -1 : left > right ? 1 : 0

///|
extern "js" fn bin_coeff_equal(left : Coeff, right : Coeff) -> Bool =
  #|(left, right) => left === right

///|
pub extern "js" fn Coeff::add(self : Coeff, other : Coeff) -> Coeff =
  #|(left, right) => left + right

///|
pub fn bin_coeff_add_normalized_odd(
  left : Coeff,
  right : Coeff,
) -> (Coeff, Int32) {
  let sum = left.add(right)
  let normalization_shift = sum.ctz()
  (sum.shift_right(normalization_shift), normalization_shift)
}

///|
extern "js" fn bin_coeff_sub_checked(
  left : Coeff,
  right : Coeff,
) -> CoeffOutcome =
  #|(left, right) => left < right
  #|  ? "Coeff subtraction would be negative"
  #|  : left - right

///|
pub fn Coeff::sub_checked(self : Coeff, other : Coeff) -> Result[Coeff, String] {
  let outcome = bin_coeff_sub_checked(self, other)
  if outcome.is_ok() {
    Ok(outcome.as_coeff())
  } else {
    Err(outcome.as_error())
  }
}

///|
pub fn bin_coeff_sub_normalized_odd(
  left : Coeff,
  right : Coeff,
) -> (Coeff, Int32) {
  let difference = left.sub_checked(right).unwrap()
  let normalization_shift = difference.ctz()
  (difference.shift_right(normalization_shift), normalization_shift)
}

///|
pub extern "js" fn Coeff::mul(self : Coeff, other : Coeff) -> Coeff =
  #|(left, right) => left * right

///|
pub extern "js" fn Coeff::square(self : Coeff) -> Coeff =
  #|(value) => value * value

///|
extern "js" fn bin_coeff_div_rem_checked(
  numerator : Coeff,
  denominator : Coeff,
) -> CoeffDivOutcome =
  #|(numerator, denominator) => {
  #|  if (denominator === 0n) return "Coeff division by zero";
  #|  if (numerator < denominator) return [0n, numerator];
  #|  const once = numerator - denominator;
  #|  if (once < denominator) return [1n, once];
  #|  const quotient = numerator / denominator;
  #|  return [quotient, numerator - quotient * denominator];
  #|}

///|
pub fn Coeff::div_rem_checked(
  self : Coeff,
  denominator : Coeff,
) -> Result[(Coeff, Coeff), String] {
  let outcome = bin_coeff_div_rem_checked(self, denominator)
  if outcome.is_ok() {
    Ok((outcome.quotient(), outcome.remainder()))
  } else {
    Err(outcome.as_error())
  }
}

///|
pub fn bin_coeff_short_div_rem(
  numerator : Coeff,
  denominator : Coeff,
) -> (Coeff, Coeff) {
  let outcome = bin_coeff_div_rem_checked(numerator, denominator)
  (outcome.quotient(), outcome.remainder())
}

///|
pub extern "js" fn Coeff::gcd(self : Coeff, other : Coeff) -> Coeff =
  #|(left, right) => {
  #|  while (right !== 0n) {
  #|    const remainder = left % right;
  #|    left = right;
  #|    right = remainder;
  #|  }
  #|  return left;
  #|}

///|
pub extern "js" fn Coeff::pow_nat(self : Coeff, exponent : UInt32) -> Coeff =
  #|(value, exponent) => value ** BigInt(exponent >>> 0)

///|
extern "js" fn bin_coeff_shift_left(value : Coeff, shift : Int32) -> Coeff =
  #|(value, shift) => value << BigInt(shift)

///|
pub fn Coeff::shift_left(self : Coeff, shift : Int32) -> Coeff {
  if shift < 0 {
    abort("Coeff shift count must be non-negative")
  }
  bin_coeff_shift_left(self, shift)
}

///|
pub fn Coeff::add_shifted_left(
  self : Coeff,
  shift : Int32,
  other : Coeff,
) -> Coeff {
  self.shift_left(shift).add(other)
}

///|
extern "js" fn bin_coeff_shift_right(value : Coeff, shift : Int32) -> Coeff =
  #|(value, shift) => value >> BigInt(shift)

///|
pub fn Coeff::shift_right(self : Coeff, shift : Int32) -> Coeff {
  if shift < 0 {
    abort("Coeff shift count must be non-negative")
  }
  bin_coeff_shift_right(self, shift)
}

///|
pub extern "js" fn Coeff::bit_and(self : Coeff, other : Coeff) -> Coeff =
  #|(left, right) => left & right

///|
pub extern "js" fn Coeff::bit_or(self : Coeff, other : Coeff) -> Coeff =
  #|(left, right) => left | right

///|
pub extern "js" fn Coeff::bit_xor(self : Coeff, other : Coeff) -> Coeff =
  #|(left, right) => left ^ right

///|
extern "js" fn bin_coeff_parse(source : String, radix : Int32) -> CoeffOutcome =
  #|(() => {
  #|  const digitValues = new Int8Array(128);
  #|  digitValues.fill(-1);
  #|  for (let digit = 0; digit < 10; digit++) {
  #|    digitValues[48 + digit] = digit;
  #|  }
  #|  for (let digit = 0; digit < 26; digit++) {
  #|    digitValues[65 + digit] = 10 + digit;
  #|    digitValues[97 + digit] = 10 + digit;
  #|  }
  #|  const chunkDigits = new Uint8Array(37);
  #|  const chunkPowers = new Array(37);
  #|  for (let radix = 2; radix <= 36; radix++) {
  #|    let digits = 0;
  #|    let power = 1;
  #|    while (power <= Number.MAX_SAFE_INTEGER / radix) {
  #|      power *= radix;
  #|      digits++;
  #|    }
  #|    chunkDigits[radix] = digits;
  #|    chunkPowers[radix] = BigInt(power);
  #|  }
  #|  const digitAt = (source, index) => {
  #|    const code = source.charCodeAt(index);
  #|    return code < 128 ? digitValues[code] : -1;
  #|  };
  #|  return (source, radix) => {
  #|    if (radix < 2 || radix > 36) {
  #|      return "Coeff radix must be between 2 and 36";
  #|    }
  #|    const length = source.length;
  #|    if (length === 0) return "Coeff cannot parse an empty string";
  #|    const first = source.charCodeAt(0);
  #|    if (first === 45) return "Coeff cannot be negative";
  #|    const start = first === 43 ? 1 : 0;
  #|    if (start === length) return "Coeff requires at least one digit";
  #|    if (radix === 2 || radix === 8 || radix === 10 || radix === 16) {
  #|      for (let index = start; index < length; index++) {
  #|        const digit = digitAt(source, index);
  #|        if (digit < 0 || digit >= radix) {
  #|          return "Coeff contains a digit outside the selected radix";
  #|        }
  #|      }
  #|      const digits = start === 0 ? source : source.slice(1);
  #|      if (radix === 10) return BigInt(digits);
  #|      const prefix = radix === 2 ? "0b" : radix === 8 ? "0o" : "0x";
  #|      return BigInt(prefix + digits);
  #|    }
  #|    const width = chunkDigits[radix];
  #|    let firstWidth = (length - start) % width;
  #|    if (firstWidth === 0) firstWidth = width;
  #|    let index = start;
  #|    let end = index + firstWidth;
  #|    let chunk = 0;
  #|    while (index < end) {
  #|      const digit = digitAt(source, index);
  #|      if (digit < 0 || digit >= radix) {
  #|        return "Coeff contains a digit outside the selected radix";
  #|      }
  #|      chunk = chunk * radix + digit;
  #|      index++;
  #|    }
  #|    let value = BigInt(chunk);
  #|    const multiplier = chunkPowers[radix];
  #|    while (index < length) {
  #|      end = index + width;
  #|      chunk = 0;
  #|      while (index < end) {
  #|        const digit = digitAt(source, index);
  #|        if (digit < 0 || digit >= radix) {
  #|          return "Coeff contains a digit outside the selected radix";
  #|        }
  #|        chunk = chunk * radix + digit;
  #|        index++;
  #|      }
  #|      value = value * multiplier + BigInt(chunk);
  #|    }
  #|    return value;
  #|  };
  #|})()

///|
pub fn Coeff::parse(
  source : String,
  radix~ : Int32 = 10,
) -> Result[Coeff, String] {
  let outcome = bin_coeff_parse(source, radix)
  if outcome.is_ok() {
    Ok(outcome.as_coeff())
  } else {
    Err(outcome.as_error())
  }
}

///|
extern "js" fn bin_coeff_from_bytes_be(
  source : Bytes,
  start : Int32,
  length : Int32,
) -> Coeff =
  #|(() => {
  #|  const hex = new Array(256);
  #|  for (let value = 0; value < 256; value++) {
  #|    hex[value] = value.toString(16).padStart(2, "0");
  #|  }
  #|  return (source, start, length) => {
  #|    const end = start + length;
  #|    let index = start;
  #|    while (index < end && source[index] === 0) index++;
  #|    if (index === end) return 0n;
  #|    let encoded = "0x";
  #|    while (index < end) encoded += hex[source[index++]];
  #|    return BigInt(encoded);
  #|  };
  #|})()

///|
pub fn Coeff::from_bytes_be(source : BytesView) -> Coeff {
  bin_coeff_from_bytes_be(source.data(), source.start_offset(), source.length())
}

///|
pub extern "js" fn Coeff::to_bytes_be(self : Coeff) -> Bytes =
  #|(() => {
  #|  const nibbles = new Uint8Array(103);
  #|  for (let value = 0; value < 10; value++) nibbles[48 + value] = value;
  #|  for (let value = 0; value < 6; value++) nibbles[97 + value] = 10 + value;
  #|  return (value) => {
  #|    if (value === 0n) return new Uint8Array([0]);
  #|    const hex = value.toString(16);
  #|    const result = new Uint8Array((hex.length + 1) >> 1);
  #|    let sourceIndex = 0;
  #|    let resultIndex = 0;
  #|    if ((hex.length & 1) !== 0) {
  #|      result[resultIndex++] = nibbles[hex.charCodeAt(sourceIndex++)];
  #|    }
  #|    while (sourceIndex < hex.length) {
  #|      result[resultIndex++] = (nibbles[hex.charCodeAt(sourceIndex)] << 4)
  #|        | nibbles[hex.charCodeAt(sourceIndex + 1)];
  #|      sourceIndex += 2;
  #|    }
  #|    return result;
  #|  };
  #|})()

///|
extern "js" fn bin_coeff_to_string(value : Coeff, radix : Int32) -> String =
  #|(value, radix) => value.toString(radix)

///|
pub fn Coeff::to_radix_string(self : Coeff, radix : Int32) -> String {
  if radix < 2 || radix > 36 {
    abort("Coeff radix must be between 2 and 36")
  }
  bin_coeff_to_string(self, radix)
}

///|
pub impl Eq for Coeff with fn equal(self, other) {
  bin_coeff_equal(self, other)
}

///|
pub impl Compare for Coeff with fn compare(self, other) {
  Coeff::compare(self, other)
}

///|
pub impl Show for Coeff with fn to_string(self) {
  self.to_radix_string(10)
}

///|
pub extend Coeff with Show::{to_string}

///|
pub impl Add for Coeff with fn add(self, other) {
  Coeff::add(self, other)
}

///|
pub impl Mul for Coeff with fn mul(self, other) {
  Coeff::mul(self, other)
}

///|
pub impl Shl for Coeff with fn shl(self, shift) {
  self.shift_left(shift)
}

///|
pub impl Shr for Coeff with fn shr(self, shift) {
  self.shift_right(shift)
}

///|
pub extend Coeff with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Coeff with Eq::{not_equal, equal}

///|
pub extend Coeff with Compare::{op_lt, op_le, op_ge, op_gt}

///|
pub extend Coeff with Show::{output}

///|
pub extend Coeff with Shl::{shl}

///|
pub extend Coeff with Shr::{shr}
