///|
fn arithmetic_interval(lo : Int32, hi : Int32) -> Interval {
  Interval::from_bounds(
    @binary.Binary::from_int(lo, precision=53),
    @binary.Binary::from_int(hi, precision=53),
    precision=53,
  )
}

///|
// oracle: A
// source: worked out by hand from the set of products (Table 9.1): [0, 0] times the whole line is {0} = [0, 0], and [1, +inf) times [-5, -1] is (-inf, -1] (the largest product is 1 * -1 = -1)
// shares: arithmetic_interval (Binary::from_int and Interval::from_bounds) builds the operands; Interval::equal, Binary::compare, classify and signum compare; the operation under test is the code under test
test "IEEE 1788 multiplication is tight for zero and unbounded intervals" {
  let zero = arithmetic_interval(0, 0)
  let entire = Interval::entire(precision=53)
  assert_true((zero * entire).equal(zero))
  let positive_half = Interval::from_bounds(
    @binary.Binary::one(precision=53),
    @binary.Binary::inf(precision=53),
    precision=53,
  )
  let negative = arithmetic_interval(-5, -1)
  let product = positive_half * negative
  assert_true(product.lower_bound().classify() == FpClass::Infinity)
  assert_true(product.lower_bound().signum() == Sign::Negative)
  assert_eq(product.upper_bound().compare(negative.upper_bound()), 0)
}

///|
// oracle: A
// source: worked out by hand from the set of quotients (Table 9.1): 1 / [0, 1] is [1, +inf) and 1 / [-1, 0] is (-inf, -1] (the zero denominator is a limit, not a value)
// shares: arithmetic_interval (Binary::from_int and Interval::from_bounds) builds the operands; Interval::equal, Binary::compare, classify and signum compare; the operation under test is the code under test
test "IEEE 1788 division keeps one-sided zero bounds tight" {
  let one = arithmetic_interval(1, 1)
  let nonnegative = arithmetic_interval(0, 1)
  let positive_result = one / nonnegative
  assert_eq(positive_result.lower_bound().compare(one.lower_bound()), 0)
  assert_true(positive_result.upper_bound().classify() == FpClass::Infinity)
  assert_true(positive_result.upper_bound().signum() == Sign::Positive)
  let nonpositive = arithmetic_interval(-1, 0)
  let negative_result = one / nonpositive
  assert_true(negative_result.lower_bound().classify() == FpClass::Infinity)
  assert_true(negative_result.lower_bound().signum() == Sign::Negative)
  assert_eq(negative_result.upper_bound().compare(one.lower_bound().neg()), 0)
}

///|
// oracle: A
// source: written out by hand: [0, 0] / [-1, 1] is {0} (0 / x = 0 for x != 0), and [-1, 1] / [0, 0] has no quotient, so it is Empty (Table 9.1)
// shares: arithmetic_interval (Binary::from_int and Interval::from_bounds) builds the operands; Interval::equal, Binary::compare, classify and signum compare; the operation under test is the code under test
test "IEEE 1788 division handles zero numerator and zero denominator" {
  let zero = arithmetic_interval(0, 0)
  let spanning = arithmetic_interval(-1, 1)
  assert_true((zero / spanning).equal(zero))
  assert_true((spanning / zero).is_empty())
}

///|
// oracle: A
// source: worked out by hand with exact dyadic values: 1 / [2, 4] = [1/4, 1/2], 1 / [-4, -2] = [-1/2, -1/4], [-2, 4] / [2, 4] = [-1, 2], 1 / [1, +inf) = [0, 1]
// shares: arithmetic_interval, Binary::make (the expected 1/4 and 1/2) and Interval::from_bounds build the operands; Binary::compare, is_zero and Interval::equal compare; the operation under test is the code under test
test "IEEE 1788 division reduces sign-definite quotients to two corners" {
  let quarter = @binary.Binary::make(@binary.BinCoeff::one(), -2, 53)
  let half = @binary.Binary::make(@binary.BinCoeff::one(), -1, 53)
  let positive = arithmetic_interval(1, 1) / arithmetic_interval(2, 4)
  assert_eq(positive.lower_bound().compare(quarter), 0)
  assert_eq(positive.upper_bound().compare(half), 0)
  let negative = arithmetic_interval(1, 1) / arithmetic_interval(-4, -2)
  assert_eq(negative.lower_bound().compare(half.neg()), 0)
  assert_eq(negative.upper_bound().compare(quarter.neg()), 0)
  let crossing = arithmetic_interval(-2, 4) / arithmetic_interval(2, 4)
  assert_true(crossing.equal(arithmetic_interval(-1, 2)))
  let one_sided = Interval::from_bounds(
    @binary.Binary::one(precision=53),
    @binary.Binary::inf(precision=53),
    precision=53,
  )
  let unbounded = arithmetic_interval(1, 1) / one_sided
  assert_true(unbounded.lower_bound().is_zero())
  assert_eq(
    unbounded.upper_bound().compare(@binary.Binary::one(precision=53)),
    0,
  )
}

///|
// oracle: A
// source: written out by hand: the largest binary64 is (2^53 - 1) * 2^971; adding [3, 4] to it gives the exact [max + 3, max + 4], whose lower end rounds down to max and whose upper end overflows to +inf, with the overflow and inexact flags set (directed rounding of IEEE 754-2008)
// shares: Binary::make, coeff_sub, coeff_shift_left and coeff_one build the largest binary64; arithmetic_interval builds the increment; IntervalContext::binary64 and apply_ctx are the code under test
test "binary64 context applies directed overflow bounds" {
  let ctx = IntervalContext::binary64()
  let max_finite = @binary.Binary::make(
    coeff_sub(coeff_shift_left(coeff_one(), 53), coeff_one()),
    971,
    53,
  )
  let source = Interval::from_bounds(max_finite, max_finite, precision=53)
  let increment = arithmetic_interval(3, 4)
  let (result, flags) = (source + increment).apply_ctx(ctx)
  assert_eq(result.lower_bound().compare(max_finite), 0)
  assert_true(result.upper_bound().classify() == FpClass::Infinity)
  assert_true(flags.overflow)
  assert_true(flags.inexact)
}

///|
// oracle: A
// source: written out by hand: with precision 4 and e_max 3 the smallest exponent is e_min = 1 - e_max = -2, the smallest subnormal is 2^(e_min - p + 1) = 2^-5, and the point 2^-7 lies below it, so the directed rounding gives [0, 2^-5] with the underflow and inexact flags
// shares: Binary::make, zero and Interval::from_bounds build the input and the expected ends; IntervalContext::new and apply_ctx are the code under test
test "binary context applies gradual directed underflow" {
  let ctx = IntervalContext::new(precision=4, e_max=3)
  let below_subnormal = @binary.Binary::make(@binary.BinCoeff::one(), -7, 4)
  let source = Interval::from_bounds(
    below_subnormal,
    below_subnormal,
    precision=8,
  )
  let (result, flags) = source.apply_ctx(ctx)
  let zero = @binary.Binary::zero(precision=4)
  let min_subnormal = @binary.Binary::make(@binary.BinCoeff::one(), -5, 4)
  assert_eq(result.lower_bound().compare(zero), 0)
  assert_eq(result.upper_bound().compare(min_subnormal), 0)
  assert_true(flags.underflow)
  assert_true(flags.inexact)
}

///|
// oracle: A
// source: worked out by hand from 12.12.5 (cancelPlus(x, y) = cancelMinus(x, -y), the ends being the differences of the ends, Entire when width(x) < width(y)): [-5, 0] cancelPlus [1, 5] = [-5 + 5, 0 + 1] = [0, 1]; [-5, 0] cancelMinus [-4, 0] = [-1, 0]; [-5, -1] cancelPlus [1, 6] has widths 4 < 5, so it is Entire
// shares: arithmetic_interval (Binary::from_int and Interval::from_bounds) builds the operands; Interval::equal, Binary::compare, classify and signum compare; the operation under test is the code under test
test "IEEE 1788 cancellation contracts compatible widths" {
  let left = arithmetic_interval(-5, 0)
  let right = arithmetic_interval(1, 5)
  assert_true(left.cancel_plus(right).equal(arithmetic_interval(0, 1)))
  let minuend = arithmetic_interval(-5, 0)
  let subtrahend = arithmetic_interval(-4, 0)
  assert_true(
    minuend.cancel_minus(subtrahend).equal(arithmetic_interval(-1, 0)),
  )
  assert_true(
    arithmetic_interval(-5, -1)
    .cancel_plus(arithmetic_interval(1, 6))
    .is_entire(),
  )
}

///|
// oracle: A
// source: worked out by hand: [-2, 3] times [4, 5] is [-10, 15], plus [1, 2] gives [-9, 17]; fma with an Empty addend is Empty; all values are exact integers, so the single rounding is not exercised here (the fma tables of interval_basics and bottom_table_check do exercise it)
// shares: arithmetic_interval (Binary::from_int and Interval::from_bounds) builds the operands; Interval::equal, Binary::compare, classify and signum compare; the operation under test is the code under test
test "IEEE 1788 fused multiply-add rounds only the final enclosure" {
  let left = arithmetic_interval(-2, 3)
  let multiplier = arithmetic_interval(4, 5)
  let addend = arithmetic_interval(1, 2)
  assert_true(left.fma(multiplier, addend).equal(arithmetic_interval(-9, 17)))
  assert_true(left.fma(multiplier, Interval::empty(precision=53)).is_empty())
}

///|
// oracle: A
// source: worked out by hand from the set of products: [0, 3] times [-2, 0] is [-6, 0], and [-3, -1] times [2, 4] is [-12, -2]
// shares: arithmetic_interval (Binary::from_int and Interval::from_bounds) builds the operands; Interval::equal, Binary::compare, classify and signum compare; the operation under test is the code under test
test "IEEE 1788 finite multiplication keeps sign-partition bounds" {
  let nonnegative = arithmetic_interval(0, 3)
  let nonpositive = arithmetic_interval(-2, 0)
  assert_true(nonnegative.mul(nonpositive).equal(arithmetic_interval(-6, 0)))
  assert_true(
    arithmetic_interval(-3, -1)
    .mul(arithmetic_interval(2, 4))
    .equal(arithmetic_interval(-12, -2)),
  )
}

///|
// oracle: A
// source: worked out by hand from the set of powers: [-2, 3]^3 = [-8, 27], [-2, 3]^2 = [0, 9], 0^-2 has no value (Empty), [0, 4]^-2 = [1/16, +inf) and [-4, 4]^-2 = [1/16, +inf) (the pole at 0 gives +inf), [-2, 3]^-3 contains the pole with both signs, so it is Entire
// shares: arithmetic_interval and Binary::make (the expected 1/16) build the operands; Interval::equal, is_empty, is_entire, Binary::compare and classify compare; pown is the code under test
test "IEEE 1788 pown uses directed endpoints across zero and poles" {
  assert_true(
    arithmetic_interval(-2, 3).pown(3).equal(arithmetic_interval(-8, 27)),
  )
  assert_true(
    arithmetic_interval(-2, 3).pown(2).equal(arithmetic_interval(0, 9)),
  )
  let zero = arithmetic_interval(0, 0)
  assert_true(zero.pown(-2).is_empty())
  let nonnegative = arithmetic_interval(0, 4).pown(-2)
  let one_sixteenth = @binary.Binary::make(@binary.BinCoeff::one(), -4, 53)
  assert_eq(nonnegative.lower_bound().compare(one_sixteenth), 0)
  assert_true(nonnegative.upper_bound().classify() == FpClass::Infinity)
  let crossing = arithmetic_interval(-4, 4).pown(-2)
  assert_eq(crossing.lower_bound().compare(one_sixteenth), 0)
  assert_true(crossing.upper_bound().classify() == FpClass::Infinity)
  assert_true(arithmetic_interval(-2, 3).pown(-3).is_entire())
}

///|
// oracle: A
// source: worked out by hand: [-3, -2]^2 = [4, 9]; [-3, -2]^-2 = [1/9, 1/4], where 1/4 is a 53-bit number and 1/9 lies between 0x1c71c71c71c71c * 2^-56 and 0x1c71c71c71c71d * 2^-56 (0x1c71c71c71c71c = floor(2^56 / 9), checked with Python fractions), so the lower end is the first
// shares: arithmetic_interval and Binary::make and BinCoeff::from_uint64 build the operands and the expected ends; Interval::equal and Binary::compare compare; pown is the code under test
test "IEEE 1788 pown preserves negative-half-axis monotonicity" {
  let negative = arithmetic_interval(-3, -2)
  assert_true(negative.pown(2).equal(arithmetic_interval(4, 9)))
  let reciprocal = negative.pown(-2)
  // [-3, -2]^-2 = [1/9, 1/4]: 1/9 lies between 0x1c71c71c71c71c * 2^-56 and 0x1c71c71c71c71d * 2^-56,
  // 1/4 is a number of 53 bits
  assert_true(reciprocal.lower_bound().compare(reciprocal.upper_bound()) <= 0)
  assert_eq(
    reciprocal
    .lower_bound()
    .compare(
      @binary.Binary::make(
        @binary.BinCoeff::from_uint64(0x1c71c71c71c71cUL),
        -56,
        53,
      ),
    ),
    0,
  )
  assert_eq(
    reciprocal
    .upper_bound()
    .compare(@binary.Binary::make(@binary.BinCoeff::one(), -2, 53)),
    0,
  )
}

///|
// oracle: A
// source: written out by hand: pown(-0, 3) has the lower bound -0 (a Level 1 value 0 is -0 by inf, +0 by sup, 12.12.8); [-inf, -1]^-1 = [-1, 0] with the lower end -1 and the upper end +0; 1^minInt = 1 and (-1)^minInt = 1; 2^minInt is below the binary range, so the enclosure is [0 (as -0), the smallest positive number 2^(e_min - 52)]
// shares: Binary::negative_zero, inf, from_int and Interval::from_int, from_bounds build the operands; Binary::compare, is_zero, is_sign_minus, coefficient and exponent2 compare; pown is the code under test
test "IEEE 1788 pown preserves infinity, signed zero, and Int min" {
  let negative_zero = @binary.Binary::negative_zero(precision=53)
  let signed_zero = Interval::from_bounds(
    negative_zero,
    negative_zero,
    precision=53,
  )
  assert_true(signed_zero.pown(3).lower_bound().is_negative_zero())
  let negative_unbounded = Interval::from_bounds(
    @binary.Binary::inf(negative=true, precision=53),
    @binary.Binary::from_int(-1, precision=53),
    precision=53,
  ).pown(-1)
  assert_true(
    negative_unbounded
    .lower_bound()
    .compare(@binary.Binary::from_int(-1, precision=53)) ==
    0,
  )
  // The old assertion claimed that `upper_bound` returns -0 here (the zero kept the sign of the
  // reciprocal of a negative number). That was wrong: 12.12.8 says that in a format with a
  // signed zero a Level 1 value of 0 is returned as -0 by `inf` and +0 by all other functions
  // of the subclause, `sup` included; the interval is a set, and the sign of a stored zero is
  // not part of it.
  assert_true(
    negative_unbounded.upper_bound().is_zero() &&
    !negative_unbounded.upper_bound().is_sign_minus(),
  )
  let minimum_exponent = -2147483647 - 1
  assert_true(
    Interval::from_int(1, precision=53)
    .pown(minimum_exponent)
    .equal(Interval::from_int(1, precision=53)),
  )
  assert_true(
    Interval::from_int(-1, precision=53)
    .pown(minimum_exponent)
    .equal(Interval::from_int(1, precision=53)),
  )
  // 2^(Int min) is below the binary implementation range, so the enclosure
  // widens outward to [0, smallest positive] instead of wrapping the exponent.
  let tiny = Interval::from_int(2, precision=53).pown(minimum_exponent)
  // the lower bound is the Level 1 value 0, which `inf` returns as -0 (12.12.8; the old
  // assertion claimed +0)
  assert_true(tiny.lower_bound().is_zero())
  assert_true(tiny.lower_bound().is_sign_minus())
  assert_eq(tiny.upper_bound().coefficient(), @binary.BinCoeff::one())
  assert_eq(tiny.upper_bound().exponent2(), @binary.binary_value_e_min - 52)
}

///|
// oracle: A
// source: written out by hand: the combination of the flag sets {inexact, underflow} and {overflow} has all three flags (logical or), and combining with the empty flag set does not change it
// shares: the IntervalFlags record literals build the inputs; combine and the getters are the code under test
test "IntervalFlags getters and combine accumulate endpoint status" {
  let left : IntervalFlags = {
    inexact: true,
    overflow: false,
    underflow: true,
  }
  let right : IntervalFlags = {
    inexact: false,
    overflow: true,
    underflow: false,
  }
  let combined = left.combine(right)
  assert_true(combined.inexact())
  assert_true(combined.overflow())
  assert_true(combined.underflow())
  assert_true(combined.combine(IntervalFlags::new()) == combined)
}
