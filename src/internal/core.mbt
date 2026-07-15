///|
pub fn bigint_zero() -> BigInt {
  BigInt::from_int(0)
}

///|
pub fn bigint_one() -> BigInt {
  BigInt::from_int(1)
}

///|
pub fn abs_bigint(x : BigInt) -> BigInt {
  if x < bigint_zero() {
    -x
  } else {
    x
  }
}

///|
pub fn sign_of_bigint(x : BigInt) -> Sign {
  if x < bigint_zero() {
    Sign::Negative
  } else if x > bigint_zero() {
    Sign::Positive
  } else {
    Sign::Zero
  }
}

///|
let pow10_small : Array[BigInt] = [
  1N, 10N, 100N, 1000N, 10000N, 100000N, 1000000N, 10000000N, 100000000N, 1000000000N,
  10000000000N, 100000000000N, 1000000000000N, 10000000000000N, 100000000000000N,
  1000000000000000N, 10000000000000000N, 100000000000000000N, 1000000000000000000N,
]

///|
let pow5_small : Array[BigInt] = [
  1N, 5N, 25N, 125N, 625N, 3125N, 15625N, 78125N, 390625N, 1953125N, 9765625N, 48828125N,
  244140625N, 1220703125N, 6103515625N, 30517578125N, 152587890625N, 762939453125N,
  3814697265625N,
]

///|
let pow10_cache : Array[BigInt] = [..pow10_small]

///|
let pow5_cache : Array[BigInt] = [..pow5_small]

///|
let pow_cache_limit = 4096

///|
fn extend_pow_cache(
  cache : Array[BigInt],
  multiplier : BigInt,
  n : Int,
) -> BigInt {
  while cache.length() <= n {
    cache.push(cache[cache.length() - 1] * multiplier)
  }
  cache[n]
}

///|
pub fn pow2(n : Int) -> BigInt {
  guard n >= 0 else { abort("pow2 exponent must be non-negative") }
  bigint_one() << n
}

///|
pub fn pow10(n : Int) -> BigInt {
  guard n >= 0 else { abort("pow10 exponent must be non-negative") }
  if n < pow10_cache.length() {
    return pow10_cache[n]
  }
  if n > pow_cache_limit {
    return BigInt::from_int(10).pow(BigInt::from_int(n))
  }
  extend_pow_cache(pow10_cache, BigInt::from_int(10), n)
}

///|
pub fn pow5(n : Int) -> BigInt {
  guard n >= 0 else { abort("pow5 exponent must be non-negative") }
  if n < pow5_cache.length() {
    return pow5_cache[n]
  }
  if n > pow_cache_limit {
    return BigInt::from_int(5).pow(BigInt::from_int(n))
  }
  extend_pow_cache(pow5_cache, BigInt::from_int(5), n)
}

///|
pub fn digits10(x : BigInt) -> Int {
  let magnitude = abs_bigint(x)
  if magnitude.is_zero() {
    return 1
  }
  // Use bit length for a near-exact base-10 digit estimate, then correct at
  // the power-of-ten boundary instead of materializing the whole decimal text.
  let mut digits = (magnitude.bit_length().to_double() * 0.3010299956639812).to_int() +
    1
  let ten = BigInt::from_int(10)
  let mut lower = pow10(digits - 1)
  let mut upper = lower * ten
  while digits > 1 && magnitude < lower {
    digits -= 1
    upper = lower
    lower = lower / ten
  }
  while magnitude >= upper {
    digits += 1
    lower = upper
    upper = upper * ten
  }
  digits
}

///|
pub fn remove_factor2(sig : BigInt, exp : Int) -> (BigInt, Int) {
  if sig.is_zero() {
    (bigint_zero(), 0)
  } else {
    let shift = abs_bigint(sig).ctz()
    (sig >> shift, exp + shift)
  }
}

///|
pub fn remove_factor10(coeff : BigInt, exp : Int) -> (BigInt, Int) {
  if coeff.is_zero() {
    return (bigint_zero(), 0)
  }
  let ten = BigInt::from_int(10)
  let negative = coeff < bigint_zero()
  let mut value = abs_bigint(coeff)
  let mut exponent = exp
  while (value % ten).is_zero() {
    value = value / ten
    exponent += 1
  }
  (if negative { -value } else { value }, exponent)
}

///|
pub fn exact_divide_by_power_of_ten(coeff : BigInt, shift : Int) -> BigInt? {
  if coeff.is_zero() {
    return Some(bigint_zero())
  }
  guard shift >= 0 else {
    abort("exact_divide_by_power_of_ten expects shift >= 0")
  }
  let negative = coeff < bigint_zero()
  let divisor = pow10(shift)
  let value = abs_bigint(coeff)
  guard (value % divisor).is_zero() else { return None }
  let quotient = value / divisor
  Some(if negative { -quotient } else { quotient })
}

///|
pub fn trim_trailing_decimal_zeros(
  coeff : BigInt,
  exp : Int,
  max_drop? : Int = -1,
) -> (BigInt, Int, Int) {
  if coeff.is_zero() {
    return (bigint_zero(), 0, 0)
  }
  let ten = BigInt::from_int(10)
  let negative = coeff < bigint_zero()
  let mut value = abs_bigint(coeff)
  let mut exponent = exp
  let mut dropped = 0
  let limit = if max_drop < 0 { digits10(value) - 1 } else { max_drop }
  while dropped < limit && !value.is_zero() && (value % ten).is_zero() {
    value = value / ten
    exponent += 1
    dropped += 1
  }
  (if negative { -value } else { value }, exponent, dropped)
}

///|
fn should_increment(
  quotient : BigInt,
  remainder : BigInt,
  divisor : BigInt,
  negative : Bool,
  mode : RoundingMode,
) -> Bool {
  if remainder.is_zero() {
    return false
  }
  match mode {
    RoundingMode::TowardZero => false
    RoundingMode::TowardPositive => !negative
    RoundingMode::TowardNegative => negative
    RoundingMode::AwayFromZero => true
    RoundingMode::ToNearestEven => {
      let twice = remainder * BigInt::from_int(2)
      if twice > divisor {
        true
      } else if twice < divisor {
        false
      } else {
        !(quotient % BigInt::from_int(2)).is_zero()
      }
    }
  }
}

///|
pub fn round_positive_div(
  numerator : BigInt,
  denominator : BigInt,
  negative : Bool,
  mode : RoundingMode,
) -> BigInt {
  guard numerator >= bigint_zero() else {
    abort("round_positive_div expects non-negative numerator")
  }
  guard denominator > bigint_zero() else {
    abort("denominator must be positive")
  }
  let quotient = numerator / denominator
  let remainder = numerator % denominator
  if should_increment(quotient, remainder, denominator, negative, mode) {
    quotient + bigint_one()
  } else {
    quotient
  }
}

///|
pub fn round_shift(
  magnitude : BigInt,
  shift : Int,
  negative : Bool,
  mode : RoundingMode,
) -> BigInt {
  if shift <= 0 {
    return magnitude
  }
  let quotient = magnitude >> shift
  let remainder = magnitude - (quotient << shift)
  let divisor = bigint_one() << shift
  if should_increment(quotient, remainder, divisor, negative, mode) {
    quotient + bigint_one()
  } else {
    quotient
  }
}

///|
pub fn compare_abs(a : BigInt, b : BigInt) -> Int {
  abs_bigint(a).compare(abs_bigint(b))
}

///|
pub fn split_decimal_string(src : String) -> (Bool, String, Int)? {
  let exponent_cap = 1_500_000_000
  guard src.length() > 0 else { return None }
  let mut negative = false
  let mut start = 0
  if src[0] == '-' {
    negative = true
    start = 1
  } else if src[0] == '+' {
    start = 1
  }
  guard start < src.length() else { return None }
  let digits_builder = StringBuilder::new()
  let mut seen_point = false
  let mut frac_digits = 0
  let mut exp_mode = false
  let mut exp_negative = false
  let mut exp_seen_sign = false
  let mut exp_value = 0
  let mut exp_has_digit = false
  let mut has_digit = false
  let mut i = start
  while i < src.length() {
    let ch = src[i]
    if exp_mode {
      if !exp_has_digit && !exp_seen_sign && (ch == '+' || ch == '-') {
        exp_negative = ch == '-'
        exp_seen_sign = true
      } else if ch >= '0' && ch <= '9' {
        exp_has_digit = true
        let digit = ch.to_int() - '0'.to_int()
        if exp_value < exponent_cap {
          if exp_value > exponent_cap / 10 {
            exp_value = exponent_cap
          } else {
            let next = exp_value * 10 + digit
            exp_value = if next > exponent_cap { exponent_cap } else { next }
          }
        }
      } else {
        return None
      }
    } else if ch == '.' {
      guard !seen_point else { return None }
      seen_point = true
    } else if ch == 'e' || ch == 'E' {
      exp_mode = true
    } else if ch >= '0' && ch <= '9' {
      has_digit = true
      digits_builder.write_char(Int::unsafe_to_char(ch.to_int()))
      if seen_point {
        frac_digits += 1
      }
    } else {
      return None
    }
    i += 1
  }
  guard has_digit else { return None }
  guard !exp_mode || exp_has_digit else { return None }
  let digits = digits_builder.to_string()
  guard digits.length() > 0 else { return None }
  let extra_exp = if exp_negative { -exp_value } else { exp_value }
  Some((negative, digits, extra_exp - frac_digits))
}
