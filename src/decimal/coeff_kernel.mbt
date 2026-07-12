///|
// Package-local decNumber-style decimal coefficient helpers.
//
// These are the coefficient-kernel routines we use inside the decimal
// package.  They are intentionally non-`pub`: callers outside the package
// should continue to work with Decimal values rather than raw coefficient
// storage.

///|
priv struct DecCoeff {
  units : Array[Int]
  digits : Int
}

///|
let dec_coeff_dpun = 3

///|
let dec_coeff_base = 1000

///|
let dec_coeff_powers : Array[Int] = [1, 10, 100, 1000]

///|
let dec_coeff_wide_base = 1000000000UL

///|
fn dec_coeff_d2u(digits : Int) -> Int {
  (digits + dec_coeff_dpun - 1) / dec_coeff_dpun
}

///|
fn dec_coeff_msu_digits(digits : Int) -> Int {
  let rem = digits % dec_coeff_dpun
  if rem == 0 {
    dec_coeff_dpun
  } else {
    rem
  }
}

///|
fn dec_coeff_ensure_length(units : Array[Int], needed : Int) -> Unit {
  while units.length() < needed {
    units.push(0)
  }
}

///|
fn dec_coeff_zero() -> DecCoeff {
  { units: [0], digits: 1 }
}

///|
fn dec_coeff_from_int(value : Int) -> DecCoeff {
  guard value >= 0 && value < dec_coeff_base else {
    abort("dec_coeff_from_int expects one non-negative coefficient unit")
  }
  { units: [value], digits: dec_coeff_get_digits([value], 1) }
}

///|
fn dec_coeff_from_nonnegative_int(value : Int) -> DecCoeff {
  guard value >= 0 else {
    abort("dec_coeff_from_nonnegative_int expects a non-negative integer")
  }
  if value == 0 {
    return dec_coeff_zero()
  }
  let units : Array[Int] = []
  let mut remaining = value
  while remaining > 0 {
    units.push(remaining % dec_coeff_base)
    remaining = remaining / dec_coeff_base
  }
  { units, digits: dec_coeff_get_digits(units, units.length()) }
}

///|
// Isomorphic to GDA decNumberFromInt32/decNumberFromUInt32: form the unsigned
// magnitude without negating the minimum Int, then decompose it in DECDPUN
// units. See libdecnumber/decNumber.c lines 345-374 in the GCC mirror.
fn dec_coeff_from_int_magnitude(value : Int) -> DecCoeff {
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
fn dec_coeff_power10_repr(shift : Int) -> DecCoeff {
  guard shift >= 0 else {
    abort("dec_coeff_power10_repr expects a non-negative shift")
  }
  dec_coeff_shift_power10_repr(dec_coeff_from_int(1), shift)
}

///|
fn dec_coeff_unit_len(coeff : DecCoeff) -> Int {
  dec_coeff_d2u(coeff.digits)
}

///|
fn dec_coeff_is_zero(coeff : DecCoeff) -> Bool {
  coeff.digits == 1 && coeff.units[0] == 0
}

///|
fn dec_coeff_is_odd(coeff : DecCoeff) -> Bool {
  (coeff.units[0] & 0x01) == 1
}

///|
fn dec_coeff_matches_unit_repr(coeff : DecCoeff, value : Int) -> Bool {
  guard value >= 0 && value < dec_coeff_base else {
    abort("dec_coeff_matches_unit_repr expects one coefficient unit")
  }
  dec_coeff_unit_len(coeff) == 1 && coeff.units[0] == value
}

///|
fn DecCoeff::is_zero(self : DecCoeff) -> Bool {
  dec_coeff_is_zero(self)
}

///|
fn DecCoeff::to_bigint(self : DecCoeff) -> BigInt {
  dec_coeff_to_bigint_repr(self)
}

///|
fn DecCoeff::digits10(self : DecCoeff) -> Int {
  self.digits
}

///|
fn DecCoeff::to_string(self : DecCoeff) -> String {
  let mut index = dec_coeff_unit_len(self) - 1
  let mut result = self.units[index].to_string()
  while index > 0 {
    index -= 1
    let unit = self.units[index]
    let digits = unit.to_string()
    result = result +
      (if unit < 10 {
        "00" + digits
      } else if unit < 100 {
        "0" + digits
      } else {
        digits
      })
  }
  result
}

///|
fn DecCoeff::from_bigint(magnitude : BigInt) -> DecCoeff {
  dec_coeff_from_bigint_repr(magnitude)
}

///|
fn dec_coeff_from_bigint(magnitude : BigInt) -> (Array[Int], Int) {
  guard magnitude >= 0N else {
    abort("dec_coeff_from_bigint expects a non-negative coefficient")
  }
  if magnitude.is_zero() {
    return ([0], 1)
  }
  let base = BigInt::from_int(dec_coeff_base)
  let units : Array[Int] = []
  let mut remaining = magnitude
  while !remaining.is_zero() {
    let quotient = remaining / base
    let remainder = remaining - quotient * base
    units.push(remainder.to_int())
    remaining = quotient
  }
  (units, dec_coeff_get_digits(units, units.length()))
}

///|
fn dec_coeff_to_bigint(
  units : Array[Int],
  unit_len? : Int = units.length(),
) -> BigInt {
  guard unit_len >= 1 else {
    abort("dec_coeff_to_bigint expects unit_len >= 1")
  }
  let mut acc = 0N
  let base = BigInt::from_int(dec_coeff_base)
  let mut index = unit_len - 1
  while true {
    acc = acc * base + BigInt::from_int(units[index])
    if index == 0 {
      break
    }
    index -= 1
  }
  acc
}

///|
fn dec_coeff_from_bigint_repr(magnitude : BigInt) -> DecCoeff {
  let (units, digits) = dec_coeff_from_bigint(magnitude)
  { units, digits }
}

///|
fn dec_coeff_to_bigint_repr(coeff : DecCoeff) -> BigInt {
  dec_coeff_to_bigint(coeff.units, unit_len=dec_coeff_unit_len(coeff))
}

///|
fn dec_coeff_get_digits(units : Array[Int], unit_len : Int) -> Int {
  guard unit_len >= 1 else {
    abort("dec_coeff_get_digits expects unit_len >= 1")
  }
  let mut index = unit_len - 1
  let mut digits = (unit_len - 1) * dec_coeff_dpun + 1
  while true {
    let unit = units[index]
    if unit == 0 {
      if digits == 1 {
        break
      }
      digits -= dec_coeff_dpun
    } else {
      if unit >= 10 {
        digits += 1
      }
      if unit >= 100 {
        digits += 1
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
  units : Array[Int],
  digits : Int,
  shift : Int,
) -> Int {
  guard digits >= 1 else {
    abort("dec_coeff_shift_to_most expects digits >= 1")
  }
  guard shift >= 0 else { abort("dec_coeff_shift_to_most expects shift >= 0") }
  if shift == 0 {
    return digits
  }
  if digits + shift <= dec_coeff_dpun {
    units[0] = units[0] * dec_coeff_powers[shift]
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
      let quot = units[source] / dec_coeff_powers[cut]
      let rem = units[source] - quot * dec_coeff_powers[cut]
      next += quot
      if target <= first {
        units[target] = next
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
    units[target] = next
    next = 0
    target -= 1
  }
  digits + shift
}

///|
fn dec_coeff_shift_to_least(
  units : Array[Int],
  unit_len : Int,
  shift : Int,
) -> Int {
  guard unit_len >= 1 else {
    abort("dec_coeff_shift_to_least expects unit_len >= 1")
  }
  guard shift >= 0 else { abort("dec_coeff_shift_to_least expects shift >= 0") }
  if shift == 0 {
    return unit_len
  }
  if shift == unit_len * dec_coeff_dpun {
    units[0] = 0
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
  let mut quot = units[up] / dec_coeff_powers[cut]
  while true {
    units[target] = quot
    count -= dec_coeff_dpun - cut
    if count <= 0 {
      break
    }
    up += 1
    let current = units[up]
    let rem = current % dec_coeff_powers[cut]
    quot = current / dec_coeff_powers[cut]
    units[target] = units[target] + rem * dec_coeff_powers[dec_coeff_dpun - cut]
    count -= cut
    if count <= 0 {
      break
    }
    target += 1
  }
  target + 1
}

///|
fn dec_coeff_trim(
  units : Array[Int],
  digits : Int,
  exponent : Int,
  all? : Bool = true,
  max_drop? : Int = -1,
) -> (Int, Int, Int) {
  guard digits >= 1 else { abort("dec_coeff_trim expects digits >= 1") }
  if (units[0] & 1) == 1 {
    return (digits, exponent, 0)
  }
  if digits == 1 && units[0] == 0 {
    return (1, 0, 0)
  }

  let mut exp = exponent
  let mut cut = 1
  let mut up = 0
  let mut dropped = 0
  while dropped < digits - 1 {
    let quot = units[up] / dec_coeff_powers[cut]
    if units[up] - quot * dec_coeff_powers[cut] != 0 {
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
fn dec_coeff_split_carry_3(carry : Int) -> (Int, Int) {
  if carry >= 0 {
    let est = ((carry >> 3) * 16777) >> 21
    let rem = carry - est * dec_coeff_base
    if rem < dec_coeff_base {
      (rem, est)
    } else {
      (rem - dec_coeff_base, est + 1)
    }
  } else {
    let adjusted = carry + dec_coeff_base * dec_coeff_base
    let est = ((adjusted >> 3) * 16777) >> 21
    let rem = adjusted - est * dec_coeff_base
    let next = est - dec_coeff_base
    if rem < dec_coeff_base {
      (rem, next)
    } else {
      (rem - dec_coeff_base, next + 1)
    }
  }
}

///|
fn dec_coeff_unit_add_sub(
  a : Array[Int],
  alength : Int,
  b : Array[Int],
  blength : Int,
  bshift : Int,
  c : Array[Int],
  m : Int,
) -> Int {
  guard alength >= 1 else {
    abort("dec_coeff_unit_add_sub expects alength >= 1")
  }
  guard blength >= 1 else {
    abort("dec_coeff_unit_add_sub expects blength >= 1")
  }
  guard bshift >= 0 else { abort("dec_coeff_unit_add_sub expects bshift >= 0") }

  let mut carry = 0
  let mut max_c = alength
  let mut min_c = blength
  let mut a_index = 0
  let mut b_index = 0
  let mut c_index = 0

  if bshift != 0 {
    min_c += bshift
    dec_coeff_ensure_length(c, bshift)
    while c_index < bshift {
      c[c_index] = if a_index < alength { a[a_index] } else { 0 }
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
    carry += a[a_index]
    a_index += 1
    carry += b[b_index] * m
    b_index += 1
    if carry >= 0 && carry <= dec_coeff_base - 1 {
      c[c_index] = carry
      carry = 0
    } else {
      let (digit, next) = dec_coeff_split_carry_3(carry)
      c[c_index] = digit
      carry = next
    }
    c_index += 1
  }

  while c_index < max_c {
    if a_index < alength {
      carry += a[a_index]
      a_index += 1
    } else {
      carry += b[b_index] * m
      b_index += 1
    }
    if carry >= 0 && carry <= dec_coeff_base - 1 {
      c[c_index] = carry
      carry = 0
    } else {
      let (digit, next) = dec_coeff_split_carry_3(carry)
      c[c_index] = digit
      carry = next
    }
    c_index += 1
  }

  if carry == 0 {
    return c_index
  }
  if carry > 0 {
    c[c_index] = carry
    return c_index + 1
  }

  let mut add = 1
  let mut complement_index = 0
  while complement_index < max_c {
    add = dec_coeff_base - 1 + add - c[complement_index]
    if add <= dec_coeff_base - 1 {
      c[complement_index] = add
      add = 0
    } else {
      c[complement_index] = 0
      add = 1
    }
    complement_index += 1
  }
  let mut written = max_c
  if add - carry - 1 != 0 {
    c[written] = add - carry - 1
    written += 1
  }
  -written
}

///|
fn dec_coeff_shift_power10_repr(coeff : DecCoeff, shift : Int) -> DecCoeff {
  guard shift >= 0 else {
    abort("dec_coeff_shift_power10_repr expects a non-negative shift")
  }
  if coeff.is_zero() || shift == 0 {
    return coeff
  }
  let units = coeff.units.copy()
  let shifted_digits = dec_coeff_shift_to_most(units, coeff.digits, shift)
  { units, digits: shifted_digits }
}

///|
fn dec_coeff_compare_repr(lhs : DecCoeff, rhs : DecCoeff) -> Int {
  dec_coeff_compare_unit_arrays(
    lhs.units,
    dec_coeff_unit_len(lhs),
    rhs.units,
    dec_coeff_unit_len(rhs),
  )
}

///|
fn dec_coeff_trim_units(units : Array[Int], unit_len : Int) -> Int {
  let mut len = unit_len
  while len > 1 && units[len - 1] == 0 {
    len -= 1
  }
  len
}

///|
fn dec_coeff_compare_unit_arrays(
  lhs : Array[Int],
  lhs_len : Int,
  rhs : Array[Int],
  rhs_len : Int,
) -> Int {
  let lhs_len = dec_coeff_trim_units(lhs, lhs_len)
  let rhs_len = dec_coeff_trim_units(rhs, rhs_len)
  if lhs_len > rhs_len {
    return 1
  }
  if lhs_len < rhs_len {
    return -1
  }
  let mut index = lhs_len - 1
  while true {
    if lhs[index] > rhs[index] {
      return 1
    }
    if lhs[index] < rhs[index] {
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
fn dec_coeff_compare_shifted(
  lhs : Array[Int],
  lhs_len : Int,
  rhs : Array[Int],
  rhs_len : Int,
  rhs_shift : Int,
) -> Int {
  let lhs_len = dec_coeff_trim_units(lhs, lhs_len)
  let rhs_len = dec_coeff_trim_units(rhs, rhs_len)
  let rhs_total = if rhs_len == 1 && rhs[0] == 0 {
    1
  } else {
    rhs_len + rhs_shift
  }
  if lhs_len > rhs_total {
    return 1
  }
  if lhs_len < rhs_total {
    return -1
  }
  let mut index = lhs_len - 1
  while true {
    let rhs_unit = if index >= rhs_shift && index < rhs_shift + rhs_len {
      rhs[index - rhs_shift]
    } else {
      0
    }
    if lhs[index] > rhs_unit {
      return 1
    }
    if lhs[index] < rhs_unit {
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
fn dec_coeff_wide_unit_at(
  units : Array[Int],
  unit_len : Int,
  wide_index : Int,
) -> UInt64 {
  let base_index = wide_index * 3
  let mut value = 0UL
  if base_index < unit_len {
    value = units[base_index].to_uint64()
  }
  if base_index + 1 < unit_len {
    value += units[base_index + 1].to_uint64() * 1000UL
  }
  if base_index + 2 < unit_len {
    value += units[base_index + 2].to_uint64() * 1000000UL
  }
  value
}

///|
fn dec_coeff_write_wide_unit(
  units : Array[Int],
  wide_index : Int,
  value : UInt64,
) -> Unit {
  let base_index = wide_index * 3
  units[base_index] = (value % 1000UL).to_int()
  let upper = value / 1000UL
  units[base_index + 1] = (upper % 1000UL).to_int()
  units[base_index + 2] = (upper / 1000UL).to_int()
}

///|
fn dec_coeff_pack_wide(units : Array[Int], unit_len : Int) -> Array[UInt64] {
  let wide_len = (unit_len + 2) / 3
  let packed = Array::make(wide_len, 0UL)
  for wide_index in 0..<wide_len {
    packed[wide_index] = dec_coeff_wide_unit_at(units, unit_len, wide_index)
  }
  packed
}

///|
fn dec_coeff_from_wide_accumulator(
  wide_units : Array[UInt64],
  wide_len : Int,
) -> DecCoeff {
  let units = Array::make(Int::max(1, wide_len * 3), 0)
  for wide_index in 0..<wide_len {
    dec_coeff_write_wide_unit(units, wide_index, wide_units[wide_index])
  }
  dec_coeff_from_unit_accumulator(units, units.length())
}

///|
fn dec_coeff_multiply_units_by_unit(
  units : Array[Int],
  unit_len : Int,
  multiplier : Int,
) -> (Array[Int], Int) {
  guard multiplier >= 0 && multiplier < dec_coeff_base else {
    abort("dec_coeff_multiply_units_by_unit expects one coefficient unit")
  }
  if multiplier == 0 {
    return ([0], 1)
  }
  let result = Array::make(unit_len + 1, 0)
  let len = dec_coeff_multiply_units_by_unit_into(
    units, unit_len, multiplier, result,
  )
  (result, dec_coeff_trim_units(result, len))
}

///|
fn dec_coeff_multiply_units_by_unit_into(
  units : Array[Int],
  unit_len : Int,
  multiplier : Int,
  result : Array[Int],
) -> Int {
  guard multiplier >= 0 && multiplier < dec_coeff_base else {
    abort("dec_coeff_multiply_units_by_unit_into expects one coefficient unit")
  }
  guard result.length() >= unit_len + 1 else {
    abort("dec_coeff_multiply_units_by_unit_into result is too short")
  }
  let mut carry = 0
  let mut index = 0
  while index < unit_len {
    carry += units[index] * multiplier
    let (digit, next) = dec_coeff_split_carry_3(carry)
    result[index] = digit
    carry = next
    index += 1
  }
  result[index] = carry
  if carry == 0 {
    unit_len
  } else {
    unit_len + 1
  }
}

///|
fn dec_coeff_multiply_by_unit_repr(
  coeff : DecCoeff,
  multiplier : Int,
) -> DecCoeff {
  guard multiplier >= 0 && multiplier < dec_coeff_base else {
    abort("dec_coeff_multiply_by_unit_repr expects one coefficient unit")
  }
  if coeff.is_zero() || multiplier == 0 {
    return dec_coeff_zero()
  }
  let unit_len = dec_coeff_unit_len(coeff)
  let (product, product_len) = dec_coeff_multiply_units_by_unit(
    coeff.units,
    unit_len,
    multiplier,
  )
  { units: product, digits: dec_coeff_get_digits(product, product_len) }
}

///|
fn dec_coeff_pow_unit_repr(base : Int, exponent : Int) -> DecCoeff {
  guard exponent >= 0 else {
    abort("dec_coeff_pow_unit_repr expects a non-negative exponent")
  }
  guard base >= 0 && base < dec_coeff_base else {
    abort("dec_coeff_pow_unit_repr expects one coefficient unit")
  }
  let mut result = dec_coeff_from_int(1)
  let mut index = 0
  while index < exponent {
    result = dec_coeff_multiply_by_unit_repr(result, base)
    index += 1
  }
  result
}

///|
fn dec_coeff_exact_power_repr(base : DecCoeff, exponent : Int) -> DecCoeff {
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
      factor = dec_coeff_multiply_repr(factor, factor)
    }
  }
  result
}

///|
fn dec_coeff_exact_power_if_fits_repr(
  base : DecCoeff,
  exponent : Int,
  max_digits : Int,
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
      factor = dec_coeff_multiply_repr(factor, factor)
      if factor.digits10() > max_digits {
        return None
      }
    }
  }
  Some(result)
}

///|
fn dec_coeff_div_rem_by_unit_repr(
  coeff : DecCoeff,
  divisor : Int,
) -> (DecCoeff, Int) {
  guard divisor > 0 && divisor < dec_coeff_base else {
    abort(
      "dec_coeff_div_rem_by_unit_repr expects one positive coefficient unit",
    )
  }
  if coeff.is_zero() {
    return (dec_coeff_zero(), 0)
  }
  let unit_len = dec_coeff_unit_len(coeff)
  let result : Array[Int] = []
  let mut pad = 0
  while pad < unit_len {
    result.push(0)
    pad += 1
  }
  let mut remainder = 0
  let mut index = unit_len - 1
  while true {
    let current = remainder * dec_coeff_base + coeff.units[index]
    result[index] = current / divisor
    remainder = current % divisor
    if index == 0 {
      break
    }
    index -= 1
  }
  let result_len = dec_coeff_trim_units(result, unit_len)
  (
    { units: result, digits: dec_coeff_get_digits(result, result_len) },
    remainder,
  )
}

///|
fn dec_coeff_exact_divide_by_unit_repr(
  coeff : DecCoeff,
  divisor : Int,
) -> DecCoeff? {
  let (quotient, remainder) = dec_coeff_div_rem_by_unit_repr(coeff, divisor)
  if remainder == 0 {
    Some(quotient)
  } else {
    None
  }
}

///|
fn dec_coeff_count_factor_unit_repr(
  coeff : DecCoeff,
  factor : Int,
) -> (DecCoeff, Int) {
  guard !coeff.is_zero() else {
    abort("dec_coeff_count_factor_unit_repr expects a non-zero coefficient")
  }
  let mut value = coeff
  let mut count = 0
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
  factor : Int,
) -> DecCoeff {
  dec_coeff_count_factor_unit_repr(coeff, factor).0
}

///|
fn dec_coeff_gcd_repr(lhs : DecCoeff, rhs : DecCoeff) -> DecCoeff {
  let mut x = lhs
  let mut y = rhs
  while !y.is_zero() {
    let (_, remainder) = dec_coeff_div_rem_repr(x, y)
    x = y
    y = remainder
  }
  if x.is_zero() {
    dec_coeff_from_int(1)
  } else {
    x
  }
}

///|
fn dec_coeff_from_unit_accumulator(
  units : Array[Int],
  unit_len : Int,
) -> DecCoeff {
  guard unit_len >= 1 else {
    abort("dec_coeff_from_unit_accumulator expects unit_len >= 1")
  }
  let unit_len = dec_coeff_trim_units(units, unit_len)
  while units.length() > unit_len {
    ignore(units.pop())
  }
  { units, digits: dec_coeff_get_digits(units, unit_len) }
}

///|
fn dec_coeff_magnitude_add_repr(lhs : DecCoeff, rhs : DecCoeff) -> DecCoeff {
  if lhs.is_zero() {
    return rhs
  }
  if rhs.is_zero() {
    return lhs
  }
  let lhs_len = dec_coeff_unit_len(lhs)
  let rhs_len = dec_coeff_unit_len(rhs)
  let wide_len = (Int::max(lhs_len, rhs_len) + 2) / 3
  let result = Array::make((wide_len + 1) * 3, 0)
  let mut carry = 0UL
  for wide_index in 0..<wide_len {
    let sum = dec_coeff_wide_unit_at(lhs.units, lhs_len, wide_index) +
      dec_coeff_wide_unit_at(rhs.units, rhs_len, wide_index) +
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
fn dec_coeff_magnitude_sub_repr(lhs : DecCoeff, rhs : DecCoeff) -> DecCoeff {
  guard dec_coeff_compare_repr(lhs, rhs) >= 0 else {
    abort("dec_coeff_magnitude_sub_repr expects lhs >= rhs")
  }
  if rhs.is_zero() {
    return lhs
  }
  let lhs_len = dec_coeff_unit_len(lhs)
  let rhs_len = dec_coeff_unit_len(rhs)
  let wide_len = (lhs_len + 2) / 3
  let result = Array::make(wide_len * 3, 0)
  let mut borrow = 0UL
  for wide_index in 0..<wide_len {
    let lhs_unit = dec_coeff_wide_unit_at(lhs.units, lhs_len, wide_index)
    let rhs_unit = dec_coeff_wide_unit_at(rhs.units, rhs_len, wide_index)
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
fn dec_coeff_signed_add_repr(
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
) -> Int {
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
fn dec_coeff_signed_compare_int_repr(
  negative : Bool,
  magnitude : DecCoeff,
  rhs : Int,
) -> Int {
  dec_coeff_signed_compare_repr(
    negative,
    magnitude,
    rhs < 0,
    dec_coeff_from_int_magnitude(rhs),
  )
}

///|
fn dec_coeff_magnitude_add_unit(coeff : DecCoeff, addend : Int) -> DecCoeff {
  guard addend >= 0 && addend < dec_coeff_base else {
    abort("dec_coeff_magnitude_add_unit expects one coefficient unit")
  }
  if addend == 0 {
    return coeff
  }
  let result = coeff.units.copy()
  dec_coeff_ensure_length(result, dec_coeff_unit_len(coeff) + 1)
  let addend_units = [addend]
  let len = dec_coeff_unit_add_sub(
    coeff.units,
    dec_coeff_unit_len(coeff),
    addend_units,
    1,
    0,
    result,
    1,
  )
  guard len > 0 else { abort("dec_coeff_magnitude_add_unit underflowed") }
  { units: result, digits: dec_coeff_get_digits(result, len) }
}

///|
fn dec_coeff_magnitude_sub_unit(coeff : DecCoeff, subtrahend : Int) -> DecCoeff {
  guard subtrahend >= 0 && subtrahend < dec_coeff_base else {
    abort("dec_coeff_magnitude_sub_unit expects one coefficient unit")
  }
  if subtrahend == 0 {
    return coeff
  }
  let result = coeff.units.copy()
  let rhs_units = [subtrahend]
  let len = dec_coeff_unit_add_sub(
    coeff.units,
    dec_coeff_unit_len(coeff),
    rhs_units,
    1,
    0,
    result,
    -1,
  )
  guard len >= 0 else { abort("dec_coeff_magnitude_sub_unit underflowed") }
  if len == 0 {
    dec_coeff_zero()
  } else {
    { units: result, digits: dec_coeff_get_digits(result, len) }
  }
}

///|
fn dec_coeff_signed_step_unit_repr(
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
fn dec_coeff_subtract_shifted_in_place(
  lhs : Array[Int],
  lhs_len : Int,
  rhs : Array[Int],
  rhs_len : Int,
  rhs_shift : Int,
) -> Int {
  guard rhs_len + rhs_shift <= lhs_len else {
    abort("dec_coeff_subtract_shifted_in_place rhs exceeds lhs")
  }
  let mut borrow = 0
  let mut index = 0
  while index < rhs_len {
    let target = rhs_shift + index
    let difference = lhs[target] - rhs[index] - borrow
    if difference < 0 {
      lhs[target] = difference + dec_coeff_base
      borrow = 1
    } else {
      lhs[target] = difference
      borrow = 0
    }
    index += 1
  }
  let mut target = rhs_shift + rhs_len
  while borrow != 0 && target < lhs_len {
    let difference = lhs[target] - borrow
    if difference < 0 {
      lhs[target] = difference + dec_coeff_base
      borrow = 1
    } else {
      lhs[target] = difference
      borrow = 0
    }
    target += 1
  }
  guard borrow == 0 else {
    abort("dec_coeff_subtract_shifted_in_place underflowed")
  }
  dec_coeff_trim_units(lhs, lhs_len)
}

///|
fn dec_coeff_trial_compare(
  rhs : Array[Int],
  rhs_len : Int,
  multiplier : Int,
  shift : Int,
  remainder : Array[Int],
  remainder_len : Int,
  product : Array[Int],
) -> Int {
  let product_len = dec_coeff_multiply_units_by_unit_into(
    rhs, rhs_len, multiplier, product,
  )
  dec_coeff_compare_shifted(
    remainder, remainder_len, product, product_len, shift,
  )
}

///|
fn dec_coeff_best_unit_multiplier(
  rhs : Array[Int],
  rhs_len : Int,
  shift : Int,
  remainder : Array[Int],
  remainder_len : Int,
  product : Array[Int],
) -> Int {
  let upper_index = shift + rhs_len
  let upper_unit = if upper_index < remainder_len {
    remainder[upper_index]
  } else {
    0
  }
  let lower_unit = remainder[upper_index - 1]
  let numerator_head = upper_unit * dec_coeff_base + lower_unit
  let upper_bound = Int::min(
    dec_coeff_base - 1,
    numerator_head / rhs[rhs_len - 1],
  )
  if dec_coeff_trial_compare(
      rhs, rhs_len, upper_bound, shift, remainder, remainder_len, product,
    ) >=
    0 {
    return upper_bound
  }
  let mut lo = 0
  let mut hi = upper_bound - 1
  let mut best = 0
  while lo <= hi {
    let mid = (lo + hi) / 2
    let cmp = dec_coeff_trial_compare(
      rhs, rhs_len, mid, shift, remainder, remainder_len, product,
    )
    if cmp >= 0 {
      best = mid
      lo = mid + 1
    } else {
      hi = mid - 1
    }
  }
  best
}

///|
fn dec_coeff_wide_trim_units(units : Array[UInt64], unit_len : Int) -> Int {
  let mut len = unit_len
  while len > 1 && units[len - 1] == 0UL {
    len -= 1
  }
  len
}

///|
fn dec_coeff_wide_compare_unit_arrays(
  lhs : Array[UInt64],
  lhs_len : Int,
  rhs : Array[UInt64],
  rhs_len : Int,
) -> Int {
  let lhs_len = dec_coeff_wide_trim_units(lhs, lhs_len)
  let rhs_len = dec_coeff_wide_trim_units(rhs, rhs_len)
  if lhs_len > rhs_len {
    return 1
  }
  if lhs_len < rhs_len {
    return -1
  }
  let mut index = lhs_len - 1
  while true {
    if lhs[index] > rhs[index] {
      return 1
    }
    if lhs[index] < rhs[index] {
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
fn dec_coeff_wide_compare_shifted(
  lhs : Array[UInt64],
  lhs_len : Int,
  rhs : Array[UInt64],
  rhs_len : Int,
  rhs_shift : Int,
) -> Int {
  let lhs_len = dec_coeff_wide_trim_units(lhs, lhs_len)
  let rhs_len = dec_coeff_wide_trim_units(rhs, rhs_len)
  let rhs_total = rhs_len + rhs_shift
  if lhs_len > rhs_total {
    return 1
  }
  if lhs_len < rhs_total {
    return -1
  }
  let mut index = lhs_len - 1
  while true {
    let rhs_unit = if index >= rhs_shift && index < rhs_shift + rhs_len {
      rhs[index - rhs_shift]
    } else {
      0UL
    }
    if lhs[index] > rhs_unit {
      return 1
    }
    if lhs[index] < rhs_unit {
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
fn dec_coeff_wide_multiply_by_unit_into(
  units : Array[UInt64],
  unit_len : Int,
  multiplier : UInt64,
  result : Array[UInt64],
) -> Int {
  let mut carry = 0UL
  for index in 0..<unit_len {
    let current = units[index] * multiplier + carry
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
fn dec_coeff_wide_subtract_shifted_in_place(
  lhs : Array[UInt64],
  lhs_len : Int,
  rhs : Array[UInt64],
  rhs_len : Int,
  rhs_shift : Int,
) -> Int {
  guard rhs_len + rhs_shift <= lhs_len else {
    abort("dec_coeff_wide_subtract_shifted_in_place rhs exceeds lhs")
  }
  let mut borrow = 0UL
  for index in 0..<rhs_len {
    let target = rhs_shift + index
    let subtrahend = rhs[index] + borrow
    if lhs[target] < subtrahend {
      lhs[target] = lhs[target] + dec_coeff_wide_base - subtrahend
      borrow = 1UL
    } else {
      lhs[target] = lhs[target] - subtrahend
      borrow = 0UL
    }
  }
  let mut target = rhs_shift + rhs_len
  while borrow != 0UL && target < lhs_len {
    if lhs[target] == 0UL {
      lhs[target] = dec_coeff_wide_base - 1UL
    } else {
      lhs[target] = lhs[target] - 1UL
      borrow = 0UL
    }
    target += 1
  }
  guard borrow == 0UL else {
    abort("dec_coeff_wide_subtract_shifted_in_place underflowed")
  }
  dec_coeff_wide_trim_units(lhs, lhs_len)
}

///|
fn dec_coeff_wide_trial_compare(
  rhs : Array[UInt64],
  rhs_len : Int,
  multiplier : UInt64,
  shift : Int,
  remainder : Array[UInt64],
  remainder_len : Int,
  product : Array[UInt64],
) -> Int {
  let product_len = dec_coeff_wide_multiply_by_unit_into(
    rhs, rhs_len, multiplier, product,
  )
  dec_coeff_wide_compare_shifted(
    remainder, remainder_len, product, product_len, shift,
  )
}

///|
fn dec_coeff_wide_best_multiplier(
  rhs : Array[UInt64],
  rhs_len : Int,
  shift : Int,
  remainder : Array[UInt64],
  remainder_len : Int,
  product : Array[UInt64],
) -> UInt64 {
  let upper_index = shift + rhs_len
  let upper_unit = if upper_index < remainder_len {
    remainder[upper_index]
  } else {
    0UL
  }
  let lower_unit = remainder[upper_index - 1]
  let numerator_head = upper_unit * dec_coeff_wide_base + lower_unit
  let estimated = numerator_head / rhs[rhs_len - 1]
  let upper_bound = if estimated < dec_coeff_wide_base {
    estimated
  } else {
    dec_coeff_wide_base - 1UL
  }
  if dec_coeff_wide_trial_compare(
      rhs, rhs_len, upper_bound, shift, remainder, remainder_len, product,
    ) >=
    0 {
    return upper_bound
  }
  let mut lo = 0
  let mut hi = upper_bound.to_int() - 1
  let mut best = 0
  while lo <= hi {
    let mid = (lo + hi) / 2
    let cmp = dec_coeff_wide_trial_compare(
      rhs,
      rhs_len,
      mid.to_uint64(),
      shift,
      remainder,
      remainder_len,
      product,
    )
    if cmp >= 0 {
      best = mid
      lo = mid + 1
    } else {
      hi = mid - 1
    }
  }
  best.to_uint64()
}

///|
fn dec_coeff_div_rem_wide_repr(
  numerator : DecCoeff,
  denominator : DecCoeff,
) -> (DecCoeff, DecCoeff) {
  let numerator_units = dec_coeff_pack_wide(
    numerator.units,
    dec_coeff_unit_len(numerator),
  )
  let denominator_units = dec_coeff_pack_wide(
    denominator.units,
    dec_coeff_unit_len(denominator),
  )
  let mut remainder_len = numerator_units.length()
  let denominator_len = denominator_units.length()
  if dec_coeff_wide_compare_unit_arrays(
      numerator_units, remainder_len, denominator_units, denominator_len,
    ) <
    0 {
    return (dec_coeff_zero(), numerator)
  }
  if denominator_len == 1 {
    let quotient = Array::make(remainder_len, 0UL)
    let divisor = denominator_units[0]
    let mut residue = 0UL
    let mut index = remainder_len - 1
    while true {
      let current = residue * dec_coeff_wide_base + numerator_units[index]
      quotient[index] = current / divisor
      residue = current % divisor
      if index == 0 {
        break
      }
      index -= 1
    }
    let quotient_len = dec_coeff_wide_trim_units(quotient, quotient.length())
    return (
      dec_coeff_from_wide_accumulator(quotient, quotient_len),
      dec_coeff_from_wide_accumulator([residue], 1),
    )
  }
  let max_shift = remainder_len - denominator_len
  let quotient = Array::make(max_shift + 1, 0UL)
  let product = Array::make(denominator_len + 1, 0UL)
  let mut shift = max_shift
  while true {
    if dec_coeff_wide_compare_shifted(
        numerator_units, remainder_len, denominator_units, denominator_len, shift,
      ) >=
      0 {
      let multiplier = dec_coeff_wide_best_multiplier(
        denominator_units, denominator_len, shift, numerator_units, remainder_len,
        product,
      )
      if multiplier != 0UL {
        quotient[shift] = multiplier
        let product_len = dec_coeff_wide_multiply_by_unit_into(
          denominator_units, denominator_len, multiplier, product,
        )
        remainder_len = dec_coeff_wide_subtract_shifted_in_place(
          numerator_units, remainder_len, product, product_len, shift,
        )
      }
    }
    if shift == 0 {
      break
    }
    shift -= 1
  }
  let quotient_len = dec_coeff_wide_trim_units(quotient, quotient.length())
  let remainder_len = dec_coeff_wide_trim_units(numerator_units, remainder_len)
  (
    dec_coeff_from_wide_accumulator(quotient, quotient_len),
    dec_coeff_from_wide_accumulator(numerator_units, remainder_len),
  )
}

///|
fn dec_coeff_div_rem_repr(
  numerator : DecCoeff,
  denominator : DecCoeff,
) -> (DecCoeff, DecCoeff) {
  guard !denominator.is_zero() else {
    abort("dec_coeff_div_rem_repr expects denominator > 0")
  }
  if numerator.is_zero() {
    return (dec_coeff_zero(), dec_coeff_zero())
  }
  let remainder = numerator.units.copy()
  let denom = denominator.units
  let mut remainder_len = dec_coeff_unit_len(numerator)
  let denom_len = dec_coeff_unit_len(denominator)
  if denom_len == 1 {
    let (quotient, residue) = dec_coeff_div_rem_by_unit_repr(
      numerator,
      denom[0],
    )
    return (quotient, dec_coeff_from_int(residue))
  }
  if denom_len >= 4 {
    return dec_coeff_div_rem_wide_repr(numerator, denominator)
  }
  if dec_coeff_compare_unit_arrays(remainder, remainder_len, denom, denom_len) <
    0 {
    return (dec_coeff_zero(), numerator)
  }
  let max_shift = remainder_len - denom_len
  let quotient = Array::make(max_shift + 1, 0)
  let product = Array::make(denom_len + 1, 0)
  let mut shift = max_shift
  while true {
    if dec_coeff_compare_shifted(
        remainder, remainder_len, denom, denom_len, shift,
      ) >=
      0 {
      let multiplier = dec_coeff_best_unit_multiplier(
        denom, denom_len, shift, remainder, remainder_len, product,
      )
      if multiplier > 0 {
        quotient[shift] = multiplier
        let product_len = dec_coeff_multiply_units_by_unit_into(
          denom, denom_len, multiplier, product,
        )
        remainder_len = dec_coeff_subtract_shifted_in_place(
          remainder, remainder_len, product, product_len, shift,
        )
      }
    }
    if shift == 0 {
      break
    }
    shift -= 1
  }
  let quotient_len = dec_coeff_trim_units(quotient, quotient.length())
  let remainder_len = dec_coeff_trim_units(remainder, remainder_len)
  (
    { units: quotient, digits: dec_coeff_get_digits(quotient, quotient_len) },
    { units: remainder, digits: dec_coeff_get_digits(remainder, remainder_len) },
  )
}

///|
fn dec_coeff_multiply_repr(lhs : DecCoeff, rhs : DecCoeff) -> DecCoeff {
  if lhs.is_zero() || rhs.is_zero() {
    return dec_coeff_zero()
  }
  let lhs_len = dec_coeff_unit_len(lhs)
  let rhs_len = dec_coeff_unit_len(rhs)
  let lhs_wide_len = (lhs_len + 2) / 3
  let rhs_wide_len = (rhs_len + 2) / 3
  if lhs_wide_len <= 4 && rhs_wide_len <= 4 {
    let result = Array::make((lhs_wide_len + rhs_wide_len + 1) * 3, 0)
    let columns = lhs_wide_len + rhs_wide_len - 1
    let mut carry = 0UL
    for column in 0..<columns {
      let lhs_start = Int::max(0, column - (rhs_wide_len - 1))
      let lhs_end = Int::min(lhs_wide_len - 1, column)
      let mut current = carry
      for lhs_index in lhs_start..<=lhs_end {
        let rhs_index = column - lhs_index
        current += dec_coeff_wide_unit_at(lhs.units, lhs_len, lhs_index) *
          dec_coeff_wide_unit_at(rhs.units, rhs_len, rhs_index)
      }
      dec_coeff_write_wide_unit(result, column, current % dec_coeff_wide_base)
      carry = current / dec_coeff_wide_base
    }
    let mut column = columns
    while carry != 0UL {
      dec_coeff_write_wide_unit(result, column, carry % dec_coeff_wide_base)
      carry = carry / dec_coeff_wide_base
      column += 1
    }
    return dec_coeff_from_unit_accumulator(result, result.length())
  }
  let lhs_wide = dec_coeff_pack_wide(lhs.units, lhs_len)
  let rhs_wide = dec_coeff_pack_wide(rhs.units, rhs_len)
  let acc = Array::make(lhs_wide_len + rhs_wide_len + 1, 0UL)
  for rhs_index in 0..<rhs_wide.length() {
    let multiplier = rhs_wide[rhs_index]
    let mut carry = 0UL
    for lhs_index in 0..<lhs_wide.length() {
      let acc_index = lhs_index + rhs_index
      let current = acc[acc_index] + lhs_wide[lhs_index] * multiplier + carry
      acc[acc_index] = current % dec_coeff_wide_base
      carry = current / dec_coeff_wide_base
    }
    let mut acc_index = lhs_wide.length() + rhs_index
    while carry != 0UL {
      let current = acc[acc_index] + carry
      acc[acc_index] = current % dec_coeff_wide_base
      carry = current / dec_coeff_wide_base
      acc_index += 1
    }
  }
  let mut acc_len = acc.length()
  while acc_len > 1 && acc[acc_len - 1] == 0UL {
    acc_len -= 1
  }
  dec_coeff_from_wide_accumulator(acc, acc_len)
}

///|
fn dec_coeff_compare_scaled_repr(
  lhs : DecCoeff,
  rhs : DecCoeff,
  exp : Int,
) -> Int {
  guard exp >= 0 else {
    abort("dec_coeff_compare_scaled_repr expects a non-negative exponent")
  }
  let alength = dec_coeff_unit_len(lhs)
  let blength = dec_coeff_unit_len(rhs)
  if exp == 0 {
    return dec_coeff_compare_repr(lhs, rhs)
  }

  let exp_units = dec_coeff_d2u(exp)
  if alength > blength + exp_units {
    return 1
  }
  if alength + 1 < blength + exp_units {
    return -1
  }

  let need = Int::max(alength, blength + exp_units) + 2
  let acc : Array[Int] = []
  let mut index = 0
  while index < need {
    acc.push(0)
    index += 1
  }
  let expunit_shift = exp / dec_coeff_dpun
  let exprem = exp % dec_coeff_dpun
  let multiplier = dec_coeff_powers[exprem]
  let accunits = dec_coeff_unit_add_sub(
    lhs.units,
    alength,
    rhs.units,
    blength,
    expunit_shift,
    acc,
    -multiplier,
  )
  if accunits < 0 {
    return -1
  }
  let mut first = 0
  while first < accunits - 1 && acc[first] == 0 {
    first += 1
  }
  if acc[first] == 0 {
    0
  } else {
    1
  }
}

///|
fn remove_factor10_repr(coeff : DecCoeff, exp : Int) -> (DecCoeff, Int) {
  if coeff.is_zero() {
    return (dec_coeff_zero(), 0)
  }
  let units = coeff.units.copy()
  let (trimmed_digits, exponent, _) = dec_coeff_trim(
    units,
    coeff.digits,
    exp,
    all=true,
  )
  ({ units, digits: trimmed_digits }, exponent)
}

///|
fn exact_divide_by_power_of_ten_repr(
  coeff : DecCoeff,
  shift : Int,
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
  guard shift < coeff.digits else { return None }
  let units = coeff.units.copy()
  let mut cut = 1
  let mut up = 0
  let mut checked = 0
  while checked < shift {
    let quot = units[up] / dec_coeff_powers[cut]
    guard units[up] - quot * dec_coeff_powers[cut] == 0 else { return None }
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
  Some({ units, digits: dec_coeff_get_digits(units, trimmed_units) })
}

///|
fn trim_trailing_decimal_zeros_repr(
  coeff : DecCoeff,
  exp : Int,
  max_drop? : Int = -1,
) -> (DecCoeff, Int, Int) {
  if coeff.is_zero() {
    return (dec_coeff_zero(), 0, 0)
  }
  let units = coeff.units.copy()
  let (trimmed_digits, exponent, dropped) = dec_coeff_trim(
    units,
    coeff.digits,
    exp,
    all=true,
    max_drop~,
  )
  ({ units, digits: trimmed_digits }, exponent, dropped)
}
