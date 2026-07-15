///|
let gda_coeff_ntt_prime1 = 998244353UL

///|
let gda_coeff_ntt_prime2 = 754974721UL

///|
let gda_coeff_ntt_root1 = 3UL

///|
let gda_coeff_ntt_root2 = 11UL

///|
let gda_coeff_ntt_crt_inverse = 416537774UL

///|
let gda_coeff_ntt_radix_digits = 5

///|
let gda_coeff_ntt_radix = 100000UL

///|
fn gda_coeff_ntt_pow_mod(
  base : UInt64,
  exponent : UInt64,
  prime : UInt64,
) -> UInt64 {
  let mut result = 1UL
  let mut factor = base % prime
  let mut power = exponent
  while power != 0UL {
    if (power & 1UL) != 0UL {
      result = result * factor % prime
    }
    factor = factor * factor % prime
    power = power >> 1
  }
  result
}

///|
fn gda_coeff_ntt_transform(
  values : Array[UInt64],
  inverse : Bool,
  prime : UInt64,
  root : UInt64,
) -> Unit {
  let length = values.length()
  guard length > 0 &&
    length <= 1 << 23 &&
    (length & (length - 1)) == 0 &&
    (prime - 1UL) % length.to_uint64() == 0UL else {
    abort("decimal coefficient NTT length is unsupported")
  }
  let mut reverse = 0
  for index in 1..<length {
    let mut bit = length >> 1
    while (reverse & bit) != 0 {
      reverse = reverse ^ bit
      bit = bit >> 1
    }
    reverse = reverse ^ bit
    if index < reverse {
      let hold = values[index]
      values[index] = values[reverse]
      values[reverse] = hold
    }
  }
  let mut stage_length = 2
  while stage_length <= length {
    let mut stage_root = gda_coeff_ntt_pow_mod(
      root,
      (prime - 1UL) / stage_length.to_uint64(),
      prime,
    )
    if inverse {
      stage_root = gda_coeff_ntt_pow_mod(stage_root, prime - 2UL, prime)
    }
    let half = stage_length / 2
    let mut block = 0
    while block < length {
      let mut factor = 1UL
      for offset in 0..<half {
        let lhs = values[block + offset]
        let rhs = values[block + offset + half] * factor % prime
        values[block + offset] = (lhs + rhs) % prime
        values[block + offset + half] = (lhs + prime - rhs) % prime
        factor = factor * stage_root % prime
      }
      block += stage_length
    }
    stage_length = stage_length << 1
  }
  if inverse {
    let inverse_length = gda_coeff_ntt_pow_mod(
      length.to_uint64(),
      prime - 2UL,
      prime,
    )
    for index in 0..<length {
      values[index] = values[index] * inverse_length % prime
    }
  }
}

///|
fn gda_coeff_ntt_digit_len(value : GdaCoeff) -> Int {
  (value.digits10() + gda_coeff_ntt_radix_digits - 1) /
  gda_coeff_ntt_radix_digits
}

///|
fn gda_coeff_ntt_digits(value : GdaCoeff) -> Array[UInt64] {
  let length = gda_coeff_ntt_digit_len(value)
  let result = Array::make(length, 0UL)
  for index in 0..<length {
    let decimal_offset = index * gda_coeff_ntt_radix_digits
    let limb_index = decimal_offset / gda_coeff_dpun
    let limb_offset = decimal_offset % gda_coeff_dpun
    let available = gda_coeff_dpun - limb_offset
    let divisor = gda_coeff_powers[limb_offset].to_uint64()
    let mut digit = gda_coeff_limb_at(value, limb_index).to_uint64() / divisor
    if available < gda_coeff_ntt_radix_digits {
      let needed = gda_coeff_ntt_radix_digits - available
      let upper = gda_coeff_limb_at(value, limb_index + 1).to_uint64() %
        gda_coeff_powers[needed].to_uint64()
      digit += upper * gda_coeff_powers[available].to_uint64()
    }
    result[index] = digit % gda_coeff_ntt_radix
  }
  result
}

///|
fn gda_coeff_ntt_next_power_of_two(value : Int) -> Int {
  let mut result = 1
  while result < value {
    result = result << 1
  }
  result
}

///|
fn gda_coeff_ntt_limits_fit(left_len : Int, right_len : Int) -> Bool {
  if left_len <= 0 ||
    right_len <= 0 ||
    left_len.to_int64() + right_len.to_int64() - 1L > (1 << 23).to_int64() {
    return false
  }
  let transform_length = gda_coeff_ntt_next_power_of_two(
    left_len + right_len - 1,
  )
  transform_length <= 1 << 23 &&
  Int::min(left_len, right_len).to_uint64() *
  (gda_coeff_ntt_radix - 1UL) *
  (gda_coeff_ntt_radix - 1UL) <
  gda_coeff_ntt_prime1 * gda_coeff_ntt_prime2
}

///|
fn gda_coeff_ntt_transform_length(left : GdaCoeff, right : GdaCoeff) -> Int {
  gda_coeff_ntt_next_power_of_two(
    gda_coeff_ntt_digit_len(left) + gda_coeff_ntt_digit_len(right) - 1,
  )
}

///|
fn gda_coeff_ntt_fits(left : GdaCoeff, right : GdaCoeff) -> Bool {
  gda_coeff_ntt_limits_fit(
    gda_coeff_ntt_digit_len(left),
    gda_coeff_ntt_digit_len(right),
  )
}

///|
fn gda_coeff_ntt_convolve(
  left : Array[UInt64],
  right : Array[UInt64],
  prime : UInt64,
  root : UInt64,
) -> Array[UInt64] {
  let length = gda_coeff_ntt_next_power_of_two(
    left.length() + right.length() - 1,
  )
  let lhs = Array::make(length, 0UL)
  let rhs = Array::make(length, 0UL)
  for index in 0..<left.length() {
    lhs[index] = left[index]
  }
  for index in 0..<right.length() {
    rhs[index] = right[index]
  }
  gda_coeff_ntt_transform(lhs, false, prime, root)
  gda_coeff_ntt_transform(rhs, false, prime, root)
  for index in 0..<length {
    lhs[index] = lhs[index] * rhs[index] % prime
  }
  gda_coeff_ntt_transform(lhs, true, prime, root)
  lhs
}

///|
fn gda_coeff_ntt_square_convolve(
  value : Array[UInt64],
  prime : UInt64,
  root : UInt64,
) -> Array[UInt64] {
  let length = gda_coeff_ntt_next_power_of_two(value.length() * 2 - 1)
  let transformed = Array::make(length, 0UL)
  for index in 0..<value.length() {
    transformed[index] = value[index]
  }
  gda_coeff_ntt_transform(transformed, false, prime, root)
  for index in 0..<length {
    transformed[index] = transformed[index] * transformed[index] % prime
  }
  gda_coeff_ntt_transform(transformed, true, prime, root)
  transformed
}

///|
fn gda_coeff_ntt_crt(left : UInt64, right : UInt64) -> UInt64 {
  let difference = (right + gda_coeff_ntt_prime2 - left % gda_coeff_ntt_prime2) %
    gda_coeff_ntt_prime2
  let correction = difference * gda_coeff_ntt_crt_inverse % gda_coeff_ntt_prime2
  left + gda_coeff_ntt_prime1 * correction
}

///|
fn gda_coeff_from_ntt_digits(digits : Array[UInt64]) -> GdaCoeff {
  let limb_len = (
      digits.length() * gda_coeff_ntt_radix_digits + gda_coeff_dpun - 1
    ) /
    gda_coeff_dpun +
    1
  let limbs = Array::make(Int::max(1, limb_len), 0UL)
  for index in 0..<digits.length() {
    let decimal_offset = index * gda_coeff_ntt_radix_digits
    let limb_index = decimal_offset / gda_coeff_dpun
    let limb_offset = decimal_offset % gda_coeff_dpun
    let contribution = digits[index] * gda_coeff_powers[limb_offset].to_uint64()
    let mut target = limb_index
    let mut carry = contribution
    while carry != 0UL {
      let current = limbs[target] + carry
      limbs[target] = current % gda_coeff_wide_base
      carry = current / gda_coeff_wide_base
      target += 1
    }
  }
  gda_coeff_from_wide_accumulator(limbs, limbs.length())
}

///|
fn gda_coeff_ntt_reconstruct(
  first : Array[UInt64],
  second : Array[UInt64],
  length : Int,
) -> GdaCoeff {
  let normalized = Array::make(length + 8, 0UL)
  let mut carry = 0UL
  for index in 0..<length {
    let coefficient = gda_coeff_ntt_crt(first[index], second[index]) + carry
    normalized[index] = coefficient % gda_coeff_ntt_radix
    carry = coefficient / gda_coeff_ntt_radix
  }
  let mut index = length
  while carry != 0UL {
    normalized[index] = carry % gda_coeff_ntt_radix
    carry /= gda_coeff_ntt_radix
    index += 1
  }
  gda_coeff_from_ntt_digits(normalized)
}

///|
fn gda_coeff_mul_ntt(left : GdaCoeff, right : GdaCoeff) -> GdaCoeff {
  if !gda_coeff_ntt_fits(left, right) {
    return gda_coeff_mul_toom3(left, right)
  }
  let lhs = gda_coeff_ntt_digits(left)
  let rhs = gda_coeff_ntt_digits(right)
  let first = gda_coeff_ntt_convolve(
    lhs, rhs, gda_coeff_ntt_prime1, gda_coeff_ntt_root1,
  )
  let second = gda_coeff_ntt_convolve(
    lhs, rhs, gda_coeff_ntt_prime2, gda_coeff_ntt_root2,
  )
  let length = lhs.length() + rhs.length() - 1
  gda_coeff_ntt_reconstruct(first, second, length)
}

///|
fn gda_coeff_square_ntt(value : GdaCoeff) -> GdaCoeff {
  if !gda_coeff_ntt_fits(value, value) {
    return gda_coeff_mul_toom3(value, value)
  }
  let digits = gda_coeff_ntt_digits(value)
  let first = gda_coeff_ntt_square_convolve(
    digits, gda_coeff_ntt_prime1, gda_coeff_ntt_root1,
  )
  let second = gda_coeff_ntt_square_convolve(
    digits, gda_coeff_ntt_prime2, gda_coeff_ntt_root2,
  )
  gda_coeff_ntt_reconstruct(first, second, digits.length() * 2 - 1)
}
