///|
/// Checks `bin_coeff_mul_short` on one pair: either it declines, or its value
/// rounds, to `precision` bits, as the exact product does (nearest even, and
/// the truncation and the inexact flag for the directed modes). Returns
/// whether it returned a value.
fn short_mul_check(
  left_big : BigInt,
  right_big : BigInt,
  precision : Int32,
) -> Bool raise {
  let left = bin_coeff_test_from_bigint(left_big)
  let right = bin_coeff_test_from_bigint(right_big)
  // the width conditions of `bin_coeff_mul_short_ok` without its limb range:
  // the algorithm is checked at every size, the production range is a choice
  if left.bit_length() + 64 <= precision ||
    right.bit_length() + 64 <= precision ||
    left.bit_length() > precision ||
    right.bit_length() > precision {
    return false
  }
  let approximate = bin_coeff_mul_short(left, right, precision)
  if approximate.is_zero() {
    return false
  }
  let product = left_big * right_big
  let product_bits = product.bit_length()
  let approximate_big = @string.parse_bigint(approximate.to_string())
  let approximate_bits = approximate_big.bit_length()
  // the value is `H * 2^(bits(a) + bits(b) - 64 m)`: the same top bits
  let limbs = bin_coeff_short_product_limbs(precision)
  assert_eq(
    product_bits,
    approximate_bits +
    left_big.bit_length() +
    right_big.bit_length() -
    64 * limbs,
  )
  let exact_shift = product_bits - precision
  let kept = product >> exact_shift
  let low = product - (kept << exact_shift)
  let approximate_shift = approximate_bits - precision
  let approximate_kept = approximate_big >> approximate_shift
  let approximate_low = approximate_big -
    (approximate_kept << approximate_shift)
  // directed modes: the truncation agrees and the product is inexact
  assert_true(kept == approximate_kept)
  assert_true(low != 0N)
  // nearest: halfway is the same side (a tie cannot occur in a returned value)
  let half = 1N << (exact_shift - 1)
  let approximate_half = 1N << (approximate_shift - 1)
  assert_true(approximate_low != approximate_half)
  assert_eq(low > half, approximate_low > approximate_half)
  true
}

///|
// oracle: B, S
// source: B: the exact product from core BigInt multiplication: the kept top bits and the sticky part decide the directed modes and the nearest rounding, the bit length relation product_bits = approximate_bits + bits(a) + bits(b) - 64 m; S: the counts (the declined and the returned cases are both common)
// shares: bin_coeff_test_from_bigint and bin_coeff_sqrt_test_value (the operands), Coeff::to_string read back with parse_bigint
// primitives: core BigInt (moonbitlang/core) multiplication and shifts are an implementation independent of the kernel; Coeff::to_string: see the text path in `radix conversion of powers of the radix and their neighbours at chunk edges` (coeff_radix_nonjs_wbtest.mbt)
test "short product rounds like the exact product on random operands" {
  let mut returned = 0
  let mut total = 0
  for limbs in [3, 4, 5, 8, 9, 16, 17, 31, 32, 33, 40, 63] {
    for variant in 0..<3 {
      for seed in 1..<60 {
        for precision_offset in [0, -1, -30, -63] {
          let precision = limbs * 64 + precision_offset
          let left_bits = precision - (if variant == 2 { seed % 40 } else { 0 })
          let right_bits = precision -
            (if variant == 1 { seed % 50 } else { 0 })
          let left_big = bin_coeff_sqrt_test_value(
              left_bits,
              (seed + limbs * 77).to_uint64(),
            ) |
            1N
          let right_big = bin_coeff_sqrt_test_value(
              right_bits,
              (seed * 5 + variant + limbs * 13).to_uint64(),
            ) |
            1N
          total += 1
          if short_mul_check(left_big, right_big, precision) {
            returned += 1
          }
        }
      }
    }
  }
  assert_true(returned * 100 > total * 90)
}

///|
/// Structured operands whose product sits next to a grid point: powers of two
/// plus or minus small numbers (`(2^k + 1) (2^k - 1) = 2^(2k) - 1`, squares of
/// `2^k + 1`), all ones, a top limb just above half, trailing patterns. Every
/// call must decline or round correctly.
// oracle: B, S
// source: B: the exact product from core BigInt multiplication: the kept top bits and the sticky part decide the directed modes and the nearest rounding, the bit length relation product_bits = approximate_bits + bits(a) + bits(b) - 64 m; S: the counts (the declined and the returned cases are both common)
// shares: bin_coeff_test_from_bigint and bin_coeff_sqrt_test_value (the operands), Coeff::to_string read back with parse_bigint
// primitives: core BigInt (moonbitlang/core) multiplication and shifts are an implementation independent of the kernel; Coeff::to_string: see the text path in `radix conversion of powers of the radix and their neighbours at chunk edges` (coeff_radix_nonjs_wbtest.mbt)
test "short product on products next to rounding boundaries" {
  let mut returned = 0
  let mut declined = 0
  for limbs in [3, 4, 5, 8, 9, 17, 32, 33, 63] {
    for precision_offset in [0, -1, -63] {
      let precision = limbs * 64 + precision_offset
      let power = 1N << (precision - 1)
      let ones = (1N << precision) - 1N
      let operands = [
        power + 1N,
        power - 1N + (1N << 0),
        ones,
        ones - 2N,
        power + (1N << 64) + 1N,
        power + (power >> 1) + 1N,
        (1N << (precision / 2)) + 1N,
        (((1N << (precision / 2)) - 1N) * ((1N << (precision / 2 - 3)) + 1N)) |
        1N,
        power | (1N << (precision - 64)) | 1N,
      ]
      for left_big in operands {
        for right_big in operands {
          if left_big.bit_length() > precision ||
            right_big.bit_length() > precision {
            continue
          }
          if left_big <= 0N || right_big <= 0N {
            continue
          }
          if short_mul_check(left_big, right_big, precision) {
            returned += 1
          } else {
            declined += 1
          }
        }
      }
    }
  }
  // structured products do reach the decline path, and some still return
  assert_true(declined > 20)
  assert_true(returned > 20)
}
