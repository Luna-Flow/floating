// A far addend, and the two ends of the exponent range, in an endpoint sum (IEEE
// 1788-2015 12.10: tightest).
//
// ORACLE (level A): every expected value is written out in this file as a
// hexadecimal coefficient and an exponent; no `bin_float` operation produces one.
// The code under test is compared with them by `BinFloat::compare` and
// `BinFloat::make` only.
//   c + 2^-1073741902 = (253 * 2^120 + 1) * 2^-1073741902
//                     = 0xFD, 29 hex zeros, 0x1, times 2^-1073741902 (128 bits)
//   the largest finite number of 200 bits = (2^200 - 1) * 2^(e_max + 1 - 200)
//                     = 50 hex digits F, times 2^1073741624
//
// Before the change the stand-in for a far addend (`far_addend_surrogate`) was made
// at one bit and rounded away to the quantum of one bit, `2^e_min`, much larger than
// the addend: `fma` was looser than the tightest interval by that unit (#629). The
// exact product and sum of `fma` were made at their own bit length, so a value
// above the range was clamped at the largest finite number of that many bits (#631).
//
// COST: the stand-in lies `max(65,536, precision of the rounding)` places under the
// large addend, whatever the precision label of the operands is (a value made with
// `exact_range` below the normal range carries a label of up to 2^28): the tests
// below bound the bit length of the aligned sum.

///|
fn fab_value(
  coefficient : UInt64,
  exponent : Int32,
  precision : Int32,
) -> @bin_float.BinFloat {
  let bits = Int32::max(
    precision,
    @bin_float.binary_implementation_e_min - exponent + 1,
  )
  @bin_float.BinFloat::make(
    @bin_float.BinCoeff::from_uint64(coefficient),
    exponent,
    bits,
  )
}

///|
fn fab_hex(
  text : String,
  exponent : Int32,
  precision : Int32,
) -> @bin_float.BinFloat {
  match @bin_float.BinCoeff::parse(text, radix=16) {
    Ok(coefficient) =>
      @bin_float.BinFloat::make(coefficient, exponent, precision)
    Err(error) => abort(error)
  }
}

///|
fn fab_zeros(n : Int32) -> String {
  let mut text = ""
  for _ in 0..<n {
    text = text + "0"
  }
  text
}

///|
/// c + 2^-1073741902 at 128 bits, written out.
fn fab_expected_sum() -> @bin_float.BinFloat {
  fab_hex("FD" + fab_zeros(29) + "1", -1073741902, 128)
}

///|
/// The largest finite number of 200 bits, written out.
fn fab_expected_max_200() -> @bin_float.BinFloat {
  let mut text = ""
  for _ in 0..<50 {
    text = text + "F"
  }
  fab_hex(text, 1073741624, 200)
}

///|
test "fma with a product far below the range floor adds one p-bit unit, not 2^e_min" {
  // c = 253 * 2^-1073741782 (8 bits, a normal value), p = 128: its unit is
  // 2^-1073741902; the product is about 2^-2147483600
  let precision = 128
  let c = fab_value(253UL, -1073741782, precision)
  let tiny = fab_value(1UL, -1073741800, precision)
  let a = BallFloat::from_bounds(tiny, tiny, precision~)
  let sum = a.fma(a, BallFloat::from_bounds(c, c, precision~))
  // the product is positive: the tightest lower bound is c itself
  assert_true(sum.lower_bound().compare(c) == 0)
  assert_true(sum.upper_bound().compare(fab_expected_sum()) == 0)
}

///|
test "add of a value far below the range floor is rounded to the unit of the precision" {
  let precision = 128
  let c = fab_value(253UL, -1073741782, precision)
  let tiny = fab_value(1UL, -1073741800 - 100000, precision)
  let a = BallFloat::from_bounds(c, c, precision~)
  let b = BallFloat::from_bounds(tiny, tiny, precision~)
  let sum = a.add(b)
  assert_true(sum.lower_bound().compare(c) == 0)
  assert_true(sum.upper_bound().compare(fab_expected_sum()) == 0)
}

///|
test "fma of a product above the range has the largest finite number of the precision as its lower bound" {
  // 3 * 2^(e_max - 1) times 3 is above the range: its lower bound was the largest
  // finite number of the 4 bits of the exact product, not of the precision
  let precision = 200
  let e_max = @bin_float.binary_implementation_e_max
  let a = @bin_float.BinFloat::make(
    @bin_float.BinCoeff::from_uint64(3UL),
    e_max - 1,
    precision,
  )
  let x = BallFloat::from_bounds(a, a, precision~)
  let three = BallFloat::from_int(3, precision~)
  let zero = BallFloat::from_bounds(
    @bin_float.BinFloat::zero(precision~),
    @bin_float.BinFloat::zero(precision~),
    precision~,
  )
  let r = x.fma(three, zero)
  assert_true(r.lower_bound().compare(fab_expected_max_200()) == 0)
  assert_true(r.upper_bound().classify() == FpClass::Infinity)
  // the sum above the range, the product exact and finite: [M, +inf] as well
  let sum = x.fma(BallFloat::from_int(1, precision~), x)
  assert_true(sum.lower_bound().compare(fab_expected_max_200()) == 0)
  assert_true(sum.upper_bound().classify() == FpClass::Infinity)
}

///|
/// The bit length of the coefficient of the sum `a + b` made by `exact_add` for an
/// endpoint sum rounded to `precision` bits.
fn fab_aligned_bits(
  a : @bin_float.BinFloat,
  b : @bin_float.BinFloat,
  precision : Int32,
  mode : BinaryRoundingMode,
) -> Int32 {
  exact_add(a, b, mode~, min_bits=precision, exact_range=true)
  .coefficient()
  .bit_length()
}

///|
test "a far addend is aligned over a bounded number of bits, whatever its precision label" {
  // 65,536 places of margin, the bits of the large addend, the 128 of the
  // precision and a few for the stand-in itself
  let bound = 65536 + 128 + 64 + 8
  let precision = 128
  let c = fab_value(253UL, -1073741782, precision)
  // (1) the product of the first test: its label is capped at 2^28
  let tiny = fab_value(1UL, -1073741800, precision)
  let product = exact_mul(
    tiny,
    tiny,
    mode=BinaryRoundingMode::RoundTowardPositive,
    exact_range=true,
  )
  assert_true(product.precision() > 100000000)
  for
    mode in [
      BinaryRoundingMode::RoundTowardPositive,
      BinaryRoundingMode::RoundTowardNegative,
    ] {
    assert_true(fab_aligned_bits(c, product, precision, mode) <= bound)
    assert_true(fab_aligned_bits(c, product.neg(), precision, mode) <= bound)
    // (2) the addend of the second test
    let far = fab_value(1UL, -1073741800 - 100000, precision)
    assert_true(fab_aligned_bits(c, far, precision, mode) <= bound)
    // (3) an operand that carries a precision of 2^28 (a user can pass one)
    let inflated = @bin_float.BinFloat::make(
      @bin_float.BinCoeff::from_uint64(5UL),
      -1000000,
      268435456,
    )
    let large = @bin_float.BinFloat::make(
      @bin_float.BinCoeff::from_uint64(7UL),
      1000000,
      268435456,
    )
    assert_true(fab_aligned_bits(large, inflated, precision, mode) <= bound)
    assert_true(fab_aligned_bits(inflated, large, precision, mode) <= bound)
  }
}

///|
test "add, sub and cancel with endpoints of an inflated precision stay cheap and tight" {
  let precision = 128
  let big = @bin_float.BinFloat::make(
    @bin_float.BinCoeff::from_uint64(7UL),
    1000000,
    268435456,
  )
  let small = @bin_float.BinFloat::make(
    @bin_float.BinCoeff::from_uint64(5UL),
    -1000000,
    268435456,
  )
  let x = BallFloat::from_bounds(big, big, precision~)
  let y = BallFloat::from_bounds(small, small, precision~)
  // 7 * 2^1000000 + 5 * 2^-1000000: the lower bound of the sum is 7 * 2^1000000
  let sum = x.add(y)
  assert_true(sum.lower_bound().compare(big) == 0)
  let difference = x.sub(y)
  assert_true(difference.upper_bound().compare(big) == 0)
  // widths 0 and 0: cancel gives a point only when the widths are equal; the
  // second interval is wider
  let z = BallFloat::from_bounds(small, big, precision~)
  assert_true(x.cancel_minus(z).is_entire())
}
