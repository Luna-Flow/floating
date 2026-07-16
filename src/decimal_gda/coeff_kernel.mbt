///|
// Package-local decNumber-style decimal coefficient helpers.
//
// These are the coefficient-kernel routines we use inside the decimal
// package.  They are intentionally non-`pub`: callers outside the package
// should continue to work with Decimal values rather than raw coefficient
// storage.

///|
priv enum GdaCoeff {
  Small(UInt64)
  Limbs(Array[UInt], Int)
} derive(Debug)

///|
let gda_coeff_dpun = 9

///|
let gda_coeff_base = 1000000000

///|
let gda_coeff_powers : Array[Int] = [
  1, 10, 100, 1000, 10000, 100000, 1000000, 10000000, 100000000, 1000000000,
]

///|
let gda_coeff_wide_base = 1000000000UL

///|
let gda_coeff_small_limit = 1000000000000000000UL

///|
let gda_coeff_small_powers10 : Array[UInt64] = [
  1UL, 10UL, 100UL, 1000UL, 10000UL, 100000UL, 1000000UL, 10000000UL, 100000000UL,
  1000000000UL, 10000000000UL, 100000000000UL, 1000000000000UL, 10000000000000UL,
  100000000000000UL, 1000000000000000UL, 10000000000000000UL, 100000000000000000UL,
  1000000000000000000UL,
]

///|
fn gda_coeff_small_digits(value : UInt64) -> Int {
  let mut digits = 1
  while digits < gda_coeff_small_powers10.length() &&
        value >= gda_coeff_small_powers10[digits] {
    digits += 1
  }
  digits
}

///|
fn gda_coeff_d2u(digits : Int) -> Int {
  (digits + gda_coeff_dpun - 1) / gda_coeff_dpun
}

///|
fn gda_coeff_msu_digits(digits : Int) -> Int {
  let rem = digits % gda_coeff_dpun
  if rem == 0 {
    gda_coeff_dpun
  } else {
    rem
  }
}

///|
fn gda_coeff_ensure_length(units : Array[UInt], needed : Int) -> Unit {
  while units.length() < needed {
    units.push(0U)
  }
}

///|
fn gda_coeff_zero() -> GdaCoeff {
  Small(0UL)
}

///|
fn gda_coeff_from_int(value : Int) -> GdaCoeff {
  guard value >= 0 && value < gda_coeff_base else {
    abort("gda_coeff_from_int expects one non-negative coefficient unit")
  }
  GdaCoeff::Small(value.to_uint64())
}

///|
fn gda_coeff_from_nonnegative_int(value : Int) -> GdaCoeff {
  guard value >= 0 else {
    abort("gda_coeff_from_nonnegative_int expects a non-negative integer")
  }
  if value == 0 {
    return gda_coeff_zero()
  }
  let value64 = value.to_uint64()
  if value64 < gda_coeff_small_limit {
    return GdaCoeff::Small(value64)
  }
  let units : Array[UInt] = []
  let mut remaining = value
  while remaining > 0 {
    units.push((remaining % gda_coeff_base).reinterpret_as_uint())
    remaining = remaining / gda_coeff_base
  }
  gda_coeff_from_unit_accumulator(units, units.length())
}

///|
fn gda_coeff_from_decimal_digits_repr(src : String) -> GdaCoeff? {
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
    return Some(GdaCoeff::Small(value))
  }
  let unit_len = gda_coeff_d2u(src.length())
  let units = Array::make(unit_len, 0U)
  let mut end = src.length()
  let mut unit_index = 0
  while end > 0 {
    let start = Int::max(0, end - gda_coeff_dpun)
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
  Some(gda_coeff_from_unit_accumulator(units, unit_len))
}

///|
// Isomorphic to GDA decNumberFromInt32/decNumberFromUInt32: form the unsigned
// magnitude without negating the minimum Int, then decompose it in DECDPUN
// units. See libdecnumber/decNumber.c lines 345-374 in the GCC mirror.
fn gda_coeff_from_int_magnitude(value : Int) -> GdaCoeff {
  if value >= 0 {
    gda_coeff_from_nonnegative_int(value)
  } else {
    gda_coeff_magnitude_add_unit(
      gda_coeff_from_nonnegative_int(-(value + 1)),
      1,
    )
  }
}

///|
fn gda_coeff_power10_repr(shift : Int) -> GdaCoeff {
  guard shift >= 0 else {
    abort("gda_coeff_power10_repr expects a non-negative shift")
  }
  gda_coeff_shift_power10_repr(gda_coeff_from_int(1), shift)
}

///|
fn gda_coeff_unit_len(coeff : GdaCoeff) -> Int {
  match coeff {
    Small(value) => if value < gda_coeff_wide_base { 1 } else { 2 }
    Limbs(units, _) => units.length()
  }
}

///|
fn gda_coeff_limb_at(coeff : GdaCoeff, index : Int) -> UInt {
  match coeff {
    Small(value) =>
      if index == 0 {
        (value % gda_coeff_wide_base).to_uint()
      } else if index == 1 {
        (value / gda_coeff_wide_base).to_uint()
      } else {
        0U
      }
    Limbs(units, _) => if index < units.length() { units[index] } else { 0U }
  }
}

///|
fn gda_coeff_copy_limbs(coeff : GdaCoeff) -> Array[UInt] {
  match coeff {
    Small(value) =>
      if value < gda_coeff_wide_base {
        [value.to_uint()]
      } else {
        [
          (value % gda_coeff_wide_base).to_uint(),
          (value / gda_coeff_wide_base).to_uint(),
        ]
      }
    Limbs(units, _) => units.copy()
  }
}

///|
fn gda_coeff_digits_cached(coeff : GdaCoeff) -> Int {
  match coeff {
    Small(value) => gda_coeff_small_digits(value)
    Limbs(_, digits) => digits
  }
}

///|
fn gda_coeff_is_zero(coeff : GdaCoeff) -> Bool {
  match coeff {
    Small(value) => value == 0UL
    Limbs(_, _) => false
  }
}

///|
fn gda_coeff_small_value(coeff : GdaCoeff) -> UInt64? {
  match coeff {
    GdaCoeff::Small(value) => Some(value)
    GdaCoeff::Limbs(_, _) => None
  }
}

///|
fn gda_coeff_is_odd(coeff : GdaCoeff) -> Bool {
  (gda_coeff_limb_at(coeff, 0) & 0x01U) == 1U
}

///|
fn gda_coeff_matches_unit_repr(coeff : GdaCoeff, value : Int) -> Bool {
  guard value >= 0 && value < gda_coeff_base else {
    abort("gda_coeff_matches_unit_repr expects one coefficient unit")
  }
  gda_coeff_unit_len(coeff) == 1 &&
  gda_coeff_limb_at(coeff, 0) == value.reinterpret_as_uint()
}

///|
fn GdaCoeff::is_zero(self : GdaCoeff) -> Bool {
  gda_coeff_is_zero(self)
}

///|
fn GdaCoeff::to_bigint(self : GdaCoeff) -> BigInt {
  gda_coeff_to_bigint_repr(self)
}

///|
fn GdaCoeff::digits10(self : GdaCoeff) -> Int {
  gda_coeff_digits_cached(self)
}

///|
fn GdaCoeff::to_string(self : GdaCoeff) -> String {
  let mut index = gda_coeff_unit_len(self) - 1
  let result = StringBuilder::new()
  result.write_string(gda_coeff_limb_at(self, index).to_string())
  while index > 0 {
    index -= 1
    let unit = gda_coeff_limb_at(self, index)
    let digits = unit.to_string()
    for _ in 0..<(gda_coeff_dpun - digits.length()) {
      result.write_char('0')
    }
    result.write_string(digits)
  }
  result.to_string()
}

///|
fn gda_coeff_from_bigint(magnitude : BigInt) -> (Array[UInt], Int) {
  guard magnitude >= 0N else {
    abort("gda_coeff_from_bigint expects a non-negative coefficient")
  }
  if magnitude.is_zero() {
    return ([0U], 1)
  }
  let base = BigInt::from_int(gda_coeff_base)
  let units : Array[UInt] = []
  let mut remaining = magnitude
  while !remaining.is_zero() {
    let quotient = remaining / base
    let remainder = remaining - quotient * base
    units.push(remainder.to_int().reinterpret_as_uint())
    remaining = quotient
  }
  (units, gda_coeff_get_digits(units, units.length()))
}

///|
fn gda_coeff_to_bigint(
  units : Array[UInt],
  unit_len? : Int = units.length(),
) -> BigInt {
  guard unit_len >= 1 else {
    abort("gda_coeff_to_bigint expects unit_len >= 1")
  }
  let mut acc = 0N
  let base = BigInt::from_int(gda_coeff_base)
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
fn gda_coeff_from_bigint_repr(magnitude : BigInt) -> GdaCoeff {
  let (units, _) = gda_coeff_from_bigint(magnitude)
  gda_coeff_from_unit_accumulator(units, units.length())
}

///|
fn gda_coeff_to_bigint_repr(coeff : GdaCoeff) -> BigInt {
  match coeff {
    Small(value) => BigInt::from_uint64(value)
    Limbs(units, _) => gda_coeff_to_bigint(units)
  }
}

///|
fn gda_coeff_get_digits(units : Array[UInt], unit_len : Int) -> Int {
  guard unit_len >= 1 else {
    abort("gda_coeff_get_digits expects unit_len >= 1")
  }
  let mut index = unit_len - 1
  let mut digits = (unit_len - 1) * gda_coeff_dpun + 1
  while true {
    let unit = units[index]
    if unit == 0U {
      if digits == 1 {
        break
      }
      digits -= gda_coeff_dpun
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
fn gda_coeff_shift_to_most(
  units : Array[UInt],
  digits : Int,
  shift : Int,
) -> Int {
  guard digits >= 1 else {
    abort("gda_coeff_shift_to_most expects digits >= 1")
  }
  guard shift >= 0 else { abort("gda_coeff_shift_to_most expects shift >= 0") }
  if shift == 0 {
    return digits
  }
  if digits + shift <= gda_coeff_dpun {
    units[0] = (units[0].reinterpret_as_int() * gda_coeff_powers[shift]).reinterpret_as_uint()
    return digits + shift
  }

  let source_units = gda_coeff_d2u(digits)
  let target_units = gda_coeff_d2u(digits + shift)
  gda_coeff_ensure_length(units, target_units)

  let mut next = 0
  let mut source = source_units - 1
  let mut target = source + gda_coeff_d2u(shift)
  let cut = gda_coeff_dpun - gda_coeff_msu_digits(shift)
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
      let quot = units[source].reinterpret_as_int() / gda_coeff_powers[cut]
      let rem = units[source].reinterpret_as_int() -
        quot * gda_coeff_powers[cut]
      next += quot
      if target <= first {
        units[target] = next.reinterpret_as_uint()
      }
      next = rem * gda_coeff_powers[gda_coeff_dpun - cut]
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
fn gda_coeff_shift_to_least(
  units : Array[UInt],
  unit_len : Int,
  shift : Int,
) -> Int {
  guard unit_len >= 1 else {
    abort("gda_coeff_shift_to_least expects unit_len >= 1")
  }
  guard shift >= 0 else { abort("gda_coeff_shift_to_least expects shift >= 0") }
  if shift == 0 {
    return unit_len
  }
  if shift == unit_len * gda_coeff_dpun {
    units[0] = 0U
    return 1
  }

  let mut target = 0
  let cut = gda_coeff_msu_digits(shift)
  if cut == gda_coeff_dpun {
    let mut up = gda_coeff_d2u(shift)
    while up < unit_len {
      units[target] = units[up]
      target += 1
      up += 1
    }
    return target
  }

  let mut up = gda_coeff_d2u(shift - cut)
  let mut count = unit_len * gda_coeff_dpun - shift
  let mut quot = units[up].reinterpret_as_int() / gda_coeff_powers[cut]
  while true {
    units[target] = quot.reinterpret_as_uint()
    count -= gda_coeff_dpun - cut
    if count <= 0 {
      break
    }
    up += 1
    let current = units[up]
    let rem = current.reinterpret_as_int() % gda_coeff_powers[cut]
    quot = current.reinterpret_as_int() / gda_coeff_powers[cut]
    units[target] = units[target] +
      (rem * gda_coeff_powers[gda_coeff_dpun - cut]).reinterpret_as_uint()
    count -= cut
    if count <= 0 {
      break
    }
    target += 1
  }
  target + 1
}

///|
fn gda_coeff_div_pow10_round_info_repr(
  numerator : GdaCoeff,
  shift : Int,
) -> (GdaCoeff, Bool, Int) {
  guard shift >= 0 else {
    abort("gda_coeff_div_pow10_round_info_repr expects shift >= 0")
  }
  if numerator.is_zero() || shift == 0 {
    return (numerator, false, -1)
  }
  let digits = numerator.digits10()
  if shift > digits {
    return (gda_coeff_zero(), true, -1)
  }
  if gda_coeff_small_value(numerator) is Some(value) {
    let divisor = gda_coeff_small_powers10[shift]
    let quotient = value / divisor
    let remainder = value % divisor
    let twice = remainder * 2UL
    return (
      GdaCoeff::Small(quotient),
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
    gda_coeff_zero()
  } else {
    let units = gda_coeff_copy_limbs(numerator)
    let quotient_len = gda_coeff_shift_to_least(
      units,
      gda_coeff_unit_len(numerator),
      shift,
    )
    gda_coeff_from_unit_accumulator(units, quotient_len)
  }
  let leading_position = shift - 1
  let leading_unit = leading_position / gda_coeff_dpun
  let leading_offset = leading_position % gda_coeff_dpun
  let leading_limb = gda_coeff_limb_at(numerator, leading_unit).reinterpret_as_int()
  let leading_digit = leading_limb / gda_coeff_powers[leading_offset] % 10
  let mut lower_nonzero = leading_limb % gda_coeff_powers[leading_offset] != 0
  for index in 0..<leading_unit {
    if gda_coeff_limb_at(numerator, index) != 0U {
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
fn gda_coeff_trim(
  units : Array[UInt],
  digits : Int,
  exponent : Int,
  all? : Bool = true,
  max_drop? : Int = -1,
) -> (Int, Int, Int) {
  guard digits >= 1 else { abort("gda_coeff_trim expects digits >= 1") }
  if (units[0] & 1U) == 1U {
    return (digits, exponent, 0)
  }
  if digits == 1 && units[0] == 0U {
    return (1, 0, 0)
  }

  let mut exp = exponent
  let mut cut = 1
  let mut up = 0
  let mut dropped = 0
  while dropped < digits - 1 {
    let quot = units[up].reinterpret_as_int() / gda_coeff_powers[cut]
    if units[up].reinterpret_as_int() - quot * gda_coeff_powers[cut] != 0 {
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
    if cut > gda_coeff_dpun {
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

  let unit_len = gda_coeff_d2u(digits)
  ignore(gda_coeff_shift_to_least(units, unit_len, dropped))
  (digits - dropped, exponent + dropped, dropped)
}

///|
fn gda_coeff_split_carry_3(carry : Int64) -> (Int, Int64) {
  let base = 1000000000L
  if carry >= 0L {
    ((carry % base).to_int(), carry / base)
  } else {
    let quotient = -((-carry + base - 1L) / base)
    ((carry - quotient * base).to_int(), quotient)
  }
}

///|
fn gda_coeff_unit_add_sub(
  a : Array[UInt],
  alength : Int,
  b : Array[UInt],
  blength : Int,
  bshift : Int,
  c : Array[UInt],
  m : Int,
) -> Int {
  guard alength >= 1 else {
    abort("gda_coeff_unit_add_sub expects alength >= 1")
  }
  guard blength >= 1 else {
    abort("gda_coeff_unit_add_sub expects blength >= 1")
  }
  guard bshift >= 0 else { abort("gda_coeff_unit_add_sub expects bshift >= 0") }

  let mut carry = 0L
  let mut max_c = alength
  let mut min_c = blength
  let mut a_index = 0
  let mut b_index = 0
  let mut c_index = 0

  if bshift != 0 {
    min_c += bshift
    gda_coeff_ensure_length(c, bshift)
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
  gda_coeff_ensure_length(c, max_c + 1)

  while c_index < min_c {
    carry += a[a_index].to_int64()
    a_index += 1
    carry += b[b_index].to_int64() * m.to_int64()
    b_index += 1
    if carry >= 0L && carry < 1000000000L {
      c[c_index] = carry.to_int().reinterpret_as_uint()
      carry = 0L
    } else {
      let (digit, next) = gda_coeff_split_carry_3(carry)
      c[c_index] = digit.reinterpret_as_uint()
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
      let (digit, next) = gda_coeff_split_carry_3(carry)
      c[c_index] = digit.reinterpret_as_uint()
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
    add = gda_coeff_base - 1 + add - c[complement_index].reinterpret_as_int()
    if add <= gda_coeff_base - 1 {
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
fn gda_coeff_shift_power10_repr(coeff : GdaCoeff, shift : Int) -> GdaCoeff {
  guard shift >= 0 else {
    abort("gda_coeff_shift_power10_repr expects a non-negative shift")
  }
  if coeff.is_zero() || shift == 0 {
    return coeff
  }
  if gda_coeff_small_value(coeff) is Some(value) &&
    shift < gda_coeff_small_powers10.length() {
    let multiplier = gda_coeff_small_powers10[shift]
    if value == 0UL || multiplier <= (gda_coeff_small_limit - 1UL) / value {
      return GdaCoeff::Small(value * multiplier)
    }
  }
  let units = gda_coeff_copy_limbs(coeff)
  let shifted_digits = gda_coeff_shift_to_most(units, coeff.digits10(), shift)
  gda_coeff_from_unit_accumulator(units, gda_coeff_d2u(shifted_digits))
}

///|
fn gda_coeff_compare_repr(lhs : GdaCoeff, rhs : GdaCoeff) -> Int {
  let lhs_len = gda_coeff_unit_len(lhs)
  let rhs_len = gda_coeff_unit_len(rhs)
  if lhs_len > rhs_len {
    return 1
  }
  if lhs_len < rhs_len {
    return -1
  }
  let mut index = lhs_len - 1
  while true {
    let lhs_limb = gda_coeff_limb_at(lhs, index)
    let rhs_limb = gda_coeff_limb_at(rhs, index)
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
fn gda_coeff_trim_units(units : Array[UInt], unit_len : Int) -> Int {
  let mut len = unit_len
  while len > 1 && units[len - 1] == 0U {
    len -= 1
  }
  len
}

///|
fn gda_coeff_write_wide_unit(
  units : Array[UInt],
  wide_index : Int,
  value : UInt64,
) -> Unit {
  guard value < gda_coeff_wide_base else {
    abort("decimal coefficient limb exceeds base")
  }
  units[wide_index] = value.to_uint()
}

///|
fn gda_coeff_pack_wide(coeff : GdaCoeff) -> Array[UInt64] {
  let wide_len = gda_coeff_unit_len(coeff)
  let packed = Array::make(wide_len, 0UL)
  for wide_index in 0..<wide_len {
    packed[wide_index] = gda_coeff_limb_at(coeff, wide_index).to_uint64()
  }
  packed
}

///|
fn gda_coeff_from_wide_accumulator(
  wide_units : Array[UInt64],
  wide_len : Int,
) -> GdaCoeff {
  let units = Array::make(Int::max(1, wide_len), 0U)
  for wide_index in 0..<wide_len {
    gda_coeff_write_wide_unit(units, wide_index, wide_units[wide_index])
  }
  gda_coeff_from_unit_accumulator(units, units.length())
}

///|
fn gda_coeff_multiply_units_by_unit(
  units : Array[UInt],
  unit_len : Int,
  multiplier : Int,
) -> (Array[UInt], Int) {
  guard multiplier >= 0 && multiplier < gda_coeff_base else {
    abort("gda_coeff_multiply_units_by_unit expects one coefficient unit")
  }
  if multiplier == 0 {
    return ([0U], 1)
  }
  let result = Array::make(unit_len + 1, 0U)
  let len = gda_coeff_multiply_units_by_unit_into(
    units, unit_len, multiplier, result,
  )
  (result, gda_coeff_trim_units(result, len))
}

///|
fn gda_coeff_multiply_units_by_unit_into(
  units : Array[UInt],
  unit_len : Int,
  multiplier : Int,
  result : Array[UInt],
) -> Int {
  guard multiplier >= 0 && multiplier < gda_coeff_base else {
    abort("gda_coeff_multiply_units_by_unit_into expects one coefficient unit")
  }
  guard result.length() >= unit_len + 1 else {
    abort("gda_coeff_multiply_units_by_unit_into result is too short")
  }
  let mut carry = 0UL
  let mut index = 0
  while index < unit_len {
    let current = units[index].to_uint64() * multiplier.to_uint64() + carry
    result[index] = (current % gda_coeff_wide_base).to_uint()
    carry = current / gda_coeff_wide_base
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
fn gda_coeff_multiply_by_unit_repr(
  coeff : GdaCoeff,
  multiplier : Int,
) -> GdaCoeff {
  guard multiplier >= 0 && multiplier < gda_coeff_base else {
    abort("gda_coeff_multiply_by_unit_repr expects one coefficient unit")
  }
  if coeff.is_zero() || multiplier == 0 {
    return gda_coeff_zero()
  }
  if gda_coeff_small_value(coeff) is Some(value) {
    let multiplier = multiplier.to_uint64()
    if multiplier <= (gda_coeff_small_limit - 1UL) / value {
      return GdaCoeff::Small(value * multiplier)
    }
  }
  let unit_len = gda_coeff_unit_len(coeff)
  let (product, product_len) = gda_coeff_multiply_units_by_unit(
    gda_coeff_copy_limbs(coeff),
    unit_len,
    multiplier,
  )
  gda_coeff_from_unit_accumulator(product, product_len)
}

///|
fn gda_coeff_pow_unit_repr(base : Int, exponent : Int) -> GdaCoeff {
  guard exponent >= 0 else {
    abort("gda_coeff_pow_unit_repr expects a non-negative exponent")
  }
  guard base >= 0 && base < gda_coeff_base else {
    abort("gda_coeff_pow_unit_repr expects one coefficient unit")
  }
  gda_coeff_exact_power_repr(gda_coeff_from_int(base), exponent)
}

///|
fn gda_coeff_exact_power_repr(base : GdaCoeff, exponent : Int) -> GdaCoeff {
  guard exponent >= 0 else {
    abort("gda_coeff_exact_power_repr expects a non-negative exponent")
  }
  if exponent == 0 {
    return gda_coeff_from_int(1)
  }
  let mut result = gda_coeff_from_int(1)
  let mut factor = base
  let mut remaining = exponent
  while remaining > 0 {
    if (remaining & 1) == 1 {
      result = gda_coeff_multiply_repr(result, factor)
    }
    remaining = remaining >> 1
    if remaining > 0 {
      factor = gda_coeff_square_repr(factor)
    }
  }
  result
}

///|
fn gda_coeff_exact_power_if_fits_repr(
  base : GdaCoeff,
  exponent : Int,
  max_digits : Int,
) -> GdaCoeff? {
  guard exponent >= 0 else {
    abort("gda_coeff_exact_power_if_fits_repr expects a non-negative exponent")
  }
  guard max_digits > 0 else {
    abort("gda_coeff_exact_power_if_fits_repr expects max_digits > 0")
  }
  if exponent == 0 {
    return Some(gda_coeff_from_int(1))
  }
  let mut result = gda_coeff_from_int(1)
  let mut factor = base
  let mut remaining = exponent
  if factor.digits10() > max_digits {
    return None
  }
  while remaining > 0 {
    if (remaining & 1) == 1 {
      result = gda_coeff_multiply_repr(result, factor)
      if result.digits10() > max_digits {
        return None
      }
    }
    remaining = remaining >> 1
    if remaining > 0 {
      factor = gda_coeff_square_repr(factor)
      if factor.digits10() > max_digits {
        return None
      }
    }
  }
  Some(result)
}

///|
fn gda_coeff_div_rem_by_unit_repr(
  coeff : GdaCoeff,
  divisor : Int,
) -> (GdaCoeff, Int) {
  guard divisor > 0 && divisor < gda_coeff_base else {
    abort(
      "gda_coeff_div_rem_by_unit_repr expects one positive coefficient unit",
    )
  }
  if coeff.is_zero() {
    return (gda_coeff_zero(), 0)
  }
  let wide_divisor = divisor.to_uint64()
  if gda_coeff_small_value(coeff) is Some(value) {
    return (
      GdaCoeff::Small(value / wide_divisor),
      (value % wide_divisor).to_int(),
    )
  }
  let unit_len = gda_coeff_unit_len(coeff)
  if unit_len == 1 {
    let value = gda_coeff_limb_at(coeff, 0).to_uint64()
    return (
      gda_coeff_from_int((value / wide_divisor).to_int()),
      (value % wide_divisor).to_int(),
    )
  }
  let result = Array::make(unit_len, 0U)
  let mut remainder = 0UL
  let mut index = unit_len - 1
  while true {
    let current = remainder * gda_coeff_wide_base +
      gda_coeff_limb_at(coeff, index).to_uint64()
    result[index] = (current / wide_divisor).to_uint()
    remainder = current % wide_divisor
    if index == 0 {
      break
    }
    index -= 1
  }
  let result_len = gda_coeff_trim_units(result, unit_len)
  (gda_coeff_from_unit_accumulator(result, result_len), remainder.to_int())
}

///|
fn gda_coeff_exact_divide_by_unit_repr(
  coeff : GdaCoeff,
  divisor : Int,
) -> GdaCoeff? {
  let (quotient, remainder) = gda_coeff_div_rem_by_unit_repr(coeff, divisor)
  if remainder == 0 {
    Some(quotient)
  } else {
    None
  }
}

///|
fn gda_coeff_count_factor_unit_repr(
  coeff : GdaCoeff,
  factor : Int,
) -> (GdaCoeff, Int) {
  guard !coeff.is_zero() else {
    abort("gda_coeff_count_factor_unit_repr expects a non-zero coefficient")
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
      match gda_coeff_exact_divide_by_unit_repr(value, batch_factor) {
        Some(next) => {
          value = next
          count += batch_count
        }
        None => break
      }
    }
  }
  while true {
    match gda_coeff_exact_divide_by_unit_repr(value, factor) {
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
fn gda_coeff_remove_factor_unit_repr(
  coeff : GdaCoeff,
  factor : Int,
) -> GdaCoeff {
  gda_coeff_count_factor_unit_repr(coeff, factor).0
}

///|
fn gda_coeff_from_unit_accumulator(
  units : Array[UInt],
  unit_len : Int,
) -> GdaCoeff {
  guard unit_len >= 1 else {
    abort("gda_coeff_from_unit_accumulator expects unit_len >= 1")
  }
  guard unit_len <= units.length() else {
    abort("gda_coeff_from_unit_accumulator unit_len exceeds buffer")
  }
  for index in 0..<unit_len {
    guard units[index] < 1_000_000_000U else {
      abort("gda_coeff_from_unit_accumulator limb exceeds base")
    }
  }
  let unit_len = gda_coeff_trim_units(units, unit_len)
  while units.length() > unit_len {
    ignore(units.pop())
  }
  if unit_len <= 2 {
    let high = if unit_len == 2 {
      units[1].to_uint64() * gda_coeff_wide_base
    } else {
      0UL
    }
    let value = units[0].to_uint64() + high
    if value < gda_coeff_small_limit {
      Small(value)
    } else {
      Limbs(units, gda_coeff_get_digits(units, unit_len))
    }
  } else {
    Limbs(units, gda_coeff_get_digits(units, unit_len))
  }
}

///|
fn gda_coeff_magnitude_add_repr(lhs : GdaCoeff, rhs : GdaCoeff) -> GdaCoeff {
  if lhs.is_zero() {
    return rhs
  }
  if rhs.is_zero() {
    return lhs
  }
  if gda_coeff_small_value(lhs) is Some(left) &&
    gda_coeff_small_value(rhs) is Some(right) {
    let sum = left + right
    if sum < gda_coeff_small_limit {
      return GdaCoeff::Small(sum)
    }
  }
  if gda_coeff_unit_len(lhs) == 1 && gda_coeff_unit_len(rhs) == 1 {
    let sum = gda_coeff_limb_at(lhs, 0).to_uint64() +
      gda_coeff_limb_at(rhs, 0).to_uint64()
    if sum < gda_coeff_wide_base {
      return gda_coeff_from_int(sum.to_int())
    }
    return gda_coeff_from_unit_accumulator(
      [
        (sum % gda_coeff_wide_base).to_uint(),
        (sum / gda_coeff_wide_base).to_uint(),
      ],
      2,
    )
  }
  let lhs_len = gda_coeff_unit_len(lhs)
  let rhs_len = gda_coeff_unit_len(rhs)
  let wide_len = Int::max(lhs_len, rhs_len)
  let result = Array::make(wide_len + 1, 0U)
  let mut carry = 0UL
  for wide_index in 0..<wide_len {
    let sum = gda_coeff_limb_at(lhs, wide_index).to_uint64() +
      gda_coeff_limb_at(rhs, wide_index).to_uint64() +
      carry
    if sum >= gda_coeff_wide_base {
      gda_coeff_write_wide_unit(result, wide_index, sum - gda_coeff_wide_base)
      carry = 1UL
    } else {
      gda_coeff_write_wide_unit(result, wide_index, sum)
      carry = 0UL
    }
  }
  if carry != 0UL {
    gda_coeff_write_wide_unit(result, wide_len, carry)
  }
  gda_coeff_from_unit_accumulator(result, result.length())
}

///|
fn gda_coeff_magnitude_sub_repr(lhs : GdaCoeff, rhs : GdaCoeff) -> GdaCoeff {
  guard gda_coeff_compare_repr(lhs, rhs) >= 0 else {
    abort("gda_coeff_magnitude_sub_repr expects lhs >= rhs")
  }
  if rhs.is_zero() {
    return lhs
  }
  if gda_coeff_small_value(lhs) is Some(left) &&
    gda_coeff_small_value(rhs) is Some(right) {
    return GdaCoeff::Small(left - right)
  }
  let lhs_len = gda_coeff_unit_len(lhs)
  let wide_len = lhs_len
  let result = Array::make(wide_len, 0U)
  let mut borrow = 0UL
  for wide_index in 0..<wide_len {
    let lhs_unit = gda_coeff_limb_at(lhs, wide_index).to_uint64()
    let rhs_unit = gda_coeff_limb_at(rhs, wide_index).to_uint64()
    let subtrahend = rhs_unit + borrow
    if lhs_unit < subtrahend {
      gda_coeff_write_wide_unit(
        result,
        wide_index,
        lhs_unit + gda_coeff_wide_base - subtrahend,
      )
      borrow = 1UL
    } else {
      gda_coeff_write_wide_unit(result, wide_index, lhs_unit - subtrahend)
      borrow = 0UL
    }
  }
  guard borrow == 0UL else { abort("gda_coeff_magnitude_sub_repr underflowed") }
  gda_coeff_from_unit_accumulator(result, result.length())
}

///|
fn gda_coeff_signed_add_repr(
  lhs_negative : Bool,
  lhs : GdaCoeff,
  rhs_negative : Bool,
  rhs : GdaCoeff,
) -> (Bool, GdaCoeff) {
  if lhs.is_zero() {
    return if rhs.is_zero() {
      (false, gda_coeff_zero())
    } else {
      (rhs_negative, rhs)
    }
  }
  if rhs.is_zero() {
    return (lhs_negative, lhs)
  }
  if lhs_negative == rhs_negative {
    return (lhs_negative, gda_coeff_magnitude_add_repr(lhs, rhs))
  }
  match gda_coeff_compare_repr(lhs, rhs) {
    0 => (false, gda_coeff_zero())
    1 => (lhs_negative, gda_coeff_magnitude_sub_repr(lhs, rhs))
    _ => (rhs_negative, gda_coeff_magnitude_sub_repr(rhs, lhs))
  }
}

///|
fn gda_coeff_signed_compare_repr(
  lhs_negative : Bool,
  lhs : GdaCoeff,
  rhs_negative : Bool,
  rhs : GdaCoeff,
) -> Int {
  let lhs_negative = lhs_negative && !lhs.is_zero()
  let rhs_negative = rhs_negative && !rhs.is_zero()
  if lhs_negative != rhs_negative {
    return if lhs_negative { -1 } else { 1 }
  }
  let magnitude = gda_coeff_compare_repr(lhs, rhs)
  if lhs_negative {
    -magnitude
  } else {
    magnitude
  }
}

///|
fn gda_coeff_signed_compare_int_repr(
  negative : Bool,
  magnitude : GdaCoeff,
  rhs : Int,
) -> Int {
  gda_coeff_signed_compare_repr(
    negative,
    magnitude,
    rhs < 0,
    gda_coeff_from_int_magnitude(rhs),
  )
}

///|
fn gda_coeff_magnitude_add_unit(coeff : GdaCoeff, addend : Int) -> GdaCoeff {
  guard addend >= 0 && addend < gda_coeff_base else {
    abort("gda_coeff_magnitude_add_unit expects one coefficient unit")
  }
  if addend == 0 {
    return coeff
  }
  if gda_coeff_small_value(coeff) is Some(value) {
    let sum = value + addend.to_uint64()
    if sum < gda_coeff_small_limit {
      return GdaCoeff::Small(sum)
    }
  }
  let coeff_len = gda_coeff_unit_len(coeff)
  let result = gda_coeff_copy_limbs(coeff)
  gda_coeff_ensure_length(result, coeff_len + 1)
  let addend_units = [addend.reinterpret_as_uint()]
  let len = gda_coeff_unit_add_sub(
    result,
    coeff_len,
    addend_units,
    1,
    0,
    result,
    1,
  )
  guard len > 0 else { abort("gda_coeff_magnitude_add_unit underflowed") }
  gda_coeff_from_unit_accumulator(result, len)
}

///|
fn gda_coeff_magnitude_sub_unit(coeff : GdaCoeff, subtrahend : Int) -> GdaCoeff {
  guard subtrahend >= 0 && subtrahend < gda_coeff_base else {
    abort("gda_coeff_magnitude_sub_unit expects one coefficient unit")
  }
  if subtrahend == 0 {
    return coeff
  }
  if gda_coeff_small_value(coeff) is Some(value) {
    return GdaCoeff::Small(value - subtrahend.to_uint64())
  }
  let coeff_len = gda_coeff_unit_len(coeff)
  let result = gda_coeff_copy_limbs(coeff)
  let rhs_units = [subtrahend.reinterpret_as_uint()]
  let len = gda_coeff_unit_add_sub(
    result,
    coeff_len,
    rhs_units,
    1,
    0,
    result,
    -1,
  )
  guard len >= 0 else { abort("gda_coeff_magnitude_sub_unit underflowed") }
  if len == 0 {
    gda_coeff_zero()
  } else {
    gda_coeff_from_unit_accumulator(result, len)
  }
}

///|
fn gda_coeff_signed_step_unit_repr(
  negative : Bool,
  magnitude : GdaCoeff,
  toward_positive : Bool,
) -> (Bool, GdaCoeff) {
  let one = gda_coeff_from_int(1)
  if toward_positive {
    if negative {
      if magnitude.is_zero() {
        (false, one)
      } else if gda_coeff_compare_repr(magnitude, one) == 0 {
        (false, gda_coeff_zero())
      } else {
        (true, gda_coeff_magnitude_sub_unit(magnitude, 1))
      }
    } else {
      (false, gda_coeff_magnitude_add_unit(magnitude, 1))
    }
  } else if negative {
    (true, gda_coeff_magnitude_add_unit(magnitude, 1))
  } else if magnitude.is_zero() {
    (true, one)
  } else if gda_coeff_compare_repr(magnitude, one) == 0 {
    (false, gda_coeff_zero())
  } else {
    (false, gda_coeff_magnitude_sub_unit(magnitude, 1))
  }
}

///|
fn gda_coeff_wide_trim_units(units : Array[UInt64], unit_len : Int) -> Int {
  let mut len = unit_len
  while len > 1 && units[len - 1] == 0UL {
    len -= 1
  }
  len
}

///|
fn gda_coeff_wide_multiply_coeff_by_unit_into(
  coeff : GdaCoeff,
  multiplier : UInt64,
  result : Array[UInt64],
) -> Int {
  let unit_len = gda_coeff_unit_len(coeff)
  let mut carry = 0UL
  for index in 0..<unit_len {
    let current = gda_coeff_limb_at(coeff, index).to_uint64() * multiplier +
      carry
    result[index] = current % gda_coeff_wide_base
    carry = current / gda_coeff_wide_base
  }
  result[unit_len] = carry
  if carry == 0UL {
    unit_len
  } else {
    unit_len + 1
  }
}

///|
fn gda_coeff_div_rem_knuth_repr(
  numerator : GdaCoeff,
  denominator : GdaCoeff,
) -> (GdaCoeff, GdaCoeff) {
  let remainder_len = gda_coeff_unit_len(numerator)
  let denominator_len = gda_coeff_unit_len(denominator)
  if gda_coeff_compare_repr(numerator, denominator) < 0 {
    return (gda_coeff_zero(), numerator)
  }
  if denominator_len == 1 {
    let (quotient, residue) = gda_coeff_div_rem_by_unit_repr(
      numerator,
      gda_coeff_limb_at(denominator, 0).reinterpret_as_int(),
    )
    return (quotient, gda_coeff_from_int(residue))
  }
  let max_shift = remainder_len - denominator_len
  let quotient = Array::make(max_shift + 1, 0UL)
  let normalized_denominator = Array::make(denominator_len + 1, 0UL)
  let normalized_numerator = Array::make(remainder_len + 1, 0UL)
  let normalization = gda_coeff_wide_base /
    (gda_coeff_limb_at(denominator, denominator_len - 1).to_uint64() + 1UL)
  ignore(
    gda_coeff_wide_multiply_coeff_by_unit_into(
      denominator, normalization, normalized_denominator,
    ),
  )
  ignore(
    gda_coeff_wide_multiply_coeff_by_unit_into(
      numerator, normalization, normalized_numerator,
    ),
  )
  let top = normalized_denominator[denominator_len - 1]
  let second_top = normalized_denominator[denominator_len - 2]
  let mut shift = max_shift
  while true {
    let upper = normalized_numerator[shift + denominator_len]
    let next = normalized_numerator[shift + denominator_len - 1]
    let mut quotient_digit = (upper * gda_coeff_wide_base + next) / top
    let mut remainder_digit = (upper * gda_coeff_wide_base + next) % top
    if quotient_digit >= gda_coeff_wide_base {
      let excess = quotient_digit - (gda_coeff_wide_base - 1UL)
      quotient_digit = gda_coeff_wide_base - 1UL
      remainder_digit += excess * top
    }
    while remainder_digit < gda_coeff_wide_base &&
          quotient_digit * second_top >
          gda_coeff_wide_base * remainder_digit +
          normalized_numerator[shift + denominator_len - 2] {
      quotient_digit -= 1UL
      remainder_digit += top
      if remainder_digit >= gda_coeff_wide_base {
        break
      }
    }
    let mut carry = 0UL
    let mut borrow = 0UL
    for index in 0..<denominator_len {
      let product = normalized_denominator[index] * quotient_digit + carry
      let product_digit = product % gda_coeff_wide_base
      carry = product / gda_coeff_wide_base
      let subtrahend = product_digit + borrow
      let target = shift + index
      if normalized_numerator[target] < subtrahend {
        normalized_numerator[target] = normalized_numerator[target] +
          gda_coeff_wide_base -
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
        gda_coeff_wide_base -
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
        if sum >= gda_coeff_wide_base {
          normalized_numerator[target] = sum - gda_coeff_wide_base
          add_carry = 1UL
        } else {
          normalized_numerator[target] = sum
          add_carry = 0UL
        }
      }
      normalized_numerator[top_target] = normalized_numerator[top_target] +
        add_carry
      if normalized_numerator[top_target] >= gda_coeff_wide_base {
        normalized_numerator[top_target] -= gda_coeff_wide_base
      }
    }
    quotient[shift] = quotient_digit
    if shift == 0 {
      break
    }
    shift -= 1
  }
  let remainder_units = Array::make(denominator_len, 0UL)
  let mut residue = 0UL
  let mut index = denominator_len - 1
  while true {
    let current = residue * gda_coeff_wide_base + normalized_numerator[index]
    remainder_units[index] = current / normalization
    residue = current % normalization
    if index == 0 {
      break
    }
    index -= 1
  }
  let quotient_len = gda_coeff_wide_trim_units(quotient, quotient.length())
  let remainder_len = gda_coeff_wide_trim_units(
    remainder_units,
    remainder_units.length(),
  )
  if residue != 0UL {
    let mut corrected_quotient = gda_coeff_from_wide_accumulator(
      quotient, quotient_len,
    )
    let mut product = gda_coeff_multiply_repr(corrected_quotient, denominator)
    let mut corrections = 0
    while gda_coeff_compare_repr(product, numerator) > 0 {
      guard !corrected_quotient.is_zero() else {
        abort("Knuth quotient correction underflowed")
      }
      corrected_quotient = gda_coeff_magnitude_sub_unit(corrected_quotient, 1)
      product = gda_coeff_magnitude_sub_repr(product, denominator)
      corrections += 1
      guard corrections <= denominator_len * 2 + 8 else {
        abort("Knuth quotient correction exceeded guard")
      }
    }
    let mut corrected_remainder = gda_coeff_magnitude_sub_repr(
      numerator, product,
    )
    while gda_coeff_compare_repr(corrected_remainder, denominator) >= 0 {
      corrected_quotient = gda_coeff_magnitude_add_unit(corrected_quotient, 1)
      corrected_remainder = gda_coeff_magnitude_sub_repr(
        corrected_remainder, denominator,
      )
      corrections += 1
      guard corrections <= denominator_len * 2 + 8 else {
        abort("Knuth remainder correction exceeded guard")
      }
    }
    return (corrected_quotient, corrected_remainder)
  }
  (
    gda_coeff_from_wide_accumulator(quotient, quotient_len),
    gda_coeff_from_wide_accumulator(remainder_units, remainder_len),
  )
}

///|
fn gda_coeff_div_rem_repr(
  numerator : GdaCoeff,
  denominator : GdaCoeff,
) -> (GdaCoeff, GdaCoeff) {
  guard !denominator.is_zero() else {
    abort("gda_coeff_div_rem_repr expects denominator > 0")
  }
  if numerator.is_zero() {
    return (gda_coeff_zero(), gda_coeff_zero())
  }
  if gda_coeff_small_value(numerator) is Some(left) &&
    gda_coeff_small_value(denominator) is Some(right) {
    return (GdaCoeff::Small(left / right), GdaCoeff::Small(left % right))
  }
  if gda_coeff_compare_repr(numerator, denominator) < 0 {
    return (gda_coeff_zero(), numerator)
  }
  let denom_len = gda_coeff_unit_len(denominator)
  if denom_len == 1 {
    let (quotient, residue) = gda_coeff_div_rem_by_unit_repr(
      numerator,
      gda_coeff_limb_at(denominator, 0).reinterpret_as_int(),
    )
    return (quotient, gda_coeff_from_int(residue))
  }
  match gda_coeff_division_algorithm(numerator, denominator) {
    Word => abort("word division was handled before dispatch")
    Newton => gda_coeff_div_rem_newton(numerator, denominator)
    BurnikelZiegler =>
      gda_coeff_div_rem_burnikel_ziegler(numerator, denominator)
    Knuth => gda_coeff_div_rem_knuth_repr(numerator, denominator)
  }
}

///|
fn gda_coeff_mul_schoolbook(lhs : GdaCoeff, rhs : GdaCoeff) -> GdaCoeff {
  if lhs.is_zero() || rhs.is_zero() {
    return gda_coeff_zero()
  }
  let lhs_len = gda_coeff_unit_len(lhs)
  let rhs_len = gda_coeff_unit_len(rhs)
  let lhs_wide_len = lhs_len
  let rhs_wide_len = rhs_len
  if Int::min(lhs_wide_len, rhs_wide_len) <= 18 {
    let result = Array::make(lhs_wide_len + rhs_wide_len + 1, 0U)
    let columns = lhs_wide_len + rhs_wide_len - 1
    let mut carry = 0UL
    for column in 0..<columns {
      let lhs_start = Int::max(0, column - (rhs_wide_len - 1))
      let lhs_end = Int::min(lhs_wide_len - 1, column)
      let mut current = carry
      for lhs_index in lhs_start..<=lhs_end {
        let rhs_index = column - lhs_index
        current += gda_coeff_limb_at(lhs, lhs_index).to_uint64() *
          gda_coeff_limb_at(rhs, rhs_index).to_uint64()
      }
      gda_coeff_write_wide_unit(result, column, current % gda_coeff_wide_base)
      carry = current / gda_coeff_wide_base
    }
    let mut column = columns
    while carry != 0UL {
      gda_coeff_write_wide_unit(result, column, carry % gda_coeff_wide_base)
      carry = carry / gda_coeff_wide_base
      column += 1
    }
    return gda_coeff_from_unit_accumulator(result, result.length())
  }
  let lhs_wide = gda_coeff_pack_wide(lhs)
  let rhs_wide = gda_coeff_pack_wide(rhs)
  let acc = Array::make(lhs_wide_len + rhs_wide_len + 1, 0UL)
  for rhs_index in 0..<rhs_wide.length() {
    let multiplier = rhs_wide[rhs_index]
    let mut carry = 0UL
    for lhs_index in 0..<lhs_wide.length() {
      let acc_index = lhs_index + rhs_index
      let current = acc[acc_index] + lhs_wide[lhs_index] * multiplier + carry
      acc[acc_index] = current % gda_coeff_wide_base
      carry = current / gda_coeff_wide_base
    }
    let mut acc_index = lhs_wide.length() + rhs_index
    while carry != 0UL {
      let current = acc[acc_index] + carry
      acc[acc_index] = current % gda_coeff_wide_base
      carry = current / gda_coeff_wide_base
      acc_index += 1
    }
  }
  let mut acc_len = acc.length()
  while acc_len > 1 && acc[acc_len - 1] == 0UL {
    acc_len -= 1
  }
  gda_coeff_from_wide_accumulator(acc, acc_len)
}

///|
fn gda_coeff_compare_scaled_repr(
  lhs : GdaCoeff,
  rhs : GdaCoeff,
  exp : Int,
) -> Int {
  guard exp >= 0 else {
    abort("gda_coeff_compare_scaled_repr expects a non-negative exponent")
  }
  let alength = gda_coeff_unit_len(lhs)
  let blength = gda_coeff_unit_len(rhs)
  if exp == 0 {
    return gda_coeff_compare_repr(lhs, rhs)
  }
  let expunit_shift = exp / gda_coeff_dpun
  let exprem = exp % gda_coeff_dpun
  let multiplier = gda_coeff_powers[exprem].to_uint64()
  let need = Int::max(alength, expunit_shift + blength + 1)
  let mut multiply_carry = 0UL
  let mut borrow = 0UL
  let mut nonzero = false
  for index in 0..<need {
    let lhs_unit = if index < alength {
      gda_coeff_limb_at(lhs, index).to_uint64()
    } else {
      0UL
    }
    let rhs_index = index - expunit_shift
    let rhs_unit = if rhs_index >= 0 && rhs_index < blength {
      let product = gda_coeff_limb_at(rhs, rhs_index).to_uint64() * multiplier +
        multiply_carry
      multiply_carry = product / gda_coeff_wide_base
      product % gda_coeff_wide_base
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
      lhs_unit + gda_coeff_wide_base - subtrahend
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
fn remove_factor10_repr(coeff : GdaCoeff, exp : Int) -> (GdaCoeff, Int) {
  if coeff.is_zero() {
    return (gda_coeff_zero(), 0)
  }
  if gda_coeff_limb_at(coeff, 0).reinterpret_as_int() % 10 != 0 {
    return (coeff, exp)
  }
  let units = gda_coeff_copy_limbs(coeff)
  let (trimmed_digits, exponent, _) = gda_coeff_trim(
    units,
    coeff.digits10(),
    exp,
    all=true,
  )
  (
    gda_coeff_from_unit_accumulator(units, gda_coeff_d2u(trimmed_digits)),
    exponent,
  )
}

///|
fn exact_divide_by_power_of_ten_repr(
  coeff : GdaCoeff,
  shift : Int,
) -> GdaCoeff? {
  guard shift >= 0 else {
    abort("exact_divide_by_power_of_ten_repr expects shift >= 0")
  }
  if coeff.is_zero() {
    return Some(gda_coeff_zero())
  }
  if shift == 0 {
    return Some(coeff)
  }
  guard shift < coeff.digits10() else { return None }
  let units = gda_coeff_copy_limbs(coeff)
  let mut cut = 1
  let mut up = 0
  let mut checked = 0
  while checked < shift {
    let quot = units[up].reinterpret_as_int() / gda_coeff_powers[cut]
    guard units[up].reinterpret_as_int() - quot * gda_coeff_powers[cut] == 0 else {
      return None
    }
    cut += 1
    if cut > gda_coeff_dpun {
      up += 1
      cut = 1
    }
    checked += 1
  }
  let trimmed_units = gda_coeff_shift_to_least(
    units,
    gda_coeff_unit_len(coeff),
    shift,
  )
  Some(gda_coeff_from_unit_accumulator(units, trimmed_units))
}

///|
fn trim_trailing_decimal_zeros_repr(
  coeff : GdaCoeff,
  exp : Int,
  max_drop? : Int = -1,
) -> (GdaCoeff, Int, Int) {
  if coeff.is_zero() {
    return (gda_coeff_zero(), 0, 0)
  }
  if max_drop == 0 || gda_coeff_limb_at(coeff, 0).reinterpret_as_int() % 10 != 0 {
    return (coeff, exp, 0)
  }
  let units = gda_coeff_copy_limbs(coeff)
  let (trimmed_digits, exponent, dropped) = gda_coeff_trim(
    units,
    coeff.digits10(),
    exp,
    all=true,
    max_drop~,
  )
  (
    gda_coeff_from_unit_accumulator(units, gda_coeff_d2u(trimmed_digits)),
    exponent,
    dropped,
  )
}
