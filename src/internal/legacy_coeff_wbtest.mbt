///|
/// Non-negative binary coefficient with an inline UInt64 fast path.
pub enum Coeff {
  Small(UInt64)
  Medium(UInt64, UInt64)
  Large(Array[UInt])
} derive(Eq)

///|
/// Signed coefficient with a canonical non-negative zero.
pub struct SignedCoeff {
  priv negative : Bool
  priv magnitude : Coeff
} derive(Eq)

///|
let coeff_unit_bits : Int = 30

///|
let coeff_base : UInt64 = 1UL << coeff_unit_bits

///|
let coeff_mask : UInt64 = coeff_base - 1UL

///|
fn coeff_small_bits(value : UInt64) -> Int {
  let mut bits = 0
  let mut current = value
  while current != 0UL {
    bits += 1
    current = current >> 1
  }
  bits
}

///|
fn coeff_small_units(value : UInt64) -> Array[UInt] {
  if value == 0UL {
    return [0U]
  }
  let units : Array[UInt] = []
  let mut remaining = value
  while remaining != 0UL {
    units.push((remaining & coeff_mask).to_uint())
    remaining = remaining >> coeff_unit_bits
  }
  units
}

///|
fn coeff_medium(high : UInt64, low : UInt64) -> Coeff {
  if high == 0UL {
    Small(low)
  } else {
    Medium(high, low)
  }
}

///|
fn coeff_medium_units(high : UInt64, low : UInt64) -> Array[UInt] {
  let units : Array[UInt] = []
  let mut high = high
  let mut low = low
  while high != 0UL || low != 0UL {
    units.push((low & coeff_mask).to_uint())
    low = (low >> coeff_unit_bits) | (high << (64 - coeff_unit_bits))
    high = high >> coeff_unit_bits
  }
  if units.length() == 0 {
    units.push(0U)
  }
  units
}

///|
fn coeff_units(value : Coeff) -> Array[UInt] {
  match value {
    Small(value) => coeff_small_units(value)
    Medium(high, low) => coeff_medium_units(high, low)
    Large(units) => units
  }
}

///|
fn coeff_make(units : Array[UInt]) -> Coeff {
  while units.length() > 1 && units[units.length() - 1] == 0U {
    ignore(units.pop())
  }
  if units.length() == 0 {
    return Small(0UL)
  }
  let bits = (units.length() - 1) * coeff_unit_bits +
    coeff_small_bits(units[units.length() - 1].to_uint64())
  if bits <= 64 {
    let mut value = 0UL
    let mut index = units.length() - 1
    while true {
      value = (value << coeff_unit_bits) | units[index].to_uint64()
      if index == 0 {
        break
      }
      index -= 1
    }
    Small(value)
  } else if bits <= 128 {
    let mut high = 0UL
    let mut low = 0UL
    for index in 0..<units.length() {
      let unit = units[index].to_uint64()
      let shift = index * coeff_unit_bits
      if shift < 64 {
        low = low | (unit << shift)
        if shift > 64 - coeff_unit_bits {
          high = high | (unit >> (64 - shift))
        }
      } else {
        high = high | (unit << (shift - 64))
      }
    }
    coeff_medium(high, low)
  } else {
    Large(units)
  }
}

///|
pub fn coeff_zero() -> Coeff {
  Small(0UL)
}

///|
pub fn coeff_one() -> Coeff {
  Small(1UL)
}

///|
pub fn coeff_from_uint64(value : UInt64) -> Coeff {
  Small(value)
}

///|
pub fn coeff_from_nonnegative_int(value : Int) -> Coeff {
  guard value >= 0 else {
    abort("coeff_from_nonnegative_int expects a non-negative value")
  }
  Small(value.to_uint64())
}

///|
pub fn coeff_from_nonnegative_bigint(value : BigInt) -> Coeff {
  guard value >= 0N else {
    abort("coeff_from_nonnegative_bigint expects a non-negative value")
  }
  let bits = value.bit_length()
  if bits <= 64 {
    return Small(value.to_uint64())
  }
  if bits <= 128 {
    return Medium((value >> 64).to_uint64(), value.to_uint64())
  }
  let base = BigInt::from_uint64(coeff_base)
  let units : Array[UInt] = []
  let mut remaining = value
  while !remaining.is_zero() {
    let quotient = remaining / base
    units.push((remaining - quotient * base).to_uint64().to_uint())
    remaining = quotient
  }
  coeff_make(units)
}

///|
pub fn coeff_to_bigint(value : Coeff) -> BigInt {
  match value {
    Small(value) => BigInt::from_uint64(value)
    Medium(high, low) =>
      (BigInt::from_uint64(high) << 64) + BigInt::from_uint64(low)
    Large(units) => {
      let base = BigInt::from_uint64(coeff_base)
      let mut result = 0N
      let mut index = units.length() - 1
      while true {
        result = result * base + BigInt::from_uint(units[index])
        if index == 0 {
          break
        }
        index -= 1
      }
      result
    }
  }
}

///|
pub fn coeff_to_uint64(value : Coeff) -> UInt64? {
  match value {
    Small(value) => Some(value)
    Medium(_, _) | Large(_) => None
  }
}

///|
pub fn coeff_is_zero(value : Coeff) -> Bool {
  match value {
    Small(value) => value == 0UL
    Medium(_, _) => false
    Large(_) => false
  }
}

///|
pub fn coeff_bits(value : Coeff) -> Int {
  match value {
    Small(value) => coeff_small_bits(value)
    Medium(high, _) => 64 + coeff_small_bits(high)
    Large(units) =>
      (units.length() - 1) * coeff_unit_bits +
      coeff_small_bits(units[units.length() - 1].to_uint64())
  }
}

///|
pub fn coeff_compare(left : Coeff, right : Coeff) -> Int {
  match (left, right) {
    (Small(left), Small(right)) =>
      if left < right {
        -1
      } else if left > right {
        1
      } else {
        0
      }
    (Medium(left_high, left_low), Medium(right_high, right_low)) =>
      if left_high != right_high {
        if left_high < right_high {
          -1
        } else {
          1
        }
      } else if left_low != right_low {
        if left_low < right_low {
          -1
        } else {
          1
        }
      } else {
        0
      }
    (Small(_), Medium(_, _)) => -1
    (Medium(_, _), Small(_)) => 1
    _ => {
      let left_bits = coeff_bits(left)
      let right_bits = coeff_bits(right)
      if left_bits != right_bits {
        return if left_bits < right_bits { -1 } else { 1 }
      }
      let left_units = coeff_units(left)
      let right_units = coeff_units(right)
      let mut index = left_units.length() - 1
      while true {
        if left_units[index] != right_units[index] {
          return if left_units[index] < right_units[index] { -1 } else { 1 }
        }
        if index == 0 {
          break
        }
        index -= 1
      }
      0
    }
  }
}

///|
pub fn coeff_add(left : Coeff, right : Coeff) -> Coeff {
  match (left, right) {
    (Small(left), Small(right)) => {
      let sum = left + right
      if sum >= left {
        return Small(sum)
      }
      return Medium(1UL, sum)
    }
    _ => ()
  }
  match (left, right) {
    (Medium(high, low), Small(value)) | (Small(value), Medium(high, low)) => {
      let result_low = low + value
      let carry = if result_low < low { 1UL } else { 0UL }
      let result_high = high + carry
      if result_high >= high {
        return coeff_medium(result_high, result_low)
      }
    }
    (Medium(left_high, left_low), Medium(right_high, right_low)) => {
      let result_low = left_low + right_low
      let carry = if result_low < left_low { 1UL } else { 0UL }
      let partial_high = left_high + right_high
      let result_high = partial_high + carry
      if partial_high >= left_high && result_high >= partial_high {
        return coeff_medium(result_high, result_low)
      }
    }
    _ => ()
  }
  let left_units = coeff_units(left)
  let right_units = coeff_units(right)
  let length = Int::max(left_units.length(), right_units.length())
  let units : Array[UInt] = []
  let mut carry = 0UL
  for index in 0..<length {
    let left_unit = if index < left_units.length() {
      left_units[index].to_uint64()
    } else {
      0UL
    }
    let right_unit = if index < right_units.length() {
      right_units[index].to_uint64()
    } else {
      0UL
    }
    let sum = left_unit + right_unit + carry
    units.push((sum & coeff_mask).to_uint())
    carry = sum >> coeff_unit_bits
  }
  if carry != 0UL {
    units.push(carry.to_uint())
  }
  coeff_make(units)
}

///|
pub fn coeff_increment(value : Coeff) -> Coeff {
  coeff_add(value, coeff_one())
}

///|
pub fn coeff_sub(left : Coeff, right : Coeff) -> Coeff {
  guard coeff_compare(left, right) >= 0 else {
    abort("coeff_sub expects left >= right")
  }
  match (left, right) {
    (Small(left), Small(right)) => return Small(left - right)
    _ => ()
  }
  match (left, right) {
    (Medium(high, low), Small(value)) => {
      let borrow = if low < value { 1UL } else { 0UL }
      return coeff_medium(high - borrow, low - value)
    }
    (Medium(left_high, left_low), Medium(right_high, right_low)) => {
      let borrow = if left_low < right_low { 1UL } else { 0UL }
      return coeff_medium(left_high - right_high - borrow, left_low - right_low)
    }
    _ => ()
  }
  let left_units = coeff_units(left)
  let right_units = coeff_units(right)
  let units : Array[UInt] = []
  let mut borrow = 0UL
  for index in 0..<left_units.length() {
    let left_unit = left_units[index].to_uint64()
    let right_unit = if index < right_units.length() {
      right_units[index].to_uint64()
    } else {
      0UL
    }
    let subtrahend = right_unit + borrow
    if left_unit < subtrahend {
      units.push((left_unit + coeff_base - subtrahend).to_uint())
      borrow = 1UL
    } else {
      units.push((left_unit - subtrahend).to_uint())
      borrow = 0UL
    }
  }
  coeff_make(units)
}

///|
pub fn coeff_mul(left : Coeff, right : Coeff) -> Coeff {
  if coeff_is_zero(left) || coeff_is_zero(right) {
    return coeff_zero()
  }
  match (left, right) {
    (Small(left), Small(right)) =>
      if left <= 0xffffffffffffffffUL / right {
        return Small(left * right)
      } else {
        let mask32 = 0xffffffffUL
        let left_low = left & mask32
        let left_high = left >> 32
        let right_low = right & mask32
        let right_high = right >> 32
        let first = left_low * right_low
        let low_word = first & mask32
        let mut middle = left_high * right_low + (first >> 32)
        let high_carry = middle >> 32
        middle = left_low * right_high + (middle & mask32)
        let high = left_high * right_high + high_carry + (middle >> 32)
        let low = (middle << 32) | low_word
        return coeff_medium(high, low)
      }
    _ => ()
  }
  let left_units = coeff_units(left)
  let right_units = coeff_units(right)
  let units = Array::make(left_units.length() + right_units.length(), 0U)
  for left_index in 0..<left_units.length() {
    let mut carry = 0UL
    for right_index in 0..<right_units.length() {
      let index = left_index + right_index
      let product = units[index].to_uint64() +
        left_units[left_index].to_uint64() *
        right_units[right_index].to_uint64() +
        carry
      units[index] = (product & coeff_mask).to_uint()
      carry = product >> coeff_unit_bits
    }
    let mut index = left_index + right_units.length()
    while carry != 0UL {
      let sum = units[index].to_uint64() + carry
      units[index] = (sum & coeff_mask).to_uint()
      carry = sum >> coeff_unit_bits
      index += 1
    }
  }
  coeff_make(units)
}

///|
pub fn coeff_shift_left(value : Coeff, shift : Int) -> Coeff {
  guard shift >= 0 else { abort("coeff_shift_left expects shift >= 0") }
  if shift == 0 || coeff_is_zero(value) {
    return value
  }
  match value {
    Small(value) => {
      if shift < 64 && value <= 0xffffffffffffffffUL >> shift {
        return Small(value << shift)
      }
      if shift < 64 {
        return coeff_medium(value >> (64 - shift), value << shift)
      }
      if shift < 128 && coeff_small_bits(value) + shift <= 128 {
        return coeff_medium(value << (shift - 64), 0UL)
      }
    }
    Medium(high, low) =>
      if shift < 64 && high <= 0xffffffffffffffffUL >> shift {
        return coeff_medium(
          (high << shift) | (low >> (64 - shift)),
          low << shift,
        )
      }
    Large(_) => ()
  }
  let source = coeff_units(value)
  let unit_shift = shift / coeff_unit_bits
  let bit_shift = shift % coeff_unit_bits
  let units = Array::make(unit_shift, 0U)
  let mut carry = 0UL
  for unit in source {
    let shifted = (unit.to_uint64() << bit_shift) + carry
    units.push((shifted & coeff_mask).to_uint())
    carry = shifted >> coeff_unit_bits
  }
  if carry != 0UL {
    units.push(carry.to_uint())
  }
  coeff_make(units)
}

///|
pub fn coeff_shift_right(value : Coeff, shift : Int) -> Coeff {
  guard shift >= 0 else { abort("coeff_shift_right expects shift >= 0") }
  if shift == 0 || coeff_is_zero(value) {
    return value
  }
  match value {
    Small(value) => return Small(if shift >= 64 { 0UL } else { value >> shift })
    Medium(high, low) => {
      if shift >= 128 {
        return coeff_zero()
      }
      if shift >= 64 {
        return Small(high >> (shift - 64))
      }
      return coeff_medium(
        high >> shift,
        (low >> shift) | (high << (64 - shift)),
      )
    }
    Large(source) => {
      if shift >= coeff_bits(value) {
        return coeff_zero()
      }
      let unit_shift = shift / coeff_unit_bits
      let bit_shift = shift % coeff_unit_bits
      let units = Array::make(source.length() - unit_shift, 0U)
      for output_index in 0..<units.length() {
        let source_index = output_index + unit_shift
        let mut unit = source[source_index].to_uint64() >> bit_shift
        if bit_shift > 0 && source_index + 1 < source.length() {
          unit = unit |
            (
              (
                source[source_index + 1].to_uint64() <<
                (coeff_unit_bits - bit_shift)
              ) &
              coeff_mask
            )
        }
        units[output_index] = unit.to_uint()
      }
      coeff_make(units)
    }
  }
}

///|
fn coeff_uint64_low_bits_nonzero(value : UInt64, count : Int) -> Bool {
  if count <= 0 {
    false
  } else if count >= 64 {
    value != 0UL
  } else {
    (value & ((1UL << count) - 1UL)) != 0UL
  }
}

///|
fn coeff_bit_is_set(value : Coeff, index : Int) -> Bool {
  if index < 0 {
    return false
  }
  match value {
    Small(value) => index < 64 && (value & (1UL << index)) != 0UL
    Medium(high, low) =>
      if index < 64 {
        (low & (1UL << index)) != 0UL
      } else {
        index < 128 && (high & (1UL << (index - 64))) != 0UL
      }
    Large(units) => {
      let unit_index = index / coeff_unit_bits
      unit_index < units.length() &&
      (units[unit_index].to_uint64() & (1UL << (index % coeff_unit_bits))) !=
      0UL
    }
  }
}

///|
fn coeff_low_bits_nonzero(value : Coeff, count : Int) -> Bool {
  if count <= 0 {
    return false
  }
  match value {
    Small(value) => coeff_uint64_low_bits_nonzero(value, count)
    Medium(high, low) =>
      if count <= 64 {
        coeff_uint64_low_bits_nonzero(low, count)
      } else {
        low != 0UL || coeff_uint64_low_bits_nonzero(high, count - 64)
      }
    Large(units) => {
      let full_units = count / coeff_unit_bits
      let full_length = Int::min(full_units, units.length())
      for index in 0..<full_length {
        if units[index] != 0U {
          return true
        }
      }
      let partial_bits = count % coeff_unit_bits
      full_units < units.length() &&
      partial_bits > 0 &&
      coeff_uint64_low_bits_nonzero(units[full_units].to_uint64(), partial_bits)
    }
  }
}

///|
#warnings("-unused_value")
fn coeff_round_shift_ties_even(value : Coeff, shift : Int) -> (Coeff, Bool) {
  guard shift >= 0 else {
    abort("coeff_round_shift_ties_even expects shift >= 0")
  }
  if shift == 0 || coeff_is_zero(value) {
    return (value, false)
  }
  match value {
    Small(source) => {
      if shift > 64 {
        return (coeff_zero(), true)
      }
      let quotient = if shift == 64 { 0UL } else { source >> shift }
      let round_bit = (source & (1UL << (shift - 1))) != 0UL
      let sticky_bit = coeff_uint64_low_bits_nonzero(source, shift - 1)
      let increment = round_bit && (sticky_bit || (quotient & 1UL) != 0UL)
      let rounded = if increment { quotient + 1UL } else { quotient }
      if increment && rounded == 0UL {
        (Medium(1UL, 0UL), true)
      } else {
        (Small(rounded), round_bit || sticky_bit)
      }
    }
    Medium(high, low) => {
      if shift > 128 {
        return (coeff_zero(), true)
      }
      if shift == 128 {
        let round_bit = (high & (1UL << 63)) != 0UL
        let sticky_bit = low != 0UL || coeff_uint64_low_bits_nonzero(high, 63)
        return (Small(if round_bit && sticky_bit { 1UL } else { 0UL }), true)
      }
      if shift > 64 {
        let high_shift = shift - 64
        let quotient = high >> high_shift
        let round_bit = (high & (1UL << (high_shift - 1))) != 0UL
        let sticky_bit = low != 0UL ||
          coeff_uint64_low_bits_nonzero(high, high_shift - 1)
        let increment = round_bit && (sticky_bit || (quotient & 1UL) != 0UL)
        return (
          Small(if increment { quotient + 1UL } else { quotient }),
          round_bit || sticky_bit,
        )
      }
      if shift == 64 {
        let round_bit = (low & (1UL << 63)) != 0UL
        let sticky_bit = coeff_uint64_low_bits_nonzero(low, 63)
        let increment = round_bit && (sticky_bit || (high & 1UL) != 0UL)
        if increment {
          let rounded = high + 1UL
          return (
            if rounded == 0UL {
              Medium(1UL, 0UL)
            } else {
              Small(rounded)
            },
            true,
          )
        }
        return (Small(high), round_bit || sticky_bit)
      }
      let quotient_high = high >> shift
      let quotient_low = (low >> shift) | (high << (64 - shift))
      let round_bit = (low & (1UL << (shift - 1))) != 0UL
      let sticky_bit = coeff_uint64_low_bits_nonzero(low, shift - 1)
      let increment = round_bit && (sticky_bit || (quotient_low & 1UL) != 0UL)
      if increment {
        let rounded_low = quotient_low + 1UL
        let carry = if rounded_low == 0UL { 1UL } else { 0UL }
        return (coeff_medium(quotient_high + carry, rounded_low), true)
      }
      (coeff_medium(quotient_high, quotient_low), round_bit || sticky_bit)
    }
    Large(source) => {
      let round_bit = coeff_bit_is_set(value, shift - 1)
      let sticky_bit = coeff_low_bits_nonzero(value, shift - 1)
      let inexact = round_bit || sticky_bit
      let increment = round_bit &&
        (sticky_bit || coeff_bit_is_set(value, shift))
      if shift >= coeff_bits(value) {
        return (Small(if increment { 1UL } else { 0UL }), inexact)
      }
      let unit_shift = shift / coeff_unit_bits
      let bit_shift = shift % coeff_unit_bits
      let units = Array::make(source.length() - unit_shift, 0U)
      for output_index in 0..<units.length() {
        let source_index = output_index + unit_shift
        let mut unit = source[source_index].to_uint64() >> bit_shift
        if bit_shift > 0 && source_index + 1 < source.length() {
          unit = unit |
            (
              (
                source[source_index + 1].to_uint64() <<
                (coeff_unit_bits - bit_shift)
              ) &
              coeff_mask
            )
        }
        units[output_index] = unit.to_uint()
      }
      if increment {
        let mut carry = 1UL
        let mut index = 0
        while carry != 0UL {
          if index == units.length() {
            units.push(carry.to_uint())
            break
          }
          let sum = units[index].to_uint64() + carry
          units[index] = (sum & coeff_mask).to_uint()
          carry = sum >> coeff_unit_bits
          index += 1
        }
      }
      (coeff_make(units), inexact)
    }
  }
}

///|
fn coeff_div_rem_by_unit(
  numerator : Coeff,
  denominator : UInt,
) -> (Coeff, Coeff) {
  let denominator64 = denominator.to_uint64()
  let source = coeff_units(numerator)
  let quotient = Array::make(source.length(), 0U)
  let mut remainder = 0UL
  let mut index = source.length() - 1
  while true {
    let accumulated = (remainder << coeff_unit_bits) + source[index].to_uint64()
    quotient[index] = (accumulated / denominator64).to_uint()
    remainder = accumulated % denominator64
    if index == 0 {
      break
    }
    index -= 1
  }
  (coeff_make(quotient), Small(remainder))
}

///|
fn coeff_normalized_shift(units : Array[UInt], shift : Int) -> Array[UInt] {
  if shift == 0 {
    return units.copy()
  }
  let result : Array[UInt] = []
  let mut carry = 0UL
  for unit in units {
    let shifted = (unit.to_uint64() << shift) | carry
    result.push((shifted & coeff_mask).to_uint())
    carry = shifted >> coeff_unit_bits
  }
  if carry != 0UL {
    result.push(carry.to_uint())
  }
  result
}

///|
fn coeff_div_rem_large(
  numerator : Coeff,
  denominator : Coeff,
) -> (Coeff, Coeff) {
  let numerator_units = coeff_units(numerator)
  let denominator_units = coeff_units(denominator)
  if denominator_units.length() == 1 {
    return coeff_div_rem_by_unit(numerator, denominator_units[0])
  }
  let top = denominator_units[denominator_units.length() - 1].to_uint64()
  let shift = coeff_unit_bits - coeff_small_bits(top)
  let divisor = coeff_normalized_shift(denominator_units, shift)
  let dividend = coeff_normalized_shift(numerator_units, shift)
  dividend.push(0U)
  let divisor_length = divisor.length()
  let quotient_length = dividend.length() - divisor_length
  let quotient = Array::make(quotient_length, 0U)
  let mut offset = quotient_length - 1
  while true {
    let high = dividend[offset + divisor_length].to_uint64()
    let next = dividend[offset + divisor_length - 1].to_uint64()
    let trial_dividend = (high << coeff_unit_bits) + next
    let divisor_top = divisor[divisor_length - 1].to_uint64()
    let mut trial = trial_dividend / divisor_top
    let mut trial_remainder = trial_dividend % divisor_top
    if trial >= coeff_base {
      trial = coeff_base - 1UL
      trial_remainder = trial_dividend - trial * divisor_top
    }
    if divisor_length > 1 {
      let divisor_next = divisor[divisor_length - 2].to_uint64()
      let dividend_next = dividend[offset + divisor_length - 2].to_uint64()
      while trial * divisor_next >
            (trial_remainder << coeff_unit_bits) + dividend_next {
        trial -= 1UL
        trial_remainder += divisor_top
        if trial_remainder >= coeff_base {
          break
        }
      }
    }
    let mut carry = 0UL
    let mut borrow = 0UL
    for index in 0..<divisor_length {
      let product = trial * divisor[index].to_uint64() + carry
      carry = product >> coeff_unit_bits
      let low = product & coeff_mask
      let current = dividend[offset + index].to_uint64()
      let subtrahend = low + borrow
      if current < subtrahend {
        dividend[offset + index] = (current + coeff_base - subtrahend).to_uint()
        borrow = 1UL
      } else {
        dividend[offset + index] = (current - subtrahend).to_uint()
        borrow = 0UL
      }
    }
    let high_index = offset + divisor_length
    let high_subtrahend = carry + borrow
    let current_high = dividend[high_index].to_uint64()
    let underflow = current_high < high_subtrahend
    dividend[high_index] = if underflow {
      (current_high + coeff_base - high_subtrahend).to_uint()
    } else {
      (current_high - high_subtrahend).to_uint()
    }
    if underflow {
      trial -= 1UL
      let mut add_carry = 0UL
      for index in 0..<divisor_length {
        let sum = dividend[offset + index].to_uint64() +
          divisor[index].to_uint64() +
          add_carry
        dividend[offset + index] = (sum & coeff_mask).to_uint()
        add_carry = sum >> coeff_unit_bits
      }
      dividend[high_index] = ((dividend[high_index].to_uint64() + add_carry) &
      coeff_mask).to_uint()
    }
    quotient[offset] = trial.to_uint()
    if offset == 0 {
      break
    }
    offset -= 1
  }
  let remainder_units = dividend[:divisor_length].to_owned()
  let remainder = if shift == 0 {
    coeff_make(remainder_units)
  } else {
    coeff_shift_right(coeff_make(remainder_units), shift)
  }
  (coeff_make(quotient), remainder)
}

///|
pub fn coeff_div_rem(numerator : Coeff, denominator : Coeff) -> (Coeff, Coeff) {
  guard !coeff_is_zero(denominator) else {
    abort("coeff_div_rem expects a non-zero denominator")
  }
  if coeff_compare(numerator, denominator) < 0 {
    return (coeff_zero(), numerator)
  }
  match (numerator, denominator) {
    (Small(numerator), Small(denominator)) =>
      (Small(numerator / denominator), Small(numerator % denominator))
    _ => coeff_div_rem_large(numerator, denominator)
  }
}

///|
pub fn coeff_div_exact(numerator : Coeff, denominator : Coeff) -> Coeff {
  let (quotient, remainder) = coeff_div_rem(numerator, denominator)
  guard coeff_is_zero(remainder) else {
    abort("coeff_div_exact received a non-exact division")
  }
  quotient
}

///|
pub fn coeff_gcd(left : Coeff, right : Coeff) -> Coeff {
  let mut left = left
  let mut right = right
  while !coeff_is_zero(right) {
    let remainder = coeff_div_rem(left, right).1
    left = right
    right = remainder
  }
  left
}

///|
pub fn coeff_mod_int(value : Coeff, divisor : Int) -> Int {
  guard divisor > 0 else { abort("coeff_mod_int expects a positive divisor") }
  let divisor = divisor.to_uint64()
  match value {
    Small(value) => (value % divisor).to_int()
    Medium(high, low) => {
      let base32 = (1UL << 32) % divisor
      let mut remainder = (high >> 32) % divisor
      remainder = (remainder * base32 + (high & 0xffffffffUL)) % divisor
      remainder = (remainder * base32 + (low >> 32)) % divisor
      remainder = (remainder * base32 + (low & 0xffffffffUL)) % divisor
      remainder.to_int()
    }
    Large(units) => {
      let mut remainder = 0UL
      let mut index = units.length() - 1
      while true {
        remainder = ((remainder << coeff_unit_bits) + units[index].to_uint64()) %
          divisor
        if index == 0 {
          break
        }
        index -= 1
      }
      remainder.to_int()
    }
  }
}

///|
pub fn signed_coeff_from_parts(
  negative : Bool,
  magnitude : Coeff,
) -> SignedCoeff {
  { negative: negative && !coeff_is_zero(magnitude), magnitude }
}

///|
pub fn signed_coeff_from_int(value : Int) -> SignedCoeff {
  if value >= 0 {
    signed_coeff_from_parts(false, coeff_from_nonnegative_int(value))
  } else {
    let magnitude = (-(value + 1)).to_uint64() + 1UL
    signed_coeff_from_parts(true, Small(magnitude))
  }
}

///|
pub fn signed_coeff_from_bigint(value : BigInt) -> SignedCoeff {
  let negative = value < 0N
  let magnitude = coeff_from_nonnegative_bigint(
    if negative {
      -value
    } else {
      value
    },
  )
  signed_coeff_from_parts(negative, magnitude)
}

///|
pub fn signed_coeff_to_bigint(value : SignedCoeff) -> BigInt {
  let magnitude = coeff_to_bigint(value.magnitude)
  if value.negative {
    -magnitude
  } else {
    magnitude
  }
}

///|
pub fn signed_coeff_magnitude(value : SignedCoeff) -> Coeff {
  value.magnitude
}

///|
pub fn signed_coeff_sign(value : SignedCoeff) -> Int {
  if coeff_is_zero(value.magnitude) {
    0
  } else if value.negative {
    -1
  } else {
    1
  }
}

///|
pub fn signed_coeff_is_zero(value : SignedCoeff) -> Bool {
  coeff_is_zero(value.magnitude)
}

///|
pub fn signed_coeff_neg(value : SignedCoeff) -> SignedCoeff {
  signed_coeff_from_parts(!value.negative, value.magnitude)
}

///|
pub fn signed_coeff_abs(value : SignedCoeff) -> SignedCoeff {
  signed_coeff_from_parts(false, value.magnitude)
}

///|
pub fn signed_coeff_compare(left : SignedCoeff, right : SignedCoeff) -> Int {
  let left_sign = signed_coeff_sign(left)
  let right_sign = signed_coeff_sign(right)
  if left_sign != right_sign {
    return if left_sign < right_sign { -1 } else { 1 }
  }
  if left_sign == 0 {
    return 0
  }
  let comparison = coeff_compare(left.magnitude, right.magnitude)
  if left_sign < 0 {
    -comparison
  } else {
    comparison
  }
}

///|
pub fn signed_coeff_add(left : SignedCoeff, right : SignedCoeff) -> SignedCoeff {
  if left.negative == right.negative {
    return signed_coeff_from_parts(
      left.negative,
      coeff_add(left.magnitude, right.magnitude),
    )
  }
  let comparison = coeff_compare(left.magnitude, right.magnitude)
  if comparison == 0 {
    signed_coeff_from_int(0)
  } else if comparison > 0 {
    signed_coeff_from_parts(
      left.negative,
      coeff_sub(left.magnitude, right.magnitude),
    )
  } else {
    signed_coeff_from_parts(
      right.negative,
      coeff_sub(right.magnitude, left.magnitude),
    )
  }
}

///|
pub fn signed_coeff_sub(left : SignedCoeff, right : SignedCoeff) -> SignedCoeff {
  signed_coeff_add(left, signed_coeff_neg(right))
}

///|
pub fn signed_coeff_mul(left : SignedCoeff, right : SignedCoeff) -> SignedCoeff {
  signed_coeff_from_parts(
    left.negative != right.negative,
    coeff_mul(left.magnitude, right.magnitude),
  )
}

///|
pub fn signed_coeff_mul_magnitude(
  value : SignedCoeff,
  multiplier : Coeff,
) -> SignedCoeff {
  signed_coeff_from_parts(
    value.negative,
    coeff_mul(value.magnitude, multiplier),
  )
}

///|
pub fn signed_coeff_div_exact(
  value : SignedCoeff,
  divisor : Coeff,
) -> SignedCoeff {
  signed_coeff_from_parts(
    value.negative,
    coeff_div_exact(value.magnitude, divisor),
  )
}
