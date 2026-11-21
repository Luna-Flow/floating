///|
/// Oracle of the short product `bin_coeff_mul_short`: level A. The expected
/// value of a row is computed by `tools/kernel_oracle.py` (CPython integers: the
/// exact product `a * b`, rounded to `precision` bits to nearest even, down and
/// up by the definitions of the roundings) and folded into a digest. The kernel
/// returns an approximation `H` of the product or declines; a returned `H`
/// must round, in the three ways, as the exact product does (rounding of `H`
/// written out in this file with `Coeff` shifts and bit tests, which have the
/// level A oracle of the regression digests), and the kernel must return when
/// the exact product is farther than `2 (m + 2)` units of the last limb from
/// every rounding boundary (the `must_return` field: the oracle's own bound, not
/// the kernel's test). Operands are regenerated from the seed with
/// `regression_value`; the rows are in `coeff_short_oracle_rows_wbtest.mbt`.
///
/// The precisions run from the start of the portable window (13 limbs) to one
/// limb above the end of the assembly window (385 limbs), operands within 64
/// bits of the precision, with shapes whose products lie next to rounding
/// boundaries (all ones, `2^k`, `2^k + 1`, sparse, zero limbs inside). The test
/// calls `bin_coeff_mul_short` directly at every size, so each state of the
/// limb tier (portable, C, assembly) is exercised by the row kernels it
/// selects; the production window is a choice of `bin_coeff_mul_short_ok`.

///|
fn short_oracle_strip(value : Coeff, exponent : Int32) -> (Coeff, Int32) {
  let zeros = value.ctz()
  (value.shift_right(zeros), exponent + zeros)
}

///|
fn short_oracle_run(row : Array[String]) -> Bool raise {
  let name = row[0]
  let precision = oracle_int(row[2])
  let left_bits = oracle_int(row[3])
  let right_bits = oracle_int(row[4])
  let random : RegressionRandom = { regression_state: oracle_u64(row[7]), }
  let left = regression_value(random, left_bits, oracle_int(row[5]))
  let right = regression_value(random, right_bits, oracle_int(row[6]))
  let must_return = row[9] == "1"
  let approximate = bin_coeff_mul_short(left, right, precision)
  if approximate.is_zero() {
    if must_return {
      fail(
        "\{name}: the short product declined far from every rounding boundary",
      )
    }
    return false
  }
  let limbs = bin_coeff_short_product_limbs(precision)
  let approximate_bits = approximate.bit_length()
  let shift = approximate_bits - precision
  let exponent = shift + left.bit_length() + right.bit_length() - 64 * limbs
  let kept = approximate.shift_right(shift)
  let round_bit = approximate.test_bit(shift - 1)
  // the returned value is decisive: the product is inexact and not halfway, so
  // to nearest the round bit decides and up is the truncation plus one
  let nearest = if round_bit { kept.add(Coeff::one()) } else { kept }
  let up = kept.add(Coeff::one())
  let mut state = 0xcbf29ce484222325UL
  for rounded in [nearest, kept, up] {
    let (stripped, stripped_exponent) = short_oracle_strip(rounded, exponent)
    state = regression_mix_int(
      regression_mix(state, stripped),
      stripped_exponent,
    )
  }
  if state != oracle_u64(row[10]) {
    fail("\{name}: the short product rounds differently from the exact product")
  }
  true
}

///|
fn short_oracle_run_where(where_ : String) -> (Int32, Int32) raise {
  let mut total = 0
  let mut returned = 0
  for row in oracle_rows(short_oracle_table) {
    if row[8] == where_ {
      total += 1
      if short_oracle_run(row) {
        returned += 1
      }
    }
  }
  (total, returned)
}

///|
test "oracle: short product rounds like the exact product, precisions up to 4,033 bits" {
  let (total, returned) = short_oracle_run_where("pr")
  assert_true(total > 100)
  // rows far from every boundary must return: at least those of `must_return`
  assert_true(returned > total / 4)
}

///|
#skip("binary gate stage: precisions up to 24,513 bits, the C and assembly windows")
test "oracle: short product rounds like the exact product, precisions from 6,000 to 24,513 bits" {
  let (total, returned) = short_oracle_run_where("gate")
  assert_true(total > 50)
  assert_true(returned > total / 4)
}
