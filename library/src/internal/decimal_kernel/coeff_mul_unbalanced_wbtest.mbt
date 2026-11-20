///|
// The product of an unbalanced pair (the longer operand more than twice the
// shorter one) below the Karatsuba threshold takes the column schoolbook; the
// previous per-product loop (about 45 instructions a product) is gone. The
// product is compared with the independent reference of
// `coeff_mul_diff_wbtest.mbt` (grade-school with a carry per product), bit for
// bit, representation included, at the unbalanced entry and through the
// public dispatch, on shapes around every boundary: 1 to 3 limbs, the column
// limit of 18, the fold boundary of 16 products, just below the threshold
// (191) and the first block product above it (192), and longer operands of 2.1
// to 12 times the shorter.

///|
fn unbalanced_check(
  short_limbs : Int32,
  long_limbs : Int32,
  nines : UInt64,
  state : Ref[UInt64],
) -> Unit raise {
  let short = round_diff_value(state, short_limbs, nines)
  let long = round_diff_value(state, long_limbs, nines)
  let expected = reference_mul_schoolbook(short, long)
  if !sqrt_diff_same(dec_coeff_mul_unbalanced(short, long), expected) ||
    !sqrt_diff_same(dec_coeff_multiply_repr(short, long), expected) ||
    !sqrt_diff_same(dec_coeff_multiply_repr(long, short), expected) {
    fail("unbalanced product differs for \{short_limbs} x \{long_limbs} limbs")
  }
}

///|
test "unbalanced product equals the reference on shapes around every boundary" {
  let state = Ref(0x9E3779B97F4A7C15UL)
  for short_limbs in [1, 2, 3, 5, 9, 17, 18, 19, 20, 33, 34, 50, 96, 150, 191] {
    for factor_tenths in [21, 25, 30, 50, 80, 120] {
      let long_limbs = short_limbs * factor_tenths / 10 + 1
      if long_limbs > 2 * short_limbs {
        for round in 0..<4 {
          unbalanced_check(
            short_limbs,
            long_limbs,
            (round * 3).to_uint64(),
            state,
          )
        }
      }
    }
  }
}

///|
test "unbalanced product above the threshold (block products)" {
  let state = Ref(0xD1B54A32D192ED03UL)
  for short_limbs in [192, 200, 250] {
    for
      long_limbs in [2 * short_limbs + 1, 3 * short_limbs, 4 * short_limbs + 7] {
      unbalanced_check(short_limbs, long_limbs, 0UL, state)
      unbalanced_check(short_limbs, long_limbs, 6UL, state)
    }
  }
}

///|
/// All limbs 10^9 - 1: the largest column sums, at every fold boundary of the
/// column schoolbook (columns of 15, 16, 17 and more products).
test "unbalanced product of all-nines operands" {
  for short_limbs in [1, 2, 15, 16, 17, 18, 19, 31, 32, 33, 64, 100, 191] {
    for
      long_limbs in [
        2 * short_limbs + 1,
        3 * short_limbs + 2,
        40 + 5 * short_limbs,
      ] {
      let short = mul_diff_all_nines(short_limbs)
      let long = mul_diff_all_nines(long_limbs)
      let expected = reference_mul_schoolbook(short, long)
      assert_true(
        sqrt_diff_same(dec_coeff_mul_unbalanced(short, long), expected),
      )
      assert_true(
        sqrt_diff_same(dec_coeff_multiply_repr(long, short), expected),
      )
    }
  }
}
