///|
/// Short product ("mulhigh", the basecase of Harvey and Zimmermann's ShortMul):
/// the high limbs of a product, without the products of the low limbs. For
/// the rounding of a product to `precision` bits only the top `precision + 2`
/// bits matter; when the approximation is far enough from a rounding boundary
/// it decides the rounding, else the exact product is formed as before.

///|
/// Limbs of the operands of a short product at `precision` bits: the limbs of
/// the precision plus one extra limb that carries the error of the
/// approximation below the rounding position.
pub fn bin_coeff_short_product_limbs(precision : Int32) -> Int32 {
  (precision + 63) / 64 + 1
}

///|
/// Whether `bin_coeff_mul_short` handles the product of `left` and `right` at
/// `precision` bits: a short product of `bin_coeff_short_product_min_limbs` to
/// `bin_coeff_short_product_max_limbs` limbs (the two limits of the target:
/// 31 and 384 on native with the assembly rows, 20 and 192 with the C rows, 13
/// and 64 with the portable rows),
/// both operands within 64
/// bits of the precision (a narrower operand makes most of the rows zero, and
/// the exact product is cheap then).
pub fn bin_coeff_mul_short_ok(
  left : Coeff,
  right : Coeff,
  precision : Int32,
) -> Bool {
  let limbs = bin_coeff_short_product_limbs(precision)
  limbs >= bin_coeff_short_product_min_limbs &&
  limbs <= bin_coeff_short_product_max_limbs &&
  left.bit_length() + 64 > precision &&
  right.bit_length() + 64 > precision &&
  left.bit_length() <= precision &&
  right.bit_length() <= precision
}

///|
/// An approximation `H` of the product `left * right` such that
/// `left * right = H * 2^(bits(left) + bits(right) - 64 m)` up to the bound
/// below, if its rounding to `precision` bits is certain; else
/// `Coeff::zero()` (the caller then multiplies exactly). Requires
/// `bin_coeff_mul_short_ok`; `m = bin_coeff_short_product_limbs(precision)`.
///
/// Error bound. The operands are shifted left to `m` limbs with the top bit set
/// (`A = left << (64 m - bits(left))`, likewise `B`; the low limb is zero because
/// `bits <= precision <= 64 (m - 1)`). The rows of `bin_limbs_addmul_1`
/// accumulate every limb product `a_j b_i B^(i+j)` with `i + j >= m - 1`;
/// the others are dropped. Each dropped term is below `B^(i+j+2)`, and there are
/// `s + 1` of them with `i + j = s <= m - 2`, so their sum is below
/// `sum_{s=0}^{m-2} (s+1) B^(s+2) < m B^m`. The kept sum `S` therefore
/// satisfies `S <= A B < S + m B^m`, and `H = floor(S / B^m)` (the top `m`
/// limbs, `r[m ..< 2m)`) satisfies `H <= A B / B^m < H + m + 1`.
///
/// Rounding. Let `bits` be the bit length of `H` (`64 m` or one less) and
/// `s = bits - precision - 1 >= 62`. A grid point (a multiple of `2^s`: the
/// halfway and the representable points, the power of two at the top among
/// them) lies in `[H, H + m + 1]` unless `r = H mod 2^s` satisfies `r > 0` and
/// `2^s - 1 - r >= m + 1`. When it does not, the true product is strictly
/// between two grid points, the result is inexact, and its rounding in every
/// mode is that of `H`.
///
/// Ownership of the result: if it is `Heap(words, len)`, `words` is an array
/// that no operand and no other value refers to (its length may exceed `len`),
/// which the caller may keep, hand on or modify. `Coeff::zero()` is the shared
/// constant that answers "declined"; recognise it with `is_zero()`.
pub fn bin_coeff_mul_short(
  left : Coeff,
  right : Coeff,
  precision : Int32,
) -> Coeff {
  let limbs = bin_coeff_short_product_limbs(precision)
  let a = bin_coeff_words_shifted(left, 64 * limbs - left.bit_length(), limbs)
  let b = bin_coeff_words_shifted(right, 64 * limbs - right.bit_length(), limbs)
  let product = FixedArray::make(2 * limbs, 0UL)
  // row 0: the top limb of `a` times `b[0]`
  let first = bin_limbs_mul_1(
    product,
    limbs - 1,
    a,
    limbs - 1,
    1,
    b.unsafe_get(0),
  )
  product.unsafe_set(limbs, first)
  for row in 1..<limbs {
    let carry = bin_limbs_addmul_1(
      product,
      limbs - 1,
      a,
      limbs - row - 1,
      row + 1,
      b.unsafe_get(row),
    )
    product.unsafe_set(limbs + row, carry)
  }
  // H = product[limbs ..< 2 limbs); bit length, then the rounding window
  let top = product.unsafe_get(2 * limbs - 1)
  // the product of two left-aligned values has its top bit in the top limb
  guard top != 0UL else { return Coeff::zero() }
  let bits = (limbs - 1) * 64 + bin_coeff_u64_bits(top)
  let spacing_bits = bits - precision - 1
  if spacing_bits < 62 {
    return Coeff::zero()
  }
  // r = H mod 2^spacing_bits must be nonzero and its complement at least
  // `limbs + 1`; H starts at `product[limbs]`
  let words = spacing_bits / 64 + (if spacing_bits % 64 == 0 { 0 } else { 1 })
  let top_bits = spacing_bits - (words - 1) * 64
  let top_mask = if top_bits == 64 {
    0xFFFF_FFFF_FFFF_FFFFUL
  } else {
    (1UL << top_bits) - 1UL
  }
  let mut remainder_nonzero = false
  let mut complement_large = false
  for index in 0..<words {
    let raw = product.unsafe_get(limbs + index)
    let word = if index == words - 1 { raw & top_mask } else { raw }
    let full = if index == words - 1 {
      top_mask
    } else {
      0xFFFF_FFFF_FFFF_FFFFUL
    }
    if word != 0UL {
      remainder_nonzero = true
    }
    let complement = full - word
    if index == 0 {
      if complement >= (limbs + 1).to_uint64() {
        complement_large = true
      }
    } else if complement != 0UL {
      complement_large = true
    }
  }
  if !remainder_nonzero || !complement_large {
    return Coeff::zero()
  }
  // H as a coefficient: the high `limbs` limbs of `product`, moved down in
  // place (the array is ours and `from_words` keeps only the first `limbs`)
  for index in 0..<limbs {
    product.unsafe_set(index, product.unsafe_get(limbs + index))
  }
  bin_coeff_from_words(product, limbs)
}
