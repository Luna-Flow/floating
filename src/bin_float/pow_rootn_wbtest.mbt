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
fn pow_rootn_dyadic(coefficient : UInt64, exponent : Int) -> BinFloat {
  BinFloat::make(BinCoeff::from_uint64(coefficient), exponent, 53)
}

///|
fn assert_exact_result(
  result : Result[(BinFloat, BinaryFlags), @def.ArithmeticError],
  expected : BinFloat,
  label : String,
) -> Unit raise {
  guard result is Ok((value, flags)) else { fail(label + ": unexpected error") }
  assert_eq(value, expected, msg=label)
  assert_eq(flags, BinaryFlags::new(), msg=label)
}

///|
test "BinFloat rootn returns exact results for negative degrees" {
  let half = pow_rootn_dyadic(1UL, -1)
  for context in pow_rootn_contexts() {
    assert_exact_result(
      BinFloat::from_int(8).try_rootn_ctx(-3, context),
      half,
      "rootn(8, -3)",
    )
    assert_exact_result(
      BinFloat::from_int(-8).try_rootn_ctx(-3, context),
      half.neg(),
      "rootn(-8, -3)",
    )
    assert_exact_result(
      pow_rootn_dyadic(1UL, 130).try_rootn_ctx(65, context),
      BinFloat::from_int(4),
      "rootn(2^130, 65)",
    )
  }
  // 1 / 3 is not dyadic: the exact root 3 is divided with the context rounding.
  let (third, third_flags) = BinFloat::from_int(27).rootn_ctx(
    -3,
    BinaryContext::binary64(),
  )
  assert_eq(
    third,
    BinFloat::one().div_ctx(BinFloat::from_int(3), BinaryContext::binary64()).0,
  )
  assert_true(third_flags.inexact())
}

///|
test "BinFloat rootn of negative infinity follows the degree parity" {
  let context = BinaryContext::binary64()
  let negative_infinity = BinFloat::inf(Sign::Negative)
  for degree in [2, -2, 4, -4] {
    guard negative_infinity.try_rootn_ctx(degree, context) is Err(error) else {
      fail("rootn(-inf, " + degree.to_string() + ") must be invalid")
    }
    assert_true(error.is_domain_error())
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
    BinFloat::negative_zero(),
    "rootn(-inf, -3)",
  )
}

///|
test "BinFloat pow returns exact dyadic results without inexact" {
  for context in pow_rootn_contexts() {
    assert_exact_result(
      BinFloat::from_int(4).try_pow_ctx(
        pow_rootn_dyadic(1UL, -1).neg(),
        context,
      ),
      pow_rootn_dyadic(1UL, -1),
      "pow(4, -0.5)",
    )
    assert_exact_result(
      BinFloat::from_int(16).try_pow_ctx(pow_rootn_dyadic(3UL, -2), context),
      BinFloat::from_int(8),
      "pow(16, 0.75)",
    )
    assert_exact_result(
      BinFloat::from_int(16).try_pow_ctx(
        pow_rootn_dyadic(3UL, -2).neg(),
        context,
      ),
      pow_rootn_dyadic(1UL, -3),
      "pow(16, -0.75)",
    )
    assert_exact_result(
      BinFloat::from_int(36).try_pow_ctx(pow_rootn_dyadic(3UL, -1), context),
      BinFloat::from_int(216),
      "pow(36, 1.5)",
    )
    assert_exact_result(
      pow_rootn_dyadic(81UL, -8).try_pow_ctx(pow_rootn_dyadic(5UL, -2), context),
      pow_rootn_dyadic(243UL, -10),
      "pow(81/256, 1.25)",
    )
  }
  // A non-dyadic quotient 36^-1.5 = 1/216 is still rounded and inexact.
  let (reciprocal, flags) = BinFloat::from_int(36).pow_ctx(
    pow_rootn_dyadic(3UL, -1).neg(),
    BinaryContext::binary64(),
  )
  assert_eq(
    reciprocal,
    BinFloat::one().div_ctx(BinFloat::from_int(216), BinaryContext::binary64()).0,
  )
  assert_true(flags.inexact())
}

///|
test "BinFloat pow follows the IEEE special cases for infinite exponents" {
  let context = BinaryContext::binary64()
  let positive_infinity = BinFloat::inf(Sign::Positive)
  let negative_infinity = BinFloat::inf(Sign::Negative)
  let half = pow_rootn_dyadic(1UL, -1)
  let cases : Array[(BinFloat, BinFloat, BinFloat)] = [
    (BinFloat::from_int(-1), positive_infinity, BinFloat::one()),
    (BinFloat::from_int(-1), negative_infinity, BinFloat::one()),
    (half.neg(), positive_infinity, BinFloat::zero()),
    (half.neg(), negative_infinity, positive_infinity),
    (BinFloat::from_int(-2), positive_infinity, positive_infinity),
    (BinFloat::from_int(-2), negative_infinity, BinFloat::zero()),
    (BinFloat::zero(), negative_infinity, positive_infinity),
    (BinFloat::negative_zero(), negative_infinity, positive_infinity),
    (BinFloat::zero(), positive_infinity, BinFloat::zero()),
    (BinFloat::negative_zero(), positive_infinity, BinFloat::zero()),
    (negative_infinity, positive_infinity, positive_infinity),
    (negative_infinity, negative_infinity, BinFloat::zero()),
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
test "BinFloat pow decides parity of large integer exponents" {
  let context = BinaryContext::binary64()
  let odd = BinFloat::make(BinCoeff::from_uint64((1UL << 31) + 1UL), 0, 53)
  let even = BinFloat::make(BinCoeff::one(), 32, 53)
  let positive_infinity = BinFloat::inf(Sign::Positive)
  let negative_infinity = BinFloat::inf(Sign::Negative)
  let cases : Array[(BinFloat, BinFloat, BinFloat)] = [
    (negative_infinity, odd, negative_infinity),
    (negative_infinity, odd.neg(), BinFloat::negative_zero()),
    (negative_infinity, even, positive_infinity),
    (negative_infinity, even.neg(), BinFloat::zero()),
    (negative_infinity, pow_rootn_dyadic(1UL, -1), positive_infinity),
    (negative_infinity, pow_rootn_dyadic(3UL, -2).neg(), BinFloat::zero()),
    (BinFloat::negative_zero(), odd, BinFloat::negative_zero()),
    (BinFloat::negative_zero(), even, BinFloat::zero()),
    (BinFloat::negative_zero(), pow_rootn_dyadic(3UL, -2), BinFloat::zero()),
    (BinFloat::from_int(-1), odd, BinFloat::one().neg()),
    (BinFloat::from_int(-1), even, BinFloat::one()),
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
      (odd.neg(), BinFloat::inf(Sign::Negative)),
      (pow_rootn_dyadic(3UL, -2).neg(), positive_infinity),
    ] {
    let (exponent, expected) = case
    let (value, flags) = BinFloat::negative_zero().pow_ctx(exponent, context)
    assert_eq(value, expected)
    assert_true(flags.division_by_zero())
  }
  // (-2)^(2^32) overflows to +inf; (-1.5)^(2^31 + 1) overflows to -inf, or
  // to -max under round toward positive.
  let (even_power, even_flags) = BinFloat::from_int(-2).pow_ctx(even, context)
  assert_eq(even_power, positive_infinity)
  assert_true(even_flags.overflow())
  let minus_three_halves = pow_rootn_dyadic(3UL, -1).neg()
  let (odd_power, odd_flags) = minus_three_halves.pow_ctx(odd, context)
  assert_eq(odd_power, negative_infinity)
  assert_true(odd_flags.overflow())
  let (upward_power, upward_flags) = minus_three_halves.pow_ctx(
    odd,
    BinaryContext::binary64(rounding=RoundTowardPositive),
  )
  assert_true(upward_power.classify() == FpClass::Finite)
  assert_true(upward_power.is_negative())
  assert_true(upward_flags.overflow())
  // A negative base with a non-integer exponent stays invalid.
  guard BinFloat::from_int(-4).try_pow_ctx(pow_rootn_dyadic(1UL, -1), context)
    is Err(error) else {
    fail("pow(-4, 0.5) must be invalid")
  }
  assert_true(error.is_domain_error())
}
