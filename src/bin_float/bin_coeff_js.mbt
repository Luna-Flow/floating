///|
#external
pub type BinCoeff

///|
pub impl Debug for BinCoeff with fn to_repr(self) {
  @debug.Repr::integer(self.to_string())
}

///|
#external
priv type BinCoeffOutcome

///|
extern "js" fn BinCoeffOutcome::is_ok(self : BinCoeffOutcome) -> Bool =
  #|(value) => typeof value === "bigint"

///|
fn BinCoeffOutcome::as_coeff(self : BinCoeffOutcome) -> BinCoeff = "%identity"

///|
fn BinCoeffOutcome::as_error(self : BinCoeffOutcome) -> String = "%identity"

///|
#external
priv type BinCoeffDivOutcome

///|
extern "js" fn BinCoeffDivOutcome::is_ok(self : BinCoeffDivOutcome) -> Bool =
  #|(value) => typeof value !== "string"

///|
extern "js" fn BinCoeffDivOutcome::quotient(
  self : BinCoeffDivOutcome,
) -> BinCoeff =
  #|(value) => value[0]

///|
extern "js" fn BinCoeffDivOutcome::remainder(
  self : BinCoeffDivOutcome,
) -> BinCoeff =
  #|(value) => value[1]

///|
fn BinCoeffDivOutcome::as_error(self : BinCoeffDivOutcome) -> String = "%identity"

///|
#external
priv type BinCoeffSqrtOutcome

///|
extern "js" fn BinCoeffSqrtOutcome::root(
  self : BinCoeffSqrtOutcome,
) -> BinCoeff =
  #|(value) => value[0]

///|
extern "js" fn BinCoeffSqrtOutcome::remainder(
  self : BinCoeffSqrtOutcome,
) -> BinCoeff =
  #|(value) => value[1]

///|
extern "js" fn bin_coeff_sqrt_rem_js(value : BinCoeff) -> BinCoeffSqrtOutcome =
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
fn bin_coeff_sqrt_rem_kernel(value : BinCoeff) -> (BinCoeff, BinCoeff) {
  let outcome = bin_coeff_sqrt_rem_js(value)
  (outcome.root(), outcome.remainder())
}

///|
pub extern "js" fn BinCoeff::zero() -> BinCoeff =
  #|() => 0n

///|
pub extern "js" fn BinCoeff::one() -> BinCoeff =
  #|() => 1n

///|
pub fn BinCoeff::from_uint64(value : UInt64) -> BinCoeff = "%identity"

///|
pub extern "js" fn BinCoeff::is_zero(self : BinCoeff) -> Bool =
  #|(value) => value === 0n

///|
extern "js" fn BinCoeff::is_odd(self : BinCoeff) -> Bool =
  #|(value) => (value & 1n) !== 0n

///|
pub extern "js" fn BinCoeff::bit_length(self : BinCoeff) -> Int =
  #|(value) => {
  #|  if (value === 0n) return 0;
  #|  const hex = value.toString(16);
  #|  const code = hex.charCodeAt(0);
  #|  const top = code <= 57 ? code - 48 : code - 87;
  #|  const topBits = top >= 8 ? 4 : top >= 4 ? 3 : top >= 2 ? 2 : 1;
  #|  return (hex.length - 1) * 4 + topBits;
  #|}

///|
pub extern "js" fn BinCoeff::ctz(self : BinCoeff) -> Int =
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
extern "js" fn bin_coeff_fits_uint64(value : BinCoeff) -> Bool =
  #|(value) => value <= 0xffffffffffffffffn

///|
fn bin_coeff_as_uint64(value : BinCoeff) -> UInt64 = "%identity"

///|
pub fn BinCoeff::to_uint64(self : BinCoeff) -> UInt64? {
  if bin_coeff_fits_uint64(self) {
    Some(bin_coeff_as_uint64(self))
  } else {
    None
  }
}

///|
pub extern "js" fn BinCoeff::test_bit(self : BinCoeff, index : Int) -> Bool =
  #|(value, index) => index >= 0 && ((value >> BigInt(index)) & 1n) !== 0n

///|
pub extern "js" fn BinCoeff::compare(self : BinCoeff, other : BinCoeff) -> Int =
  #|(left, right) => left < right ? -1 : left > right ? 1 : 0

///|
extern "js" fn bin_coeff_equal(left : BinCoeff, right : BinCoeff) -> Bool =
  #|(left, right) => left === right

///|
pub extern "js" fn BinCoeff::add(self : BinCoeff, other : BinCoeff) -> BinCoeff =
  #|(left, right) => left + right

///|
fn bin_coeff_add_normalized_odd(
  left : BinCoeff,
  right : BinCoeff,
) -> (BinCoeff, Int) {
  let sum = left.add(right)
  let normalization_shift = sum.ctz()
  (sum.shift_right(normalization_shift), normalization_shift)
}

///|
extern "js" fn bin_coeff_sub_checked(
  left : BinCoeff,
  right : BinCoeff,
) -> BinCoeffOutcome =
  #|(left, right) => left < right
  #|  ? "BinCoeff subtraction would be negative"
  #|  : left - right

///|
pub fn BinCoeff::sub_checked(
  self : BinCoeff,
  other : BinCoeff,
) -> Result[BinCoeff, String] {
  let outcome = bin_coeff_sub_checked(self, other)
  if outcome.is_ok() {
    Ok(outcome.as_coeff())
  } else {
    Err(outcome.as_error())
  }
}

///|
fn bin_coeff_sub_normalized_odd(
  left : BinCoeff,
  right : BinCoeff,
) -> (BinCoeff, Int) {
  let difference = left.sub_checked(right).unwrap()
  let normalization_shift = difference.ctz()
  (difference.shift_right(normalization_shift), normalization_shift)
}

///|
pub extern "js" fn BinCoeff::mul(self : BinCoeff, other : BinCoeff) -> BinCoeff =
  #|(left, right) => left * right

///|
pub extern "js" fn BinCoeff::square(self : BinCoeff) -> BinCoeff =
  #|(value) => value * value

///|
extern "js" fn bin_coeff_div_rem_checked(
  numerator : BinCoeff,
  denominator : BinCoeff,
) -> BinCoeffDivOutcome =
  #|(numerator, denominator) => {
  #|  if (denominator === 0n) return "BinCoeff division by zero";
  #|  if (numerator < denominator) return [0n, numerator];
  #|  const once = numerator - denominator;
  #|  if (once < denominator) return [1n, once];
  #|  const quotient = numerator / denominator;
  #|  return [quotient, numerator - quotient * denominator];
  #|}

///|
pub fn BinCoeff::div_rem_checked(
  self : BinCoeff,
  denominator : BinCoeff,
) -> Result[(BinCoeff, BinCoeff), String] {
  let outcome = bin_coeff_div_rem_checked(self, denominator)
  if outcome.is_ok() {
    Ok((outcome.quotient(), outcome.remainder()))
  } else {
    Err(outcome.as_error())
  }
}

///|
fn bin_coeff_short_div_rem(
  numerator : BinCoeff,
  denominator : BinCoeff,
) -> (BinCoeff, BinCoeff) {
  let outcome = bin_coeff_div_rem_checked(numerator, denominator)
  (outcome.quotient(), outcome.remainder())
}

///|
pub extern "js" fn BinCoeff::gcd(self : BinCoeff, other : BinCoeff) -> BinCoeff =
  #|(left, right) => {
  #|  while (right !== 0n) {
  #|    const remainder = left % right;
  #|    left = right;
  #|    right = remainder;
  #|  }
  #|  return left;
  #|}

///|
pub extern "js" fn BinCoeff::pow_nat(
  self : BinCoeff,
  exponent : UInt,
) -> BinCoeff =
  #|(value, exponent) => value ** BigInt(exponent >>> 0)

///|
extern "js" fn bin_coeff_shift_left(value : BinCoeff, shift : Int) -> BinCoeff =
  #|(value, shift) => value << BigInt(shift)

///|
pub fn BinCoeff::shift_left(self : BinCoeff, shift : Int) -> BinCoeff {
  if shift < 0 {
    abort("BinCoeff shift count must be non-negative")
  }
  bin_coeff_shift_left(self, shift)
}

///|
extern "js" fn bin_coeff_shift_right(value : BinCoeff, shift : Int) -> BinCoeff =
  #|(value, shift) => value >> BigInt(shift)

///|
pub fn BinCoeff::shift_right(self : BinCoeff, shift : Int) -> BinCoeff {
  if shift < 0 {
    abort("BinCoeff shift count must be non-negative")
  }
  bin_coeff_shift_right(self, shift)
}

///|
pub extern "js" fn BinCoeff::bit_and(
  self : BinCoeff,
  other : BinCoeff,
) -> BinCoeff =
  #|(left, right) => left & right

///|
pub extern "js" fn BinCoeff::bit_or(
  self : BinCoeff,
  other : BinCoeff,
) -> BinCoeff =
  #|(left, right) => left | right

///|
pub extern "js" fn BinCoeff::bit_xor(
  self : BinCoeff,
  other : BinCoeff,
) -> BinCoeff =
  #|(left, right) => left ^ right

///|
extern "js" fn bin_coeff_parse(source : String, radix : Int) -> BinCoeffOutcome =
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
  #|      return "BinCoeff radix must be between 2 and 36";
  #|    }
  #|    const length = source.length;
  #|    if (length === 0) return "BinCoeff cannot parse an empty string";
  #|    const first = source.charCodeAt(0);
  #|    if (first === 45) return "BinCoeff cannot be negative";
  #|    const start = first === 43 ? 1 : 0;
  #|    if (start === length) return "BinCoeff requires at least one digit";
  #|    if (radix === 2 || radix === 8 || radix === 10 || radix === 16) {
  #|      for (let index = start; index < length; index++) {
  #|        const digit = digitAt(source, index);
  #|        if (digit < 0 || digit >= radix) {
  #|          return "BinCoeff contains a digit outside the selected radix";
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
  #|        return "BinCoeff contains a digit outside the selected radix";
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
  #|          return "BinCoeff contains a digit outside the selected radix";
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
pub fn BinCoeff::parse(
  source : String,
  radix? : Int = 10,
) -> Result[BinCoeff, String] {
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
  start : Int,
  length : Int,
) -> BinCoeff =
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
pub fn BinCoeff::from_bytes_be(source : BytesView) -> BinCoeff {
  bin_coeff_from_bytes_be(source.data(), source.start_offset(), source.length())
}

///|
pub extern "js" fn BinCoeff::to_bytes_be(self : BinCoeff) -> Bytes =
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
extern "js" fn bin_coeff_to_string(value : BinCoeff, radix : Int) -> String =
  #|(value, radix) => value.toString(radix)

///|
pub fn BinCoeff::to_string(self : BinCoeff, radix? : Int = 10) -> String {
  if radix < 2 || radix > 36 {
    abort("BinCoeff radix must be between 2 and 36")
  }
  bin_coeff_to_string(self, radix)
}

///|
pub impl Eq for BinCoeff with fn equal(self, other) {
  bin_coeff_equal(self, other)
}

///|
pub impl Compare for BinCoeff with fn compare(self, other) {
  BinCoeff::compare(self, other)
}

///|
pub impl Show for BinCoeff with fn to_string(self) {
  BinCoeff::to_string(self)
}

///|
pub impl Add for BinCoeff with fn add(self, other) {
  BinCoeff::add(self, other)
}

///|
pub impl Mul for BinCoeff with fn mul(self, other) {
  BinCoeff::mul(self, other)
}

///|
pub impl Shl for BinCoeff with fn shl(self, shift) {
  self.shift_left(shift)
}

///|
pub impl Shr for BinCoeff with fn shr(self, shift) {
  self.shift_right(shift)
}
