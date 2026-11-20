///|
// Package-local decNumber-style decimal coefficient helpers.
//
// These are the coefficient-kernel routines we use inside the decimal
// package.  They are intentionally non-`pub`: callers outside the package
// should continue to work with Decimal values rather than raw coefficient
// storage.

///|
#derive(Debug)
pub(all) enum DecCoeff {
  Small(UInt64)
  Limbs(Array[UInt32], Int32)
}

///|
pub let dec_coeff_dpun = 9

///|
pub let dec_coeff_base = 1000000000

///|
let dec_coeff_powers : Array[Int32] = [
  1, 10, 100, 1000, 10000, 100000, 1000000, 10000000, 100000000, 1000000000,
]

///|
let dec_coeff_wide_base = 1000000000UL

///|
pub let dec_coeff_small_limit = 1000000000000000000UL

///|
pub let dec_coeff_small_powers10 : Array[UInt64] = [
  1UL, 10UL, 100UL, 1000UL, 10000UL, 100000UL, 1000000UL, 10000000UL, 100000000UL,
  1000000000UL, 10000000000UL, 100000000000UL, 1000000000000UL, 10000000000000UL,
  100000000000000UL, 1000000000000000UL, 10000000000000000UL, 100000000000000000UL,
  1000000000000000000UL,
]

///|
/// `10^0` to `10^19`: every power of ten that fits one 64-bit word.
let dec_coeff_word_powers10 : FixedArray[UInt64] = [
  1UL, 10UL, 100UL, 1000UL, 10000UL, 100000UL, 1000000UL, 10000000UL, 100000000UL,
  1000000000UL, 10000000000UL, 100000000000UL, 1000000000000UL, 10000000000000UL,
  100000000000000UL, 1000000000000000UL, 10000000000000000UL, 100000000000000000UL,
  1000000000000000000UL, 10000000000000000000UL,
]

///|
/// Number of decimal digits of a word (zero has one digit): the leading-zero
/// count gives `floor(bits * log10(2))` as an estimate that is one too small
/// at most, and one comparison with a power of ten corrects it.
pub fn dec_coeff_small_digits(value : UInt64) -> Int32 {
  // `| 1` keeps the digit count (an even value cannot be `10^k - 1`) and maps
  // zero to one
  let value = value | 1UL
  let bits = 64 - value.reinterpret_as_int64().clz()
  let estimate = (bits * 1233) >> 12
  if value >= dec_coeff_word_powers10.unsafe_get(estimate) {
    estimate + 1
  } else {
    estimate
  }
}

///|
fn dec_coeff_d2u(digits : Int32) -> Int32 {
  (digits + dec_coeff_dpun - 1) / dec_coeff_dpun
}

///|
fn dec_coeff_msu_digits(digits : Int32) -> Int32 {
  let rem = digits % dec_coeff_dpun
  if rem == 0 {
    dec_coeff_dpun
  } else {
    rem
  }
}

///|
fn dec_coeff_ensure_length(units : Array[UInt32], needed : Int32) -> Unit {
  while units.length() < needed {
    units.push(0U)
  }
}

///|
pub fn dec_coeff_zero() -> DecCoeff {
  Small(0UL)
}

///|
pub fn dec_coeff_from_int(value : Int32) -> DecCoeff {
  guard value >= 0 && value < dec_coeff_base else {
    abort("dec_coeff_from_int expects one non-negative coefficient unit")
  }
  DecCoeff::Small(value.to_uint64())
}

///|
pub fn dec_coeff_from_nonnegative_int(value : Int32) -> DecCoeff {
  guard value >= 0 else {
    abort("dec_coeff_from_nonnegative_int expects a non-negative integer")
  }
  if value == 0 {
    return dec_coeff_zero()
  }
  let value64 = value.to_uint64()
  if value64 < dec_coeff_small_limit {
    return DecCoeff::Small(value64)
  }
  let units : Array[UInt32] = []
  let mut remaining = value
  while remaining > 0 {
    units.push((remaining % dec_coeff_base).reinterpret_as_uint())
    remaining = remaining / dec_coeff_base
  }
  dec_coeff_from_unit_accumulator(units, units.length())
}

///|
pub fn dec_coeff_from_decimal_digits_repr(src : String) -> DecCoeff? {
  if src.length() == 0 {
    return None
  }
  if src.length() <= 18 {
    let mut value = 0UL
    for index in 0..<src.length() {
      let digit = src[index].to_int() - '0'.to_int()
      if digit < 0 || digit > 9 {
        return None
      }
      value = value * 10UL + digit.to_uint64()
    }
    return Some(DecCoeff::Small(value))
  }
  let unit_len = dec_coeff_d2u(src.length())
  let units = Array::make(unit_len, 0U)
  let mut end = src.length()
  let mut unit_index = 0
  while end > 0 {
    let start = Int32::max(0, end - dec_coeff_dpun)
    let mut value = 0
    for index in start..<end {
      let digit = src[index].to_int() - '0'.to_int()
      if digit < 0 || digit > 9 {
        return None
      }
      value = value * 10 + digit
    }
    units[unit_index] = value.reinterpret_as_uint()
    unit_index += 1
    end = start
  }
  Some(dec_coeff_from_unit_accumulator(units, unit_len))
}

///|
// Isomorphic to GDA decNumberFromInt32/decNumberFromUInt32: form the unsigned
// magnitude without negating the minimum Int, then decompose it in DECDPUN
// units. See libdecnumber/decNumber.c lines 345-374 in the GCC mirror.
pub fn dec_coeff_from_int_magnitude(value : Int32) -> DecCoeff {
  if value >= 0 {
    dec_coeff_from_nonnegative_int(value)
  } else {
    dec_coeff_magnitude_add_unit(
      dec_coeff_from_nonnegative_int(-(value + 1)),
      1,
    )
  }
}

///|
pub fn dec_coeff_power10_repr(shift : Int32) -> DecCoeff {
  guard shift >= 0 else {
    abort("dec_coeff_power10_repr expects a non-negative shift")
  }
  dec_coeff_shift_power10_repr(dec_coeff_from_int(1), shift)
}

///|
pub fn dec_coeff_unit_len(coeff : DecCoeff) -> Int32 {
  match coeff {
    Small(value) => if value < dec_coeff_wide_base { 1 } else { 2 }
    Limbs(units, _) => units.length()
  }
}

///|
pub fn dec_coeff_limb_at(coeff : DecCoeff, index : Int32) -> UInt32 {
  match coeff {
    Small(value) =>
      if index == 0 {
        (value % dec_coeff_wide_base).to_uint()
      } else if index == 1 {
        (value / dec_coeff_wide_base).to_uint()
      } else {
        0U
      }
    Limbs(units, _) => if index < units.length() { units[index] } else { 0U }
  }
}

///|
pub fn dec_coeff_copy_limbs(coeff : DecCoeff) -> Array[UInt32] {
  match coeff {
    Small(value) =>
      if value < dec_coeff_wide_base {
        [value.to_uint()]
      } else {
        [
          (value % dec_coeff_wide_base).to_uint(),
          (value / dec_coeff_wide_base).to_uint(),
        ]
      }
    Limbs(units, _) => units.copy()
  }
}

///|
fn dec_coeff_digits_cached(coeff : DecCoeff) -> Int32 {
  match coeff {
    Small(value) => dec_coeff_small_digits(value)
    Limbs(_, digits) => digits
  }
}

///|
fn dec_coeff_is_zero(coeff : DecCoeff) -> Bool {
  match coeff {
    Small(value) => value == 0UL
    Limbs(_, _) => false
  }
}

///|
pub fn dec_coeff_small_value(coeff : DecCoeff) -> UInt64? {
  match coeff {
    DecCoeff::Small(value) => Some(value)
    DecCoeff::Limbs(_, _) => None
  }
}

///|
pub fn dec_coeff_is_odd(coeff : DecCoeff) -> Bool {
  (dec_coeff_limb_at(coeff, 0) & 0x01U) == 1U
}

///|
pub fn dec_coeff_matches_unit_repr(coeff : DecCoeff, value : Int32) -> Bool {
  guard value >= 0 && value < dec_coeff_base else {
    abort("dec_coeff_matches_unit_repr expects one coefficient unit")
  }
  dec_coeff_unit_len(coeff) == 1 &&
  dec_coeff_limb_at(coeff, 0) == value.reinterpret_as_uint()
}

///|
pub fn DecCoeff::is_zero(self : DecCoeff) -> Bool {
  dec_coeff_is_zero(self)
}

///|
pub fn DecCoeff::to_bigint(self : DecCoeff) -> BigInt {
  dec_coeff_to_bigint_repr(self)
}

///|
pub fn DecCoeff::digits10(self : DecCoeff) -> Int32 {
  dec_coeff_digits_cached(self)
}

///|
pub fn DecCoeff::to_string(self : DecCoeff) -> String {
  let mut index = dec_coeff_unit_len(self) - 1
  let result = StringBuilder()
  result.write_string(dec_coeff_limb_at(self, index).to_string())
  while index > 0 {
    index -= 1
    let unit = dec_coeff_limb_at(self, index)
    let digits = unit.to_string()
    for _ in 0..<(dec_coeff_dpun - digits.length()) {
      result.write_char('0')
    }
    result.write_string(digits)
  }
  result.to_string()
}

///|
fn dec_coeff_from_bigint(magnitude : BigInt) -> (Array[UInt32], Int32) {
  guard magnitude >= 0N else {
    abort("dec_coeff_from_bigint expects a non-negative coefficient")
  }
  if magnitude.is_zero() {
    return ([0U], 1)
  }
  let base = BigInt::from_int(dec_coeff_base)
  let units : Array[UInt32] = []
  let mut remaining = magnitude
  while !remaining.is_zero() {
    let quotient = remaining / base
    let remainder = remaining - quotient * base
    units.push(remainder.to_int().reinterpret_as_uint())
    remaining = quotient
  }
  (units, dec_coeff_get_digits(units, units.length()))
}

///|
fn dec_coeff_to_bigint(
  units : Array[UInt32],
  unit_len~ : Int32 = units.length(),
) -> BigInt {
  guard unit_len >= 1 else {
    abort("dec_coeff_to_bigint expects unit_len >= 1")
  }
  let mut acc = 0N
  let base = BigInt::from_int(dec_coeff_base)
  let mut index = unit_len - 1
  while true {
    acc = acc * base + BigInt::from_int(units[index].reinterpret_as_int())
    if index == 0 {
      break
    }
    index -= 1
  }
  acc
}

///|
pub fn dec_coeff_from_bigint_repr(magnitude : BigInt) -> DecCoeff {
  let (units, _) = dec_coeff_from_bigint(magnitude)
  dec_coeff_from_unit_accumulator(units, units.length())
}

///|
pub fn dec_coeff_to_bigint_repr(coeff : DecCoeff) -> BigInt {
  match coeff {
    Small(value) => BigInt::from_uint64(value)
    Limbs(units, _) => dec_coeff_to_bigint(units)
  }
}

///|
fn dec_coeff_get_digits(units : Array[UInt32], unit_len : Int32) -> Int32 {
  guard unit_len >= 1 else {
    abort("dec_coeff_get_digits expects unit_len >= 1")
  }
  let mut index = unit_len - 1
  let mut digits = (unit_len - 1) * dec_coeff_dpun + 1
  while true {
    let unit = units[index]
    if unit == 0U {
      if digits == 1 {
        break
      }
      digits -= dec_coeff_dpun
    } else {
      let mut threshold = 10
      while unit.reinterpret_as_int() >= threshold {
        digits += 1
        if threshold == 100000000 {
          break
        }
        threshold *= 10
      }
      break
    }
    if index == 0 {
      break
    }
    index -= 1
  }
  digits
}

///|
fn dec_coeff_shift_to_most(
  units : Array[UInt32],
  digits : Int32,
  shift : Int32,
) -> Int32 {
  guard digits >= 1 else {
    abort("dec_coeff_shift_to_most expects digits >= 1")
  }
  guard shift >= 0 else { abort("dec_coeff_shift_to_most expects shift >= 0") }
  if shift == 0 {
    return digits
  }
  if digits + shift <= dec_coeff_dpun {
    units[0] = (units[0].reinterpret_as_int() * dec_coeff_powers[shift]).reinterpret_as_uint()
    return digits + shift
  }

  let source_units = dec_coeff_d2u(digits)
  let target_units = dec_coeff_d2u(digits + shift)
  dec_coeff_ensure_length(units, target_units)

  let mut next = 0
  let mut source = source_units - 1
  let mut target = source + dec_coeff_d2u(shift)
  let cut = dec_coeff_dpun - dec_coeff_msu_digits(shift)
  if cut == 0 {
    while true {
      units[target] = units[source]
      if source == 0 {
        break
      }
      source -= 1
      target -= 1
    }
    if target > 0 {
      target -= 1
    } else {
      target = -1
    }
  } else {
    let first = target_units - 1
    while true {
      let quot = units[source].reinterpret_as_int() / dec_coeff_powers[cut]
      let rem = units[source].reinterpret_as_int() -
        quot * dec_coeff_powers[cut]
      next += quot
      if target <= first {
        units[target] = next.reinterpret_as_uint()
      }
      next = rem * dec_coeff_powers[dec_coeff_dpun - cut]
      if source == 0 {
        break
      }
      source -= 1
      target -= 1
    }
    target -= 1
  }

  while target >= 0 {
    units[target] = next.reinterpret_as_uint()
    next = 0
    target -= 1
  }
  digits + shift
}

///|
fn dec_coeff_shift_to_least(
  units : Array[UInt32],
  unit_len : Int32,
  shift : Int32,
) -> Int32 {
  guard unit_len >= 1 else {
    abort("dec_coeff_shift_to_least expects unit_len >= 1")
  }
  guard shift >= 0 else { abort("dec_coeff_shift_to_least expects shift >= 0") }
  if shift == 0 {
    return unit_len
  }
  if shift == unit_len * dec_coeff_dpun {
    units[0] = 0U
    return 1
  }

  let mut target = 0
  let cut = dec_coeff_msu_digits(shift)
  if cut == dec_coeff_dpun {
    let mut up = dec_coeff_d2u(shift)
    while up < unit_len {
      units[target] = units[up]
      target += 1
      up += 1
    }
    return target
  }

  let mut up = dec_coeff_d2u(shift - cut)
  let mut count = unit_len * dec_coeff_dpun - shift
  let mut quot = units[up].reinterpret_as_int() / dec_coeff_powers[cut]
  while true {
    units[target] = quot.reinterpret_as_uint()
    count -= dec_coeff_dpun - cut
    if count <= 0 {
      break
    }
    up += 1
    let current = units[up]
    let rem = current.reinterpret_as_int() % dec_coeff_powers[cut]
    quot = current.reinterpret_as_int() / dec_coeff_powers[cut]
    units[target] = units[target] +
      (rem * dec_coeff_powers[dec_coeff_dpun - cut]).reinterpret_as_uint()
    count -= cut
    if count <= 0 {
      break
    }
    target += 1
  }
  target + 1
}

///|
fn dec_coeff_div_pow10_round_info_repr(
  numerator : DecCoeff,
  shift : Int32,
) -> (DecCoeff, Bool, Int32) {
  guard shift >= 0 else {
    abort("dec_coeff_div_pow10_round_info_repr expects shift >= 0")
  }
  if numerator.is_zero() || shift == 0 {
    return (numerator, false, -1)
  }
  let digits = numerator.digits10()
  if shift > digits {
    return (dec_coeff_zero(), true, -1)
  }
  if dec_coeff_small_value(numerator) is Some(value) {
    let divisor = dec_coeff_small_powers10[shift]
    let quotient = value / divisor
    let remainder = value % divisor
    let twice = remainder * 2UL
    return (
      DecCoeff::Small(quotient),
      remainder != 0UL,
      if twice < divisor {
        -1
      } else if twice > divisor {
        1
      } else {
        0
      },
    )
  }
  let quotient = if shift == digits {
    dec_coeff_zero()
  } else {
    let units = dec_coeff_copy_limbs(numerator)
    let quotient_len = dec_coeff_shift_to_least(
      units,
      dec_coeff_unit_len(numerator),
      shift,
    )
    dec_coeff_from_unit_accumulator(units, quotient_len)
  }
  let leading_position = shift - 1
  let leading_unit = leading_position / dec_coeff_dpun
  let leading_offset = leading_position % dec_coeff_dpun
  let leading_limb = dec_coeff_limb_at(numerator, leading_unit).reinterpret_as_int()
  let leading_digit = leading_limb / dec_coeff_powers[leading_offset] % 10
  let mut lower_nonzero = leading_limb % dec_coeff_powers[leading_offset] != 0
  for index in 0..<leading_unit {
    if dec_coeff_limb_at(numerator, index) != 0U {
      lower_nonzero = true
      break
    }
  }
  let has_remainder = leading_digit != 0 || lower_nonzero
  let half_cmp = if leading_digit < 5 {
    -1
  } else if leading_digit > 5 || lower_nonzero {
    1
  } else {
    0
  }
  (quotient, has_remainder, half_cmp)
}

///|
fn dec_coeff_unit_trailing_zeros(value : UInt32) -> Int32 {
  guard value != 0U else {
    abort("dec_coeff_unit_trailing_zeros expects a non-zero unit")
  }
  let magnitude = value.reinterpret_as_int()
  let mut zeros = 0
  while zeros < dec_coeff_dpun - 1 &&
        magnitude % dec_coeff_powers[zeros + 1] == 0 {
    zeros += 1
  }
  zeros
}

///|
fn dec_coeff_trim(
  units : Array[UInt32],
  digits : Int32,
  exponent : Int32,
  all~ : Bool = true,
  max_drop~ : Int32 = -1,
) -> (Int32, Int32, Int32) {
  guard digits >= 1 else { abort("dec_coeff_trim expects digits >= 1") }
  if (units[0] & 1U) == 1U {
    return (digits, exponent, 0)
  }
  if digits == 1 && units[0] == 0U {
    return (1, 0, 0)
  }

  let mut exp = exponent
  if all {
    let mut up = 0
    let mut dropped = 0
    let mut remaining = digits - 1
    while remaining > 0 {
      if units[up] == 0U {
        let take = Int32::min(dec_coeff_dpun, remaining)
        dropped += take
        remaining -= take
        up += 1
      } else {
        let take = Int32::min(
          dec_coeff_unit_trailing_zeros(units[up]),
          remaining,
        )
        dropped += take
        break
      }
    }
    if max_drop >= 0 && dropped > max_drop {
      dropped = max_drop
    }
    if dropped == 0 {
      return (digits, exponent, 0)
    }
    let unit_len = dec_coeff_d2u(digits)
    ignore(dec_coeff_shift_to_least(units, unit_len, dropped))
    return (digits - dropped, exponent + dropped, dropped)
  }
  let mut cut = 1
  let mut up = 0
  let mut dropped = 0
  while dropped < digits - 1 {
    let quot = units[up].reinterpret_as_int() / dec_coeff_powers[cut]
    if units[up].reinterpret_as_int() - quot * dec_coeff_powers[cut] != 0 {
      break
    }
    if !all {
      if exp <= 0 {
        if exp == 0 {
          break
        }
        exp += 1
      }
    }
    cut += 1
    if cut > dec_coeff_dpun {
      up += 1
      cut = 1
    }
    dropped += 1
  }
  if dropped == 0 {
    return (digits, exponent, 0)
  }

  if max_drop >= 0 && dropped > max_drop {
    dropped = max_drop
  }

  let unit_len = dec_coeff_d2u(digits)
  ignore(dec_coeff_shift_to_least(units, unit_len, dropped))
  (digits - dropped, exponent + dropped, dropped)
}

///|
fn dec_coeff_carry_quotient(carry : Int64) -> Int64 {
  let base = 1000000000L
  if carry >= 0L {
    carry / base
  } else {
    -((-carry + base - 1L) / base)
  }
}

///|
pub fn dec_coeff_unit_add_sub(
  a : Array[UInt32],
  alength : Int32,
  b : Array[UInt32],
  blength : Int32,
  bshift : Int32,
  c : Array[UInt32],
  m : Int32,
) -> Int32 {
  guard alength >= 1 else {
    abort("dec_coeff_unit_add_sub expects alength >= 1")
  }
  guard blength >= 1 else {
    abort("dec_coeff_unit_add_sub expects blength >= 1")
  }
  guard bshift >= 0 else { abort("dec_coeff_unit_add_sub expects bshift >= 0") }

  let mut carry = 0L
  let mut max_c = alength
  let mut min_c = blength
  let mut a_index = 0
  let mut b_index = 0
  let mut c_index = 0

  if bshift != 0 {
    min_c += bshift
    dec_coeff_ensure_length(c, bshift)
    while c_index < bshift {
      c[c_index] = if a_index < alength { a[a_index] } else { 0U }
      a_index += 1
      c_index += 1
    }
  }
  if min_c > max_c {
    let hold = min_c
    min_c = max_c
    max_c = hold
  }
  dec_coeff_ensure_length(c, max_c + 1)

  while c_index < min_c {
    carry += a[a_index].to_int64()
    a_index += 1
    carry += b[b_index].to_int64() * m.to_int64()
    b_index += 1
    if carry >= 0L && carry < 1000000000L {
      c[c_index] = carry.to_int().reinterpret_as_uint()
      carry = 0L
    } else {
      let next = dec_coeff_carry_quotient(carry)
      c[c_index] = (carry - next * 1000000000L).to_int().reinterpret_as_uint()
      carry = next
    }
    c_index += 1
  }

  while c_index < max_c {
    if a_index < alength {
      carry += a[a_index].to_int64()
      a_index += 1
    } else {
      carry += b[b_index].to_int64() * m.to_int64()
      b_index += 1
    }
    if carry >= 0L && carry < 1000000000L {
      c[c_index] = carry.to_int().reinterpret_as_uint()
      carry = 0L
    } else {
      let next = dec_coeff_carry_quotient(carry)
      c[c_index] = (carry - next * 1000000000L).to_int().reinterpret_as_uint()
      carry = next
    }
    c_index += 1
  }

  if carry == 0L {
    return c_index
  }
  if carry > 0L {
    c[c_index] = carry.to_int().reinterpret_as_uint()
    return c_index + 1
  }

  let mut add = 1
  let mut complement_index = 0
  while complement_index < max_c {
    add = dec_coeff_base - 1 + add - c[complement_index].reinterpret_as_int()
    if add <= dec_coeff_base - 1 {
      c[complement_index] = add.reinterpret_as_uint()
      add = 0
    } else {
      c[complement_index] = 0U
      add = 1
    }
    complement_index += 1
  }
  let mut written = max_c
  let upper = add.to_int64() - carry - 1L
  if upper != 0L {
    c[written] = upper.to_int().reinterpret_as_uint()
    written += 1
  }
  -written
}

///|
pub fn dec_coeff_shift_power10_repr(
  coeff : DecCoeff,
  shift : Int32,
) -> DecCoeff {
  guard shift >= 0 else {
    abort("dec_coeff_shift_power10_repr expects a non-negative shift")
  }
  if coeff.is_zero() || shift == 0 {
    return coeff
  }
  if dec_coeff_small_value(coeff) is Some(value) &&
    shift < dec_coeff_small_powers10.length() {
    let multiplier = dec_coeff_small_powers10[shift]
    if value == 0UL || multiplier <= (dec_coeff_small_limit - 1UL) / value {
      return DecCoeff::Small(value * multiplier)
    }
  }
  let units = dec_coeff_copy_limbs(coeff)
  let shifted_digits = dec_coeff_shift_to_most(units, coeff.digits10(), shift)
  dec_coeff_from_unit_accumulator(units, dec_coeff_d2u(shifted_digits))
}

///|
pub fn dec_coeff_compare_repr(lhs : DecCoeff, rhs : DecCoeff) -> Int32 {
  let lhs_len = dec_coeff_unit_len(lhs)
  let rhs_len = dec_coeff_unit_len(rhs)
  if lhs_len > rhs_len {
    return 1
  }
  if lhs_len < rhs_len {
    return -1
  }
  let mut index = lhs_len - 1
  while true {
    let lhs_limb = dec_coeff_limb_at(lhs, index)
    let rhs_limb = dec_coeff_limb_at(rhs, index)
    if lhs_limb > rhs_limb {
      return 1
    }
    if lhs_limb < rhs_limb {
      return -1
    }
    if index == 0 {
      break
    }
    index -= 1
  }
  0
}

///|
pub fn dec_coeff_compare_half_power10(coeff : DecCoeff) -> Int32 {
  if coeff.is_zero() {
    return -1
  }
  let digits = coeff.digits10()
  let most_significant_index = dec_coeff_unit_len(coeff) - 1
  let most_significant_limb = dec_coeff_limb_at(coeff, most_significant_index)
  let most_significant_digits = dec_coeff_msu_digits(digits)
  let leading_digit = most_significant_limb /
    dec_coeff_powers[most_significant_digits - 1].reinterpret_as_uint()
  if leading_digit < 5U {
    return -1
  }
  if leading_digit > 5U {
    return 1
  }
  if most_significant_limb %
    dec_coeff_powers[most_significant_digits - 1].reinterpret_as_uint() !=
    0U {
    return 1
  }
  for index in 0..<most_significant_index {
    if dec_coeff_limb_at(coeff, index) != 0U {
      return 1
    }
  }
  0
}

///|
fn dec_coeff_trim_units(units : Array[UInt32], unit_len : Int32) -> Int32 {
  let mut len = unit_len
  while len > 1 && units[len - 1] == 0U {
    len -= 1
  }
  len
}

///|
fn dec_coeff_write_wide_unit(
  units : Array[UInt32],
  wide_index : Int32,
  value : UInt64,
) -> Unit {
  guard value < dec_coeff_wide_base else {
    abort("decimal coefficient limb exceeds base")
  }
  units[wide_index] = value.to_uint()
}

///|
fn dec_coeff_from_wide_accumulator(
  wide_units : Array[UInt64],
  wide_len : Int32,
) -> DecCoeff {
  let units = Array::make(Int32::max(1, wide_len), 0U)
  for wide_index in 0..<wide_len {
    dec_coeff_write_wide_unit(units, wide_index, wide_units[wide_index])
  }
  dec_coeff_from_unit_accumulator(units, units.length())
}

///|
fn dec_coeff_multiply_units_by_unit(
  units : Array[UInt32],
  unit_len : Int32,
  multiplier : Int32,
) -> (Array[UInt32], Int32) {
  guard multiplier >= 0 && multiplier < dec_coeff_base else {
    abort("dec_coeff_multiply_units_by_unit expects one coefficient unit")
  }
  if multiplier == 0 {
    return ([0U], 1)
  }
  let result = Array::make(unit_len + 1, 0U)
  let len = dec_coeff_multiply_units_by_unit_into(
    units, unit_len, multiplier, result,
  )
  (result, dec_coeff_trim_units(result, len))
}

///|
fn dec_coeff_multiply_units_by_unit_into(
  units : Array[UInt32],
  unit_len : Int32,
  multiplier : Int32,
  result : Array[UInt32],
) -> Int32 {
  guard multiplier >= 0 && multiplier < dec_coeff_base else {
    abort("dec_coeff_multiply_units_by_unit_into expects one coefficient unit")
  }
  guard result.length() >= unit_len + 1 else {
    abort("dec_coeff_multiply_units_by_unit_into result is too short")
  }
  let mut carry = 0UL
  let mut index = 0
  while index < unit_len {
    let current = units[index].to_uint64() * multiplier.to_uint64() + carry
    result[index] = (current % dec_coeff_wide_base).to_uint()
    carry = current / dec_coeff_wide_base
    index += 1
  }
  result[index] = carry.to_uint()
  if carry == 0UL {
    unit_len
  } else {
    unit_len + 1
  }
}

///|
pub fn dec_coeff_multiply_by_unit_repr(
  coeff : DecCoeff,
  multiplier : Int32,
) -> DecCoeff {
  guard multiplier >= 0 && multiplier < dec_coeff_base else {
    abort("dec_coeff_multiply_by_unit_repr expects one coefficient unit")
  }
  if coeff.is_zero() || multiplier == 0 {
    return dec_coeff_zero()
  }
  if dec_coeff_small_value(coeff) is Some(value) {
    let multiplier = multiplier.to_uint64()
    if multiplier <= (dec_coeff_small_limit - 1UL) / value {
      return DecCoeff::Small(value * multiplier)
    }
  }
  let unit_len = dec_coeff_unit_len(coeff)
  let (product, product_len) = dec_coeff_multiply_units_by_unit(
    dec_coeff_copy_limbs(coeff),
    unit_len,
    multiplier,
  )
  dec_coeff_from_unit_accumulator(product, product_len)
}

///|
pub fn dec_coeff_pow_unit_repr(base : Int32, exponent : Int32) -> DecCoeff {
  guard exponent >= 0 else {
    abort("dec_coeff_pow_unit_repr expects a non-negative exponent")
  }
  guard base >= 0 && base < dec_coeff_base else {
    abort("dec_coeff_pow_unit_repr expects one coefficient unit")
  }
  dec_coeff_exact_power_repr(dec_coeff_from_int(base), exponent)
}

///|
pub fn dec_coeff_exact_power_repr(
  base : DecCoeff,
  exponent : Int32,
) -> DecCoeff {
  guard exponent >= 0 else {
    abort("dec_coeff_exact_power_repr expects a non-negative exponent")
  }
  if exponent == 0 {
    return dec_coeff_from_int(1)
  }
  let mut result = dec_coeff_from_int(1)
  let mut factor = base
  let mut remaining = exponent
  while remaining > 0 {
    if (remaining & 1) == 1 {
      result = dec_coeff_multiply_repr(result, factor)
    }
    remaining = remaining >> 1
    if remaining > 0 {
      factor = dec_coeff_square_repr(factor)
    }
  }
  result
}

///|
pub fn dec_coeff_exact_power_if_fits_repr(
  base : DecCoeff,
  exponent : Int32,
  max_digits : Int32,
) -> DecCoeff? {
  guard exponent >= 0 else {
    abort("dec_coeff_exact_power_if_fits_repr expects a non-negative exponent")
  }
  guard max_digits > 0 else {
    abort("dec_coeff_exact_power_if_fits_repr expects max_digits > 0")
  }
  if exponent == 0 {
    return Some(dec_coeff_from_int(1))
  }
  let mut result = dec_coeff_from_int(1)
  let mut factor = base
  let mut remaining = exponent
  if factor.digits10() > max_digits {
    return None
  }
  while remaining > 0 {
    if (remaining & 1) == 1 {
      result = dec_coeff_multiply_repr(result, factor)
      if result.digits10() > max_digits {
        return None
      }
    }
    remaining = remaining >> 1
    if remaining > 0 {
      factor = dec_coeff_square_repr(factor)
      if factor.digits10() > max_digits {
        return None
      }
    }
  }
  Some(result)
}

///|
pub fn dec_coeff_div_rem_by_unit_repr(
  coeff : DecCoeff,
  divisor : Int32,
) -> (DecCoeff, Int32) {
  guard divisor > 0 && divisor < dec_coeff_base else {
    abort(
      "dec_coeff_div_rem_by_unit_repr expects one positive coefficient unit",
    )
  }
  if coeff.is_zero() {
    return (dec_coeff_zero(), 0)
  }
  let wide_divisor = divisor.to_uint64()
  if dec_coeff_small_value(coeff) is Some(value) {
    return (
      DecCoeff::Small(value / wide_divisor),
      (value % wide_divisor).to_int(),
    )
  }
  let unit_len = dec_coeff_unit_len(coeff)
  if unit_len == 1 {
    let value = dec_coeff_limb_at(coeff, 0).to_uint64()
    return (
      dec_coeff_from_int((value / wide_divisor).to_int()),
      (value % wide_divisor).to_int(),
    )
  }
  let result = Array::make(unit_len, 0U)
  let mut remainder = 0UL
  let mut index = unit_len - 1
  while true {
    let current = remainder * dec_coeff_wide_base +
      dec_coeff_limb_at(coeff, index).to_uint64()
    result[index] = (current / wide_divisor).to_uint()
    remainder = current % wide_divisor
    if index == 0 {
      break
    }
    index -= 1
  }
  let result_len = dec_coeff_trim_units(result, unit_len)
  (dec_coeff_from_unit_accumulator(result, result_len), remainder.to_int())
}

///|
fn dec_coeff_mod_by_unit_repr(coeff : DecCoeff, divisor : Int32) -> Int32 {
  guard divisor > 0 && divisor < dec_coeff_base else {
    abort("dec_coeff_mod_by_unit_repr expects one positive coefficient unit")
  }
  if coeff.is_zero() {
    return 0
  }
  let wide_divisor = divisor.to_uint64()
  if dec_coeff_small_value(coeff) is Some(value) {
    return (value % wide_divisor).to_int()
  }
  let mut remainder = 0UL
  let mut index = dec_coeff_unit_len(coeff) - 1
  while true {
    let current = remainder * dec_coeff_wide_base +
      dec_coeff_limb_at(coeff, index).to_uint64()
    remainder = current % wide_divisor
    if index == 0 {
      break
    }
    index -= 1
  }
  remainder.to_int()
}

///|
fn dec_coeff_exact_divide_by_unit_repr(
  coeff : DecCoeff,
  divisor : Int32,
) -> DecCoeff? {
  let (quotient, remainder) = dec_coeff_div_rem_by_unit_repr(coeff, divisor)
  if remainder == 0 {
    Some(quotient)
  } else {
    None
  }
}

///|
pub fn dec_coeff_count_factor_unit_repr(
  coeff : DecCoeff,
  factor : Int32,
) -> (DecCoeff, Int32) {
  guard !coeff.is_zero() else {
    abort("dec_coeff_count_factor_unit_repr expects a non-zero coefficient")
  }
  // The base 10^9 is divisible by 2 and by 5, so for these two factors the
  // lowest limb alone decides whether the coefficient has the factor at all.
  if (factor == 2 || factor == 5) &&
    dec_coeff_limb_at(coeff, 0).reinterpret_as_int() % factor != 0 {
    return (coeff, 0)
  }
  let mut value = coeff
  let mut count = 0
  let (batch_factor, batch_count) = match factor {
    2 => (536870912, 29)
    5 => (244140625, 12)
    _ => (factor, 1)
  }
  if batch_count > 1 {
    while true {
      match dec_coeff_exact_divide_by_unit_repr(value, batch_factor) {
        Some(next) => {
          value = next
          count += batch_count
        }
        None => break
      }
    }
  }
  while true {
    match dec_coeff_exact_divide_by_unit_repr(value, factor) {
      Some(next) => {
        value = next
        count += 1
      }
      None => break
    }
  }
  (value, count)
}

///|
fn dec_coeff_remove_factor_unit_repr(
  coeff : DecCoeff,
  factor : Int32,
) -> DecCoeff {
  dec_coeff_count_factor_unit_repr(coeff, factor).0
}

///|
pub fn dec_coeff_from_unit_accumulator(
  units : Array[UInt32],
  unit_len : Int32,
) -> DecCoeff {
  guard unit_len >= 1 else {
    abort("dec_coeff_from_unit_accumulator expects unit_len >= 1")
  }
  guard unit_len <= units.length() else {
    abort("dec_coeff_from_unit_accumulator unit_len exceeds buffer")
  }
  // Every producer writes limbs below the base (checked by the white-box test
  // "unit accumulator producers write limbs below the base"), so the limbs are
  // not scanned again here.
  let unit_len = dec_coeff_trim_units(units, unit_len)
  if units.length() > unit_len {
    units.truncate(unit_len)
  }
  if unit_len <= 2 {
    let high = if unit_len == 2 {
      units[1].to_uint64() * dec_coeff_wide_base
    } else {
      0UL
    }
    let value = units[0].to_uint64() + high
    if value < dec_coeff_small_limit {
      Small(value)
    } else {
      Limbs(units, dec_coeff_get_digits(units, unit_len))
    }
  } else {
    Limbs(units, dec_coeff_get_digits(units, unit_len))
  }
}

///|
pub fn dec_coeff_magnitude_add_repr(lhs : DecCoeff, rhs : DecCoeff) -> DecCoeff {
  if lhs.is_zero() {
    return rhs
  }
  if rhs.is_zero() {
    return lhs
  }
  if dec_coeff_small_value(lhs) is Some(left) &&
    dec_coeff_small_value(rhs) is Some(right) {
    let sum = left + right
    if sum < dec_coeff_small_limit {
      return DecCoeff::Small(sum)
    }
  }
  if dec_coeff_unit_len(lhs) == 1 && dec_coeff_unit_len(rhs) == 1 {
    let sum = dec_coeff_limb_at(lhs, 0).to_uint64() +
      dec_coeff_limb_at(rhs, 0).to_uint64()
    if sum < dec_coeff_wide_base {
      return dec_coeff_from_int(sum.to_int())
    }
    return dec_coeff_from_unit_accumulator(
      [
        (sum % dec_coeff_wide_base).to_uint(),
        (sum / dec_coeff_wide_base).to_uint(),
      ],
      2,
    )
  }
  let lhs_len = dec_coeff_unit_len(lhs)
  let rhs_len = dec_coeff_unit_len(rhs)
  let wide_len = Int32::max(lhs_len, rhs_len)
  let result = Array::make(wide_len + 1, 0U)
  let mut carry = 0UL
  for wide_index in 0..<wide_len {
    let sum = dec_coeff_limb_at(lhs, wide_index).to_uint64() +
      dec_coeff_limb_at(rhs, wide_index).to_uint64() +
      carry
    if sum >= dec_coeff_wide_base {
      dec_coeff_write_wide_unit(result, wide_index, sum - dec_coeff_wide_base)
      carry = 1UL
    } else {
      dec_coeff_write_wide_unit(result, wide_index, sum)
      carry = 0UL
    }
  }
  if carry != 0UL {
    dec_coeff_write_wide_unit(result, wide_len, carry)
  }
  dec_coeff_from_unit_accumulator(result, result.length())
}

///|
pub fn dec_coeff_magnitude_sub_repr(lhs : DecCoeff, rhs : DecCoeff) -> DecCoeff {
  guard dec_coeff_compare_repr(lhs, rhs) >= 0 else {
    abort("dec_coeff_magnitude_sub_repr expects lhs >= rhs")
  }
  if rhs.is_zero() {
    return lhs
  }
  if dec_coeff_small_value(lhs) is Some(left) &&
    dec_coeff_small_value(rhs) is Some(right) {
    return DecCoeff::Small(left - right)
  }
  let lhs_len = dec_coeff_unit_len(lhs)
  let wide_len = lhs_len
  let result = Array::make(wide_len, 0U)
  let mut borrow = 0UL
  for wide_index in 0..<wide_len {
    let lhs_unit = dec_coeff_limb_at(lhs, wide_index).to_uint64()
    let rhs_unit = dec_coeff_limb_at(rhs, wide_index).to_uint64()
    let subtrahend = rhs_unit + borrow
    if lhs_unit < subtrahend {
      dec_coeff_write_wide_unit(
        result,
        wide_index,
        lhs_unit + dec_coeff_wide_base - subtrahend,
      )
      borrow = 1UL
    } else {
      dec_coeff_write_wide_unit(result, wide_index, lhs_unit - subtrahend)
      borrow = 0UL
    }
  }
  guard borrow == 0UL else { abort("dec_coeff_magnitude_sub_repr underflowed") }
  dec_coeff_from_unit_accumulator(result, result.length())
}

///|
pub fn dec_coeff_signed_add_repr(
  lhs_negative : Bool,
  lhs : DecCoeff,
  rhs_negative : Bool,
  rhs : DecCoeff,
) -> (Bool, DecCoeff) {
  if lhs.is_zero() {
    return if rhs.is_zero() {
      (false, dec_coeff_zero())
    } else {
      (rhs_negative, rhs)
    }
  }
  if rhs.is_zero() {
    return (lhs_negative, lhs)
  }
  if lhs_negative == rhs_negative {
    return (lhs_negative, dec_coeff_magnitude_add_repr(lhs, rhs))
  }
  match dec_coeff_compare_repr(lhs, rhs) {
    0 => (false, dec_coeff_zero())
    1 => (lhs_negative, dec_coeff_magnitude_sub_repr(lhs, rhs))
    _ => (rhs_negative, dec_coeff_magnitude_sub_repr(rhs, lhs))
  }
}

///|
fn dec_coeff_signed_compare_repr(
  lhs_negative : Bool,
  lhs : DecCoeff,
  rhs_negative : Bool,
  rhs : DecCoeff,
) -> Int32 {
  let lhs_negative = lhs_negative && !lhs.is_zero()
  let rhs_negative = rhs_negative && !rhs.is_zero()
  if lhs_negative != rhs_negative {
    return if lhs_negative { -1 } else { 1 }
  }
  let magnitude = dec_coeff_compare_repr(lhs, rhs)
  if lhs_negative {
    -magnitude
  } else {
    magnitude
  }
}

///|
pub fn dec_coeff_signed_compare_int_repr(
  negative : Bool,
  magnitude : DecCoeff,
  rhs : Int32,
) -> Int32 {
  dec_coeff_signed_compare_repr(
    negative,
    magnitude,
    rhs < 0,
    dec_coeff_from_int_magnitude(rhs),
  )
}

///|
pub fn dec_coeff_magnitude_add_unit(
  coeff : DecCoeff,
  addend : Int32,
) -> DecCoeff {
  guard addend >= 0 && addend < dec_coeff_base else {
    abort("dec_coeff_magnitude_add_unit expects one coefficient unit")
  }
  if addend == 0 {
    return coeff
  }
  if dec_coeff_small_value(coeff) is Some(value) {
    let sum = value + addend.to_uint64()
    if sum < dec_coeff_small_limit {
      return DecCoeff::Small(sum)
    }
  }
  let coeff_len = dec_coeff_unit_len(coeff)
  let result = dec_coeff_copy_limbs(coeff)
  dec_coeff_ensure_length(result, coeff_len + 1)
  let addend_units = [addend.reinterpret_as_uint()]
  let len = dec_coeff_unit_add_sub(
    result, coeff_len, addend_units, 1, 0, result, 1,
  )
  guard len > 0 else { abort("dec_coeff_magnitude_add_unit underflowed") }
  dec_coeff_from_unit_accumulator(result, len)
}

///|
pub fn dec_coeff_magnitude_sub_unit(
  coeff : DecCoeff,
  subtrahend : Int32,
) -> DecCoeff {
  guard subtrahend >= 0 && subtrahend < dec_coeff_base else {
    abort("dec_coeff_magnitude_sub_unit expects one coefficient unit")
  }
  if subtrahend == 0 {
    return coeff
  }
  if dec_coeff_small_value(coeff) is Some(value) {
    return DecCoeff::Small(value - subtrahend.to_uint64())
  }
  let coeff_len = dec_coeff_unit_len(coeff)
  let result = dec_coeff_copy_limbs(coeff)
  let rhs_units = [subtrahend.reinterpret_as_uint()]
  let len = dec_coeff_unit_add_sub(
    result, coeff_len, rhs_units, 1, 0, result, -1,
  )
  guard len >= 0 else { abort("dec_coeff_magnitude_sub_unit underflowed") }
  if len == 0 {
    dec_coeff_zero()
  } else {
    dec_coeff_from_unit_accumulator(result, len)
  }
}

///|
pub fn dec_coeff_signed_step_unit_repr(
  negative : Bool,
  magnitude : DecCoeff,
  toward_positive : Bool,
) -> (Bool, DecCoeff) {
  let one = dec_coeff_from_int(1)
  if toward_positive {
    if negative {
      if magnitude.is_zero() {
        (false, one)
      } else if dec_coeff_compare_repr(magnitude, one) == 0 {
        (false, dec_coeff_zero())
      } else {
        (true, dec_coeff_magnitude_sub_unit(magnitude, 1))
      }
    } else {
      (false, dec_coeff_magnitude_add_unit(magnitude, 1))
    }
  } else if negative {
    (true, dec_coeff_magnitude_add_unit(magnitude, 1))
  } else if magnitude.is_zero() {
    (true, one)
  } else if dec_coeff_compare_repr(magnitude, one) == 0 {
    (false, dec_coeff_zero())
  } else {
    (false, dec_coeff_magnitude_sub_unit(magnitude, 1))
  }
}

///|
fn dec_coeff_wide_trim_units(units : Array[UInt64], unit_len : Int32) -> Int32 {
  let mut len = unit_len
  while len > 1 && units[len - 1] == 0UL {
    len -= 1
  }
  len
}

///|
fn dec_coeff_wide_multiply_coeff_by_unit_into(
  coeff : DecCoeff,
  multiplier : UInt64,
  result : Array[UInt64],
) -> Int32 {
  let unit_len = dec_coeff_unit_len(coeff)
  let mut carry = 0UL
  for index in 0..<unit_len {
    let current = dec_coeff_limb_at(coeff, index).to_uint64() * multiplier +
      carry
    result[index] = current % dec_coeff_wide_base
    carry = current / dec_coeff_wide_base
  }
  result[unit_len] = carry
  if carry == 0UL {
    unit_len
  } else {
    unit_len + 1
  }
}

///|
/// Writes the limbs of `coeff` multiplied by `multiplier` (below the base) to
/// `target[0..unit_len]`: `unit_len + 1` limbs, the last one (index `unit_len`)
/// the carry out of the top limb, possibly zero. `target` must have room for
/// them.
fn dec_coeff_knuth_load(
  coeff : DecCoeff,
  multiplier : UInt64,
  target : FixedArray[UInt64],
) -> Unit {
  let unit_len = dec_coeff_unit_len(coeff)
  let mut carry = 0UL
  for index in 0..<unit_len {
    let current = dec_coeff_limb_at(coeff, index).to_uint64() * multiplier +
      carry
    carry = current / dec_coeff_wide_base
    target.unsafe_set(index, current - carry * dec_coeff_wide_base)
  }
  target.unsafe_set(unit_len, carry)
}

///|
/// Knuth's Algorithm D on limbs of base 10^9. `numerator` (`numerator_len`
/// limbs, one more limb of room, already multiplied by the normalization
/// unit) is divided in place by `denominator` (`denominator_len >= 2` limbs,
/// normalized: the top limb is at least 5 * 10^8): the quotient limbs are
/// written to `quotient[0..numerator_len - denominator_len]` and the
/// normalized remainder is left in `numerator[0..denominator_len)`.
fn dec_coeff_knuth_core(
  numerator : FixedArray[UInt64],
  numerator_len : Int32,
  denominator : FixedArray[UInt64],
  denominator_len : Int32,
  quotient : Array[UInt32],
) -> Unit {
  let base = dec_coeff_wide_base
  let top = denominator.unsafe_get(denominator_len - 1)
  let second_top = denominator.unsafe_get(denominator_len - 2)
  let mut shift = numerator_len - denominator_len
  while shift >= 0 {
    let upper = numerator.unsafe_get(shift + denominator_len)
    let next = numerator.unsafe_get(shift + denominator_len - 1)
    let pair = upper * base + next
    let mut quotient_digit = pair / top
    let mut remainder_digit = pair - quotient_digit * top
    if quotient_digit >= base {
      let excess = quotient_digit - (base - 1UL)
      quotient_digit = base - 1UL
      remainder_digit += excess * top
    }
    let below = numerator.unsafe_get(shift + denominator_len - 2)
    while remainder_digit < base &&
          quotient_digit * second_top > base * remainder_digit + below {
      quotient_digit -= 1UL
      remainder_digit += top
      if remainder_digit >= base {
        break
      }
    }
    // numerator[shift..shift + denominator_len] -= quotient_digit * denominator
    let mut carry = 0UL
    let mut borrow = 0UL
    for index in 0..<denominator_len {
      let product = denominator.unsafe_get(index) * quotient_digit + carry
      carry = product / base
      let subtrahend = product - carry * base + borrow
      let target = shift + index
      let value = numerator.unsafe_get(target)
      if value < subtrahend {
        numerator.unsafe_set(target, value + base - subtrahend)
        borrow = 1UL
      } else {
        numerator.unsafe_set(target, value - subtrahend)
        borrow = 0UL
      }
    }
    let top_target = shift + denominator_len
    let top_subtrahend = carry + borrow
    let top_value = numerator.unsafe_get(top_target)
    if top_value < top_subtrahend {
      numerator.unsafe_set(top_target, top_value + base - top_subtrahend)
      // the digit was one too large: add the denominator back
      quotient_digit -= 1UL
      let mut add_carry = 0UL
      for index in 0..<denominator_len {
        let target = shift + index
        let sum = numerator.unsafe_get(target) +
          denominator.unsafe_get(index) +
          add_carry
        if sum >= base {
          numerator.unsafe_set(target, sum - base)
          add_carry = 1UL
        } else {
          numerator.unsafe_set(target, sum)
          add_carry = 0UL
        }
      }
      let corrected = numerator.unsafe_get(top_target) + add_carry
      numerator.unsafe_set(
        top_target,
        if corrected >= base {
          corrected - base
        } else {
          corrected
        },
      )
    } else {
      numerator.unsafe_set(top_target, top_value - top_subtrahend)
    }
    quotient[shift] = quotient_digit.to_uint()
    shift -= 1
  }
}

///|
/// The normalized remainder `numerator[0..denominator_len)` divided by the
/// normalization unit, as limbs (below the base, leading zeros allowed).
fn dec_coeff_knuth_denormalize(
  numerator : FixedArray[UInt64],
  denominator_len : Int32,
  normalization : UInt64,
) -> Array[UInt32] {
  let result = Array::make(denominator_len, 0U)
  if normalization == 1UL {
    for index in 0..<denominator_len {
      result[index] = numerator.unsafe_get(index).to_uint()
    }
    return result
  }
  let mut residue = 0UL
  let mut index = denominator_len - 1
  while index >= 0 {
    let current = residue * dec_coeff_wide_base + numerator.unsafe_get(index)
    let quotient = current / normalization
    result[index] = quotient.to_uint()
    residue = current - quotient * normalization
    index -= 1
  }
  guard residue == 0UL else {
    abort("Knuth remainder is not divisible by the normalization unit")
  }
  result
}

///|
pub fn dec_coeff_div_rem_knuth_repr(
  numerator : DecCoeff,
  denominator : DecCoeff,
) -> (DecCoeff, DecCoeff) {
  let numerator_len = dec_coeff_unit_len(numerator)
  let denominator_len = dec_coeff_unit_len(denominator)
  if dec_coeff_compare_repr(numerator, denominator) < 0 {
    return (dec_coeff_zero(), numerator)
  }
  if denominator_len == 1 {
    let (quotient, residue) = dec_coeff_div_rem_by_unit_repr(
      numerator,
      dec_coeff_limb_at(denominator, 0).reinterpret_as_int(),
    )
    return (quotient, dec_coeff_from_int(residue))
  }
  let normalization = dec_coeff_wide_base /
    (dec_coeff_limb_at(denominator, denominator_len - 1).to_uint64() + 1UL)
  let normalized_denominator : FixedArray[UInt64] = FixedArray::make(
    denominator_len + 1,
    0UL,
  )
  let normalized_numerator : FixedArray[UInt64] = FixedArray::make(
    numerator_len + 1,
    0UL,
  )
  dec_coeff_knuth_load(denominator, normalization, normalized_denominator)
  dec_coeff_knuth_load(numerator, normalization, normalized_numerator)
  let quotient = Array::make(numerator_len - denominator_len + 1, 0U)
  dec_coeff_knuth_core(
    normalized_numerator, numerator_len, normalized_denominator, denominator_len,
    quotient,
  )
  let remainder = dec_coeff_knuth_denormalize(
    normalized_numerator, denominator_len, normalization,
  )
  (
    dec_coeff_from_unit_accumulator(quotient, quotient.length()),
    dec_coeff_from_unit_accumulator(remainder, remainder.length()),
  )
}

///|
fn dec_coeff_knuth_subtract_quotient_digit(
  normalized_numerator : Array[UInt64],
  normalized_denominator : Array[UInt64],
  denominator_len : Int32,
  shift : Int32,
) -> UInt64 {
  let top = normalized_denominator[denominator_len - 1]
  let second_top = normalized_denominator[denominator_len - 2]
  let upper = normalized_numerator[shift + denominator_len]
  let next = normalized_numerator[shift + denominator_len - 1]
  let mut quotient_digit = (upper * dec_coeff_wide_base + next) / top
  let mut remainder_digit = (upper * dec_coeff_wide_base + next) % top
  if quotient_digit >= dec_coeff_wide_base {
    let excess = quotient_digit - (dec_coeff_wide_base - 1UL)
    quotient_digit = dec_coeff_wide_base - 1UL
    remainder_digit += excess * top
  }
  while remainder_digit < dec_coeff_wide_base &&
        quotient_digit * second_top >
        dec_coeff_wide_base * remainder_digit +
        normalized_numerator[shift + denominator_len - 2] {
    quotient_digit -= 1UL
    remainder_digit += top
    if remainder_digit >= dec_coeff_wide_base {
      break
    }
  }
  let mut carry = 0UL
  let mut borrow = 0UL
  for index in 0..<denominator_len {
    let product = normalized_denominator[index] * quotient_digit + carry
    let product_digit = product % dec_coeff_wide_base
    carry = product / dec_coeff_wide_base
    let subtrahend = product_digit + borrow
    let target = shift + index
    if normalized_numerator[target] < subtrahend {
      normalized_numerator[target] = normalized_numerator[target] +
        dec_coeff_wide_base -
        subtrahend
      borrow = 1UL
    } else {
      normalized_numerator[target] = normalized_numerator[target] - subtrahend
      borrow = 0UL
    }
  }
  let top_target = shift + denominator_len
  let top_subtrahend = carry + borrow
  let mut negative = false
  if normalized_numerator[top_target] < top_subtrahend {
    normalized_numerator[top_target] = normalized_numerator[top_target] +
      dec_coeff_wide_base -
      top_subtrahend
    negative = true
  } else {
    normalized_numerator[top_target] = normalized_numerator[top_target] -
      top_subtrahend
  }
  if negative {
    quotient_digit -= 1UL
    let mut add_carry = 0UL
    for index in 0..<denominator_len {
      let target = shift + index
      let sum = normalized_numerator[target] +
        normalized_denominator[index] +
        add_carry
      if sum >= dec_coeff_wide_base {
        normalized_numerator[target] = sum - dec_coeff_wide_base
        add_carry = 1UL
      } else {
        normalized_numerator[target] = sum
        add_carry = 0UL
      }
    }
    normalized_numerator[top_target] = normalized_numerator[top_target] +
      add_carry
    if normalized_numerator[top_target] >= dec_coeff_wide_base {
      normalized_numerator[top_target] -= dec_coeff_wide_base
    }
  }
  quotient_digit
}

///|
fn dec_coeff_mod_knuth_repr(
  numerator : DecCoeff,
  denominator : DecCoeff,
) -> DecCoeff {
  guard !denominator.is_zero() else {
    abort("Knuth remainder expects denominator > 0")
  }
  if dec_coeff_compare_repr(numerator, denominator) < 0 {
    return numerator
  }
  let denominator_len = dec_coeff_unit_len(denominator)
  if denominator_len == 1 {
    let residue = dec_coeff_mod_by_unit_repr(
      numerator,
      dec_coeff_limb_at(denominator, 0).reinterpret_as_int(),
    )
    return dec_coeff_from_int(residue)
  }
  let remainder_len = dec_coeff_unit_len(numerator)
  let max_shift = remainder_len - denominator_len
  let normalized_denominator = Array::make(denominator_len + 1, 0UL)
  let normalized_numerator = Array::make(remainder_len + 1, 0UL)
  let normalization = dec_coeff_wide_base /
    (dec_coeff_limb_at(denominator, denominator_len - 1).to_uint64() + 1UL)
  ignore(
    dec_coeff_wide_multiply_coeff_by_unit_into(
      denominator, normalization, normalized_denominator,
    ),
  )
  ignore(
    dec_coeff_wide_multiply_coeff_by_unit_into(
      numerator, normalization, normalized_numerator,
    ),
  )
  let mut shift = max_shift
  while true {
    ignore(
      dec_coeff_knuth_subtract_quotient_digit(
        normalized_numerator, normalized_denominator, denominator_len, shift,
      ),
    )
    if shift == 0 {
      break
    }
    shift -= 1
  }
  let remainder_units = Array::make(denominator_len, 0UL)
  let mut residue = 0UL
  let mut index = denominator_len - 1
  while true {
    let current = residue * dec_coeff_wide_base + normalized_numerator[index]
    remainder_units[index] = current / normalization
    residue = current % normalization
    if index == 0 {
      break
    }
    index -= 1
  }
  if residue != 0UL {
    return dec_coeff_div_rem_knuth_repr(numerator, denominator).1
  }
  let remainder_len = dec_coeff_wide_trim_units(
    remainder_units,
    remainder_units.length(),
  )
  let remainder = dec_coeff_from_wide_accumulator(
    remainder_units, remainder_len,
  )
  if dec_coeff_compare_repr(remainder, denominator) >= 0 {
    return dec_coeff_div_rem_knuth_repr(numerator, denominator).1
  }
  remainder
}

///|
pub fn dec_coeff_div_rem_repr(
  numerator : DecCoeff,
  denominator : DecCoeff,
) -> (DecCoeff, DecCoeff) {
  guard !denominator.is_zero() else {
    abort("dec_coeff_div_rem_repr expects denominator > 0")
  }
  if numerator.is_zero() {
    return (dec_coeff_zero(), dec_coeff_zero())
  }
  if dec_coeff_small_value(numerator) is Some(left) &&
    dec_coeff_small_value(denominator) is Some(right) {
    return (DecCoeff::Small(left / right), DecCoeff::Small(left % right))
  }
  if dec_coeff_compare_repr(numerator, denominator) < 0 {
    return (dec_coeff_zero(), numerator)
  }
  let denom_len = dec_coeff_unit_len(denominator)
  if denom_len == 1 {
    let (quotient, residue) = dec_coeff_div_rem_by_unit_repr(
      numerator,
      dec_coeff_limb_at(denominator, 0).reinterpret_as_int(),
    )
    return (quotient, dec_coeff_from_int(residue))
  }
  match dec_coeff_division_algorithm(numerator, denominator) {
    Word => abort("word division was handled before dispatch")
    Newton => dec_coeff_div_rem_newton(numerator, denominator)
    BurnikelZiegler =>
      dec_coeff_div_rem_burnikel_ziegler(numerator, denominator)
    Knuth => dec_coeff_div_rem_knuth_repr(numerator, denominator)
  }
}

///|
/// The limbs of a coefficient as an array, read in place for a `Limbs` value
/// (a `Small` has two at most).
fn dec_coeff_limb_view(coeff : DecCoeff) -> Array[UInt32] {
  match coeff {
    Limbs(units, _) => units
    Small(_) => dec_coeff_copy_limbs(coeff)
  }
}

///|
/// The product of two limb arrays in column order, into `result` (zeroed, at
/// least `lhs_len + rhs_len` long).
///
/// Column `c` is the sum of the products `lhs[i] * rhs[c - i]`. A product is
/// at most `(10^9 - 1)^2 < 10^18`. The sum of a column is kept in one `UInt64`
/// `acc` that starts at the carry of the previous column and takes up to
/// `dec_coeff_column_fold` = 16 products, then is folded: `q = acc / 10^9`,
/// `acc = acc - q * 10^9`, and `q` is added to `folded`, so that after a fold
/// `acc < 10^9`. Between two folds `acc` stays below
///
///   10^9 + 16 * (10^9 - 1)^2 < 1.6 * 10^19 + 10^9 < 2^64 = 1.8446... * 10^19
///
/// and at the start of a column (no fold yet, `acc = carry`)
///
///   carry + 16 * (10^9 - 1)^2 < 2^64   as long as   carry < 2.44 * 10^18.
///
/// The carry out of a column is at most `floor((carry + n * (10^9 - 1)^2) /
/// 10^9) < carry / 10^9 + n * 10^9` with `n` the number of products of the
/// column, at most `min(lhs_len, rhs_len)`. The result array has
/// `lhs_len + rhs_len + 1` limbs and an array has fewer than `2^31` elements,
/// so `n < 2^30` and, inductively, `carry < 1.08 * 10^18 < 2.44 * 10^18`: the
/// sums cannot overflow for any operand the function can receive.
///
/// Used when the shorter operand has more than 18 limbs; for at most 18 limbs
/// `dec_coeff_mul_columns_short` is faster. Each column ends with one reduction.
fn dec_coeff_mul_columns(
  lhs : Array[UInt32],
  lhs_len : Int32,
  rhs : Array[UInt32],
  rhs_len : Int32,
  result : Array[UInt32],
) -> Unit {
  let base = dec_coeff_wide_base
  let columns = lhs_len + rhs_len - 1
  let mut carry = 0UL
  for column in 0..<columns {
    let start = Int32::max(0, column - (rhs_len - 1))
    let stop = Int32::min(lhs_len - 1, column)
    let mut acc = carry
    let mut folded = 0UL
    let mut index = start
    while index <= stop {
      let group_end = if stop - index >= dec_coeff_column_fold {
        index + dec_coeff_column_fold - 1
      } else {
        stop
      }
      while index <= group_end {
        acc += lhs.unsafe_get(index).to_uint64() *
          rhs.unsafe_get(column - index).to_uint64()
        index += 1
      }
      if index <= stop {
        let quotient = acc / base
        acc = acc - quotient * base
        folded += quotient
      }
    }
    let quotient = acc / base
    result.unsafe_set(column, (acc - quotient * base).to_uint())
    carry = folded + quotient
  }
  let mut column = columns
  while carry != 0UL {
    let quotient = carry / base
    result.unsafe_set(column, (carry - quotient * base).to_uint())
    carry = quotient
    column += 1
  }
}

///|
/// The product of two operands of at most 18 limbs (the shorter one), by
/// columns with no fold: no column has more than 18 products, the carry out of
/// a column is below `carry / 10^9 + 18 * 10^9`, so every carry is below
/// `1.9 * 10^10`, and the sum of a column is below
///
///   1.9 * 10^10 + 18 * (10^9 - 1)^2 < 1.8000000019 * 10^19 < 2^64
///
/// (18 * (10^9 - 1)^2 = 17,999,999,964,000,000,018; the margin to `2^64` is
/// 4.4 * 10^17). This is the loop of `dec_coeff_mul_columns` with a fold count
/// of 18, written as its own function on purpose: the generic loop, with any
/// fold count, makes the compiler emit a vectorized loop whose set-up costs
/// 8 to 11 percent on columns of 16 to 18 products (measured on 16, 17 and 18
/// limbs; a plain loop that the compiler may still vectorize costs 4 percent
/// on every short size), and a loop that cannot be vectorized is the fastest
/// below 19 limbs. The inner loop is the counting loop `for i in a..<=b` over
/// the two arrays, the form that the compiler leaves scalar here.
fn dec_coeff_mul_columns_short(
  lhs : Array[UInt32],
  lhs_len : Int32,
  rhs : Array[UInt32],
  rhs_len : Int32,
  result : Array[UInt32],
) -> Unit {
  let base = dec_coeff_wide_base
  let columns = lhs_len + rhs_len - 1
  let mut carry = 0UL
  for column in 0..<columns {
    let lhs_start = Int32::max(0, column - (rhs_len - 1))
    let lhs_end = Int32::min(lhs_len - 1, column)
    let mut current = carry
    for lhs_index in lhs_start..<=lhs_end {
      current += lhs.unsafe_get(lhs_index).to_uint64() *
        rhs.unsafe_get(column - lhs_index).to_uint64()
    }
    carry = current / base
    result.unsafe_set(column, (current - carry * base).to_uint())
  }
  let mut column = columns
  while carry != 0UL {
    let quotient = carry / base
    result.unsafe_set(column, (carry - quotient * base).to_uint())
    carry = quotient
    column += 1
  }
}

///|
/// Products accumulated between two folds of a column sum (see
/// `dec_coeff_mul_columns` for the bound).
let dec_coeff_column_fold : Int32 = 16

///|
fn dec_coeff_mul_schoolbook(lhs : DecCoeff, rhs : DecCoeff) -> DecCoeff {
  if lhs.is_zero() || rhs.is_zero() {
    return dec_coeff_zero()
  }
  let lhs_len = dec_coeff_unit_len(lhs)
  let rhs_len = dec_coeff_unit_len(rhs)
  let result = Array::make(lhs_len + rhs_len + 1, 0U)
  let lhs_view = dec_coeff_limb_view(lhs)
  let rhs_view = dec_coeff_limb_view(rhs)
  if Int32::min(lhs_len, rhs_len) <= 18 {
    dec_coeff_mul_columns_short(lhs_view, lhs_len, rhs_view, rhs_len, result)
  } else {
    dec_coeff_mul_columns(lhs_view, lhs_len, rhs_view, rhs_len, result)
  }
  dec_coeff_from_unit_accumulator(result, result.length())
}

///|
pub fn dec_coeff_compare_scaled_repr(
  lhs : DecCoeff,
  rhs : DecCoeff,
  exp : Int32,
) -> Int32 {
  guard exp >= 0 else {
    abort("dec_coeff_compare_scaled_repr expects a non-negative exponent")
  }
  let alength = dec_coeff_unit_len(lhs)
  let blength = dec_coeff_unit_len(rhs)
  if exp == 0 {
    return dec_coeff_compare_repr(lhs, rhs)
  }
  let expunit_shift = exp / dec_coeff_dpun
  let exprem = exp % dec_coeff_dpun
  let multiplier = dec_coeff_powers[exprem].to_uint64()
  let need = Int32::max(alength, expunit_shift + blength + 1)
  let mut multiply_carry = 0UL
  let mut borrow = 0UL
  let mut nonzero = false
  for index in 0..<need {
    let lhs_unit = if index < alength {
      dec_coeff_limb_at(lhs, index).to_uint64()
    } else {
      0UL
    }
    let rhs_index = index - expunit_shift
    let rhs_unit = if rhs_index >= 0 && rhs_index < blength {
      let product = dec_coeff_limb_at(rhs, rhs_index).to_uint64() * multiplier +
        multiply_carry
      multiply_carry = product / dec_coeff_wide_base
      product % dec_coeff_wide_base
    } else if rhs_index == blength {
      let carry = multiply_carry
      multiply_carry = 0UL
      carry
    } else {
      0UL
    }
    let subtrahend = rhs_unit + borrow
    let difference = if lhs_unit >= subtrahend {
      borrow = 0UL
      lhs_unit - subtrahend
    } else {
      borrow = 1UL
      lhs_unit + dec_coeff_wide_base - subtrahend
    }
    if difference != 0UL {
      nonzero = true
    }
  }
  if borrow != 0UL {
    -1
  } else if nonzero {
    1
  } else {
    0
  }
}

///|
pub fn remove_factor10_repr(coeff : DecCoeff, exp : Int32) -> (DecCoeff, Int32) {
  if coeff.is_zero() {
    return (dec_coeff_zero(), 0)
  }
  if dec_coeff_limb_at(coeff, 0).reinterpret_as_int() % 10 != 0 {
    return (coeff, exp)
  }
  let units = dec_coeff_copy_limbs(coeff)
  let (trimmed_digits, exponent, _) = dec_coeff_trim(
    units,
    coeff.digits10(),
    exp,
    all=true,
  )
  (
    dec_coeff_from_unit_accumulator(units, dec_coeff_d2u(trimmed_digits)),
    exponent,
  )
}

///|
pub fn exact_divide_by_power_of_ten_repr(
  coeff : DecCoeff,
  shift : Int32,
) -> DecCoeff? {
  guard shift >= 0 else {
    abort("exact_divide_by_power_of_ten_repr expects shift >= 0")
  }
  if coeff.is_zero() {
    return Some(dec_coeff_zero())
  }
  if shift == 0 {
    return Some(coeff)
  }
  guard shift < coeff.digits10() else { return None }
  let units = dec_coeff_copy_limbs(coeff)
  let mut cut = 1
  let mut up = 0
  let mut checked = 0
  while checked < shift {
    let quot = units[up].reinterpret_as_int() / dec_coeff_powers[cut]
    guard units[up].reinterpret_as_int() - quot * dec_coeff_powers[cut] == 0 else {
      return None
    }
    cut += 1
    if cut > dec_coeff_dpun {
      up += 1
      cut = 1
    }
    checked += 1
  }
  let trimmed_units = dec_coeff_shift_to_least(
    units,
    dec_coeff_unit_len(coeff),
    shift,
  )
  Some(dec_coeff_from_unit_accumulator(units, trimmed_units))
}

///|
pub fn trim_trailing_decimal_zeros_repr(
  coeff : DecCoeff,
  exp : Int32,
  max_drop~ : Int32 = -1,
) -> (DecCoeff, Int32, Int32) {
  if coeff.is_zero() {
    return (dec_coeff_zero(), 0, 0)
  }
  if max_drop == 0 || dec_coeff_limb_at(coeff, 0).reinterpret_as_int() % 10 != 0 {
    return (coeff, exp, 0)
  }
  let units = dec_coeff_copy_limbs(coeff)
  let (trimmed_digits, exponent, dropped) = dec_coeff_trim(
    units,
    coeff.digits10(),
    exp,
    all=true,
    max_drop~,
  )
  (
    dec_coeff_from_unit_accumulator(units, dec_coeff_d2u(trimmed_digits)),
    exponent,
    dropped,
  )
}

///|
pub fn dec_coeff_shift_power10_mod_repr(
  coeff : DecCoeff,
  shift : Int32,
  modulus : DecCoeff,
) -> DecCoeff {
  guard shift >= 0 else {
    abort("dec_coeff_shift_power10_mod_repr expects a non-negative shift")
  }
  guard !modulus.is_zero() else {
    abort("dec_coeff_shift_power10_mod_repr expects a non-zero modulus")
  }
  let mut remainder = dec_coeff_mod_repr(coeff, modulus)
  let mut factor = dec_coeff_mod_repr(dec_coeff_from_int(10), modulus)
  let mut exponent = shift
  while exponent > 0 {
    if exponent % 2 == 1 {
      remainder = dec_coeff_mod_repr(
        dec_coeff_multiply_repr(remainder, factor),
        modulus,
      )
    }
    exponent /= 2
    if exponent > 0 {
      factor = dec_coeff_mod_repr(
        dec_coeff_multiply_repr(factor, factor),
        modulus,
      )
    }
  }
  remainder
}

///|
pub fn dec_coeff_mod_repr(
  numerator : DecCoeff,
  denominator : DecCoeff,
) -> DecCoeff {
  guard !denominator.is_zero() else {
    abort("dec_coeff_mod_repr expects denominator > 0")
  }
  if numerator.is_zero() {
    return dec_coeff_zero()
  }
  if numerator is Small(left) && denominator is Small(right) {
    return Small(left % right)
  }
  if dec_coeff_compare_repr(numerator, denominator) < 0 {
    return numerator
  }
  let denominator_len = dec_coeff_unit_len(denominator)
  if denominator_len == 1 {
    return dec_coeff_from_int(
      dec_coeff_mod_by_unit_repr(
        numerator,
        dec_coeff_limb_at(denominator, 0).reinterpret_as_int(),
      ),
    )
  }
  match dec_coeff_division_algorithm(numerator, denominator) {
    Word => abort("word remainder was handled before dispatch")
    Newton => dec_coeff_div_rem_newton(numerator, denominator).1
    BurnikelZiegler =>
      dec_coeff_div_rem_burnikel_ziegler(numerator, denominator).1
    Knuth => dec_coeff_mod_knuth_repr(numerator, denominator)
  }
}

///|
pub fn dec_coeff_gcd_repr(lhs : DecCoeff, rhs : DecCoeff) -> DecCoeff {
  let mut x = lhs
  let mut y = rhs
  while !y.is_zero() {
    let remainder = dec_coeff_mod_repr(x, y)
    x = y
    y = remainder
  }
  x
}
