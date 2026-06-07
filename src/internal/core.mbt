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
pub fn pow2(n : Int) -> BigInt {
  guard n >= 0 else { abort("pow2 exponent must be non-negative") }
  bigint_one() << n
}

///|
pub fn pow10(n : Int) -> BigInt {
  guard n >= 0 else { abort("pow10 exponent must be non-negative") }
  BigInt::from_int(10).pow(BigInt::from_int(n))
}

///|
pub fn pow5(n : Int) -> BigInt {
  guard n >= 0 else { abort("pow5 exponent must be non-negative") }
  BigInt::from_int(5).pow(BigInt::from_int(n))
}

///|
pub fn digits10(x : BigInt) -> Int {
  let s = abs_bigint(x).to_string()
  s.length()
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
  let mut coeff = coeff
  let mut exp = exp
  while (coeff % ten).is_zero() {
    coeff = coeff / ten
    exp += 1
  }
  (coeff, exp)
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
  let mut exp_value = 0
  let mut exp_has_digit = false
  let mut has_digit = false
  let mut i = start
  while i < src.length() {
    let ch = src[i]
    if exp_mode {
      if !exp_has_digit && (ch == '+' || ch == '-') {
        exp_negative = ch == '-'
      } else if ch >= '0' && ch <= '9' {
        exp_has_digit = true
        exp_value = exp_value * 10 + (ch.to_int() - '0'.to_int())
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
      digits_builder.write_string(src[i:i + 1].to_owned())
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
