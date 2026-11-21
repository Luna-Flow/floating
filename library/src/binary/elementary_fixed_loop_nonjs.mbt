///|
/// The loop of `binary_ln_unit_fixed_bounds` after `Z` and `Q` are known: the sum
/// of the terms `T(k) = floor(P(k) / (2k + 1))` with `P(0) = Z`, `P(k) =
/// floor(P(k-1) Q / 2^F)`, stopping at the first `P(index) < 2^6`; returns the
/// sum (without `P(index)`) and `index`, or `None` after 10000 terms.
///
/// The state lives in five limb arrays allocated once (`power`, `multiplier` =
/// `Q`, `scratch` for the product, `quotient`, `sum`), so a term allocates
/// nothing. Every integer is the one the `Coeff` form computes: the product is
/// the exact product by the limb rows (`bin_limbs_mul_1`, `bin_limbs_addmul_1`),
/// `P` is its floor shifted right by `F` (one copy pass, `F = 64 whole + part`),
/// and `T` is the floor of `P` by the odd divisor `2k + 1`. That divisor is at
/// most 20001 (the loop stops at 10000 terms), below `2^15`, so the running
/// remainder times `2^32` plus a half limb stays below `2^47`: a limb divides by
/// two hardware divisions of its 32-bit halves.
fn binary_ln_artanh_loop(
  z : Coeff,
  square : Coeff,
  fractional : Int32,
) -> (Coeff, Int32)? {
  let limbs = (z.bit_length() + 63) / 64
  let multiplier_limbs = (square.bit_length() + 63) / 64
  let power = FixedArray::make(limbs, 0UL)
  let quotient = FixedArray::make(limbs, 0UL)
  let sum = FixedArray::make(limbs + 1, 0UL)
  let scratch = FixedArray::make(limbs + multiplier_limbs + 1, 0UL)
  let multiplier = FixedArray::make(Int32::max(multiplier_limbs, 1), 0UL)
  for i in 0..<limbs {
    let word = bin_coeff_word(z, i)
    power.unsafe_set(i, word)
    sum.unsafe_set(i, word)
  }
  for i in 0..<multiplier_limbs {
    multiplier.unsafe_set(i, bin_coeff_word(square, i))
  }
  let whole = fractional / 64
  let part = fractional % 64
  let mut length = limbs
  let mut index = 0
  while index < 10000 {
    index += 1
    // P <- floor(P Q / 2^F); a zero Q gives 0
    let product_limbs = length + multiplier_limbs
    if multiplier_limbs == 0 || product_limbs <= whole {
      return Some((bin_coeff_from_words(sum, limbs + 1), index))
    }
    scratch.unsafe_set(
      length,
      bin_limbs_mul_1(scratch, 0, power, 0, length, multiplier.unsafe_get(0)),
    )
    for j in 1..<multiplier_limbs {
      scratch.unsafe_set(
        length + j,
        bin_limbs_addmul_1(
          scratch,
          j,
          power,
          0,
          length,
          multiplier.unsafe_get(j),
        ),
      )
    }
    // The floor lies below the old P, so it fits in `length` limbs.
    let available = product_limbs - whole
    for i in 0..<length {
      let limb = if i >= available {
        0UL
      } else if part == 0 {
        scratch.unsafe_get(whole + i)
      } else {
        let high = if whole + i + 1 < product_limbs {
          scratch.unsafe_get(whole + i + 1)
        } else {
          0UL
        }
        (scratch.unsafe_get(whole + i) >> part) | (high << (64 - part))
      }
      power.unsafe_set(i, limb)
    }
    while length > 0 && power.unsafe_get(length - 1) == 0UL {
      length -= 1
    }
    if length == 0 || (length == 1 && power.unsafe_get(0) < 64UL) {
      return Some((bin_coeff_from_words(sum, limbs + 1), index))
    }
    // T = floor(P / (2 index + 1)), limb by limb from the top
    let divisor = (2 * index + 1).to_uint64()
    let mut remainder = 0UL
    let mut i = length - 1
    while i >= 0 {
      let word = power.unsafe_get(i)
      let high = (remainder << 32) | (word >> 32)
      let high_quotient = high / divisor
      let low = ((high - high_quotient * divisor) << 32) | (word & 0xFFFFFFFFUL)
      let low_quotient = low / divisor
      remainder = low - low_quotient * divisor
      quotient.unsafe_set(i, (high_quotient << 32) | low_quotient)
      i -= 1
    }
    // sum += T
    let mut carry = false
    for k in 0..<length {
      let a = sum.unsafe_get(k)
      let b = quotient.unsafe_get(k)
      let t = a + b
      let c1 = t < a
      let u = if carry { t + 1UL } else { t }
      let c2 = carry && u == 0UL
      sum.unsafe_set(k, u)
      carry = c1 || c2
    }
    let mut k = length
    while carry && k <= limbs {
      let u = sum.unsafe_get(k) + 1UL
      sum.unsafe_set(k, u)
      carry = u == 0UL
      k += 1
    }
  }
  None
}
