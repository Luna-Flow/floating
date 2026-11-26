///|
fn pow_rootn_contexts() -> Array[BinaryContext] {
  [
    BinaryContext::binary64(),
    BinaryContext::binary64(rounding=RoundTowardNegative),
    BinaryContext::binary64(rounding=RoundTowardPositive),
    BinaryContext::binary64(rounding=RoundTowardZero),
  ]
}

///|
fn pow_rootn_dyadic(coefficient : UInt64, exponent : Int32) -> Binary {
  Binary::make(BinCoeff::from_uint64(coefficient), exponent, 53)
}

///|
fn assert_exact_result(
  result : Result[(Binary, BinaryFlags), @def.ArithmeticError],
  expected : Binary,
  label : String,
) -> Unit raise {
  guard result is Ok((value, flags)) else { fail(label + ": unexpected error") }
  assert_identical(value, expected, msg=label)
  assert_eq(flags, BinaryFlags::new(), msg=label)
}

///|
// oracle: A, B
// source: rootn(8, -3) = 1/2, rootn(-8, -3) = -1/2 and rootn(2^130, 65) = 4 written out (exact, no flags); 27^(-1/3) = 1/3 is Binary::one() divided by 3 in binary64 with Binary::div_ctx (inexact)
// shares: pow_rootn_dyadic builds 1/2 and 2^130; assert_exact_result compares value and flags; Binary::div_ctx for 1/3
// primitives: Binary::div_ctx (level A through arith_rows_wbtest.mbt)
test "Binary rootn returns exact results for negative degrees" {
  let half = pow_rootn_dyadic(1UL, -1)
  for context in pow_rootn_contexts() {
    assert_exact_result(
      Binary::from_int(8).try_rootn_ctx(-3, context),
      half,
      "rootn(8, -3)",
    )
    assert_exact_result(
      Binary::from_int(-8).try_rootn_ctx(-3, context),
      half.neg(),
      "rootn(-8, -3)",
    )
    assert_exact_result(
      pow_rootn_dyadic(1UL, 130).try_rootn_ctx(65, context),
      Binary::from_int(4),
      "rootn(2^130, 65)",
    )
  }
  // 1 / 3 is not dyadic: the exact root 3 is divided with the context rounding.
  let (third, third_flags) = Binary::from_int(27).rootn_ctx(
    -3,
    BinaryContext::binary64(),
  )
  assert_identical(
    third,
    Binary::one().div_ctx(Binary::from_int(3), BinaryContext::binary64()).0,
  )
  assert_true(third_flags.inexact())
}

///|
// oracle: A
// source: written out: the exact value is 1 for rootn(1, n) for every n (1^(1/n) = 1), here with n = Int.min, exact and with no flag
// shares: assert_exact_result compares value and flags; Binary::one and try_rootn_ctx (the code under test)
test "Binary rootn handles Int.min magnitude exactly" {
  let minimum = -2147483647 - 1
  assert_exact_result(
    Binary::one().try_rootn_ctx(minimum, BinaryContext::binary64()),
    Binary::one(),
    "rootn(1, Int.min)",
  )
}

///|
// oracle: A
// source: written out from IEEE Std 754-2019 9.2.1 (pdftotext of the PDF, rootn): rootn(-inf, n) is -inf for odd n > 0, a quiet NaN with invalid operation for even n > 0 and for even n < 0, and -0 for odd n < 0; the library rule S4 (invalid is a value in the try_ form, not not_computed) is asserted as well
// shares: assert_exact_result compares value and flags; Binary::inf and negative_zero build the operands; try_rootn_ctx and rootn_ctx are the code under test
test "Binary rootn of negative infinity follows the degree parity" {
  let context = BinaryContext::binary64()
  let negative_infinity = Binary::inf(negative=true)
  for degree in [2, -2, 4, -4] {
    guard negative_infinity.try_rootn_ctx(degree, context)
      is Ok((nan, nan_flags)) else {
      fail("rootn(-inf, " + degree.to_string() + ") must be a value")
    }
    // S4: invalid is a value in the try_ form
    assert_true(nan.is_nan() && nan_flags.invalid_operation())
    assert_false(nan_flags.not_computed())
    let (value, flags) = negative_infinity.rootn_ctx(degree, context)
    assert_true(value.is_quiet_nan())
    assert_true(flags.invalid_operation())
  }
  assert_exact_result(
    negative_infinity.try_rootn_ctx(3, context),
    negative_infinity,
    "rootn(-inf, 3)",
  )
  assert_exact_result(
    negative_infinity.try_rootn_ctx(-3, context),
    Binary::negative_zero(),
    "rootn(-inf, -3)",
  )
}

///|
// oracle: A, B
// source: A: written out, exact values with no flag: 4^-1/2 = 1/2, 16^(3/4) = 8, 16^(-3/4) = 1/8, 36^(3/2) = 216, (81/256)^(5/4) = (3/4)^5 = 243/1024; B: 36^(-3/2) = 1/216, which is not dyadic, is the quotient of 1 by 216 with Binary::div_ctx in binary64 and is inexact
// shares: pow_rootn_dyadic builds the operands; assert_exact_result compares value and flags; Binary::from_int, one and div_ctx on the reference side; try_pow_ctx and pow_ctx are the code under test
// primitives: Binary::div_ctx (level A through arith_rows_wbtest.mbt: precisions from 2 to 4097, five directions)
test "Binary pow returns exact dyadic results without inexact" {
  for context in pow_rootn_contexts() {
    assert_exact_result(
      Binary::from_int(4).try_pow_ctx(pow_rootn_dyadic(1UL, -1).neg(), context),
      pow_rootn_dyadic(1UL, -1),
      "pow(4, -0.5)",
    )
    assert_exact_result(
      Binary::from_int(16).try_pow_ctx(pow_rootn_dyadic(3UL, -2), context),
      Binary::from_int(8),
      "pow(16, 0.75)",
    )
    assert_exact_result(
      Binary::from_int(16).try_pow_ctx(pow_rootn_dyadic(3UL, -2).neg(), context),
      pow_rootn_dyadic(1UL, -3),
      "pow(16, -0.75)",
    )
    assert_exact_result(
      Binary::from_int(36).try_pow_ctx(pow_rootn_dyadic(3UL, -1), context),
      Binary::from_int(216),
      "pow(36, 1.5)",
    )
    assert_exact_result(
      pow_rootn_dyadic(81UL, -8).try_pow_ctx(pow_rootn_dyadic(5UL, -2), context),
      pow_rootn_dyadic(243UL, -10),
      "pow(81/256, 1.25)",
    )
  }
  // A non-dyadic quotient 36^-1.5 = 1/216 is still rounded and inexact.
  let (reciprocal, flags) = Binary::from_int(36).pow_ctx(
    pow_rootn_dyadic(3UL, -1).neg(),
    BinaryContext::binary64(),
  )
  assert_identical(
    reciprocal,
    Binary::one().div_ctx(Binary::from_int(216), BinaryContext::binary64()).0,
  )
  assert_true(flags.inexact())
}

///|
// oracle: A
// source: written out from IEEE Std 754-2019 9.2.1 (pdftotext of the PDF, pow): pow(-1, +-inf) = 1, pow(x, +inf) = +0 for -1 < x < 1 and +inf for x < -1 (including -inf), pow(x, -inf) = +inf for -1 < x < 1 and +0 for x < -1 (including -inf), pow(+-0, -inf) = +inf and pow(+-0, +inf) = +0, all with no exception
// shares: assert_exact_result compares value and flags; Binary::inf, zero, negative_zero and from_int build the operands; to_hex builds the message; try_pow_ctx is the code under test
test "Binary pow follows the IEEE special cases for infinite exponents" {
  let context = BinaryContext::binary64()
  let positive_infinity = Binary::inf()
  let negative_infinity = Binary::inf(negative=true)
  let half = pow_rootn_dyadic(1UL, -1)
  let cases : Array[(Binary, Binary, Binary)] = [
    (Binary::from_int(-1), positive_infinity, Binary::one()),
    (Binary::from_int(-1), negative_infinity, Binary::one()),
    (half.neg(), positive_infinity, Binary::zero()),
    (half.neg(), negative_infinity, positive_infinity),
    (Binary::from_int(-2), positive_infinity, positive_infinity),
    (Binary::from_int(-2), negative_infinity, Binary::zero()),
    (Binary::zero(), negative_infinity, positive_infinity),
    (Binary::negative_zero(), negative_infinity, positive_infinity),
    (Binary::zero(), positive_infinity, Binary::zero()),
    (Binary::negative_zero(), positive_infinity, Binary::zero()),
    (negative_infinity, positive_infinity, positive_infinity),
    (negative_infinity, negative_infinity, Binary::zero()),
  ]
  for case in cases {
    let (base, exponent, expected) = case
    assert_exact_result(
      base.try_pow_ctx(exponent, context),
      expected,
      "pow(" + base.to_hex() + ", " + exponent.to_hex() + ")",
    )
  }
}

///|
// oracle: A
// source: written out from IEEE Std 754-2019 9.2.1 (pdftotext of the PDF, pow) and 7.4: the parity of 2^31 + 1 (odd) and 2^32 (even) decides pow(-inf, y), pow(-0, y) and pow(-1, y) (the sign of the result), pow(+-0, y) is infinite with divideByZero for y < 0 (-inf for an odd integer y, +inf otherwise) and zero for y > 0 (-0 for an odd integer y, +0 otherwise), pow(x < 0, non-integer y) is invalid, and (-2)^(2^32) = +inf and (-1.5)^(2^31 + 1) = -inf overflow (toward positive infinity the negative result is the largest finite value, written as finite and negative)
// shares: assert_exact_result compares value and flags; Binary::make builds the exponents; Binary::inf, zero, negative_zero and from_int build the operands; try_pow_ctx and pow_ctx are the code under test
test "Binary pow decides parity of large integer exponents" {
  let context = BinaryContext::binary64()
  let odd = Binary::make(BinCoeff::from_uint64((1UL << 31) + 1UL), 0, 53)
  let even = Binary::make(BinCoeff::one(), 32, 53)
  let positive_infinity = Binary::inf()
  let negative_infinity = Binary::inf(negative=true)
  let cases : Array[(Binary, Binary, Binary)] = [
    (negative_infinity, odd, negative_infinity),
    (negative_infinity, odd.neg(), Binary::negative_zero()),
    (negative_infinity, even, positive_infinity),
    (negative_infinity, even.neg(), Binary::zero()),
    (negative_infinity, pow_rootn_dyadic(1UL, -1), positive_infinity),
    (negative_infinity, pow_rootn_dyadic(3UL, -2).neg(), Binary::zero()),
    (Binary::negative_zero(), odd, Binary::negative_zero()),
    (Binary::negative_zero(), even, Binary::zero()),
    (Binary::negative_zero(), pow_rootn_dyadic(3UL, -2), Binary::zero()),
    (Binary::from_int(-1), odd, Binary::one().neg()),
    (Binary::from_int(-1), even, Binary::one()),
  ]
  for case in cases {
    let (base, exponent, expected) = case
    assert_exact_result(
      base.try_pow_ctx(exponent, context),
      expected,
      "pow(" + base.to_hex() + ", " + exponent.to_hex() + ")",
    )
  }
  for
    case in [
      (odd.neg(), Binary::inf(negative=true)),
      (pow_rootn_dyadic(3UL, -2).neg(), positive_infinity),
    ] {
    let (exponent, expected) = case
    let (value, flags) = Binary::negative_zero().pow_ctx(exponent, context)
    assert_identical(value, expected)
    assert_true(flags.division_by_zero())
  }
  // (-2)^(2^32) overflows to +inf; (-1.5)^(2^31 + 1) overflows to -inf, or
  // to -max under round toward positive.
  let (even_power, even_flags) = Binary::from_int(-2).pow_ctx(even, context)
  assert_identical(even_power, positive_infinity)
  assert_true(even_flags.overflow())
  let minus_three_halves = pow_rootn_dyadic(3UL, -1).neg()
  let (odd_power, odd_flags) = minus_three_halves.pow_ctx(odd, context)
  assert_identical(odd_power, negative_infinity)
  assert_true(odd_flags.overflow())
  let (upward_power, upward_flags) = minus_three_halves.pow_ctx(
    odd,
    BinaryContext::binary64(rounding=RoundTowardPositive),
  )
  assert_true(upward_power.classify() == FpClass::Finite)
  assert_true(upward_power.is_sign_minus())
  assert_true(upward_flags.overflow())
  // A negative base with a non-integer exponent stays invalid.
  guard Binary::from_int(-4).try_pow_ctx(pow_rootn_dyadic(1UL, -1), context)
    is Ok((nan, nan_flags)) else {
    fail("pow(-4, 0.5) must be a value")
  }
  assert_true(nan.is_nan() && nan_flags.invalid_operation())
  assert_false(nan_flags.not_computed())
}

///|
/// The exactness check must also fire for a large dyadic exponent. A base
/// `c * 2^e` with a non-integer exponent `m / 2^k` is dyadic exactly when
/// `2^k` divides `e` and `c` is a perfect `2^k`-th power, so 4^2048.5 is
/// exactly 2^4097 and 16^512.25 is exactly 2^2049. The Ziv loop can never
/// certify any of these, because its enclosure straddles the exact value:
/// without the check every attempt is wasted and the refinement budget is
/// exhausted (#53).

///|
// oracle: A
// source: written out: 4^(3/2) = 2^3, 4^(4097/2) = 2^4097, 16^(2049/4) = 2^2049, (1/4)^(3/2) = 2^-3 and 9^(21/2) = 3^21 = 10460353203, exact with no flag in four directions at precisions 64, 128, 192 and 288 (#53: the Ziv loop alone cannot certify an exact value)
// shares: assert_exact_result compares value and flags; Binary::make builds the expected values; pow_rootn_dyadic and Binary::from_int build the operands; try_pow_ctx is the code under test
test "Binary pow finds exact powers for large dyadic exponents" {
  let cases = [
    (Binary::from_int(4), pow_rootn_dyadic(3UL, -1), 1UL, 3),
    (Binary::from_int(4), pow_rootn_dyadic(4097UL, -1), 1UL, 4097),
    (Binary::from_int(16), pow_rootn_dyadic(2049UL, -2), 1UL, 2049),
    (pow_rootn_dyadic(1UL, -2), pow_rootn_dyadic(3UL, -1), 1UL, -3),
    // A base whose odd part is not one: 9^10.5 is exactly 3^21.
    (Binary::from_int(9), pow_rootn_dyadic(21UL, -1), 10460353203UL, 0),
  ]
  for work in [64, 128, 192, 288] {
    for
      mode in [
        BinaryRoundingMode::RoundTiesToEven,
        BinaryRoundingMode::RoundTowardNegative,
        BinaryRoundingMode::RoundTowardPositive,
        BinaryRoundingMode::RoundTowardZero,
      ] {
      let context = BinaryContext::new(precision=work, rounding=mode)
      for case in cases {
        let (base, exponent, coefficient, scale) = case
        assert_exact_result(
          base.try_pow_ctx(exponent, context),
          Binary::make(BinCoeff::from_uint64(coefficient), scale, work),
          "pow at precision \{work}",
        )
      }
    }
  }
}
