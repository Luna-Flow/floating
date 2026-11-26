///|
fn power_issue166_case(result : (Decimal, DecimalFlags)) -> String {
  let (value, flags) = result
  let mut text = value.to_string()
  if flags.inexact {
    text = text + " inexact"
  }
  if flags.invalid_operation {
    text = text + " invalid_operation"
  }
  if flags.division_by_zero {
    text = text + " division_by_zero"
  }
  text
}

///|
/// IEEE 754-2019 §9.2.1: x^+0 and x^-0 are 1 for every x, including zero,
/// infinity, and NaN; pown(+-0, n<0) is an infinity with DivisionByZero;
/// pown(+-0, 0) is 1.
// oracle: A
// source: IEEE 754-2019 9.2.1 (pow and pown lists): x^+-0 and pown(x, 0) are 1 for every x that is not a signaling NaN, including zero, infinity and a quiet NaN; pown(+-0, n < 0) is an infinity with divideByZero (negative for -0 and odd n); a signaling NaN gives a quiet NaN with invalid operation; written out
// shares: Decimal::from_string (the local d: builds the operands), to_string and power_issue166_case (print value and flags), pow_ctx and pown_ctx (the code under test)
test "decimal power special values for zero exponents" {
  let ctx = DecimalContext::decimal64()
  let d = fn(text : String) { Decimal::from_string(text).unwrap() }
  assert_eq(
    power_issue166_case(d("-0").pown_ctx(-1, ctx)),
    "-inf division_by_zero",
  )
  assert_eq(
    power_issue166_case(d("-0").pown_ctx(-2, ctx)),
    "inf division_by_zero",
  )
  assert_eq(power_issue166_case(d("0").pown_ctx(0, ctx)), "1")
  assert_eq(power_issue166_case(d("NaN").pown_ctx(0, ctx)), "1")
  assert_eq(
    power_issue166_case(Decimal::signaling_nan().pown_ctx(0, ctx)),
    "nan invalid_operation",
  )
  assert_eq(power_issue166_case(d("0").pow_ctx(d("-0"), ctx)), "1")
  assert_eq(power_issue166_case(d("1").pow_ctx(d("NaN"), ctx)), "1")
  assert_eq(
    power_issue166_case(d("1").pow_ctx(Decimal::signaling_nan(), ctx)),
    "nan invalid_operation",
  )
  assert_eq(
    power_issue166_case(
      Decimal::signaling_nan().pow_ctx(Decimal::quiet_nan(), ctx),
    ),
    "nan invalid_operation",
  )
  assert_eq(
    power_issue166_case(
      Decimal::quiet_nan().pow_ctx(Decimal::signaling_nan(), ctx),
    ),
    "nan invalid_operation",
  )
}

///|
// oracle: A, S
// source: IEEE 754-2019 9.2.1: pow(x, +-0) is 1 for zero, infinite and NaN bases in decimal32, decimal64 and decimal128, pow(+1, y) is 1 for y = 1.5 and +inf in any direction; the checked routes (pow_int_checked, pow_nat_checked) return Ok 1 for exponent zero, a division-by-zero error for a negative power of zero and a domain error for a signaling NaN: that mapping of statuses to error kinds is the library's API (level S)
// shares: Decimal::from_string (the local d: builds the operands), to_string and power_issue166_case (print value and flags), pow_ctx and pown_ctx (the code under test), pow_int_checked, pow_nat_checked and try_pow_ctx
test "decimal power identities across formats modes and checked routes" {
  let d = fn(text : String) { Decimal::from_string(text).unwrap() }
  let contexts = [
    DecimalContext::decimal32(),
    DecimalContext::decimal64(),
    DecimalContext::decimal128(),
  ]
  for base in [d("0"), d("-0"), d("Inf"), d("-Inf"), d("NaN")] {
    for ctx in contexts {
      assert_eq(power_issue166_case(base.pow_ctx(d("0"), ctx)), "1")
      assert_eq(power_issue166_case(base.pow_ctx(d("-0"), ctx)), "1")
    }
  }
  let down = DecimalContext::decimal32().with_rounding(
    DecimalRoundingMode::RoundTowardZero,
  )
  let ceiling = DecimalContext::decimal128().with_rounding(
    DecimalRoundingMode::RoundTowardPositive,
  )
  assert_eq(power_issue166_case(d("1").pow_ctx(d("1.5"), down)), "1")
  assert_eq(power_issue166_case(d("1").pow_ctx(d("Inf"), ceiling)), "1")

  match d("0").try_pow_ctx(d("0"), DecimalContext::decimal64()) {
    Ok((value, flags)) => {
      assert_eq(value.to_string(), "1")
      assert_false(flags.has_error())
    }
    Err(_) => fail("zero to zero should be a defined IEEE result")
  }
  match Decimal::signaling_nan().try_pown_ctx(0, DecimalContext::decimal64()) {
    Ok((value, flags)) => {
      assert_true(value.is_quiet_nan())
      assert_true(flags.invalid_operation)
    }
    Err(_) => fail("signaling NaN power should return a defined IEEE result")
  }
  match d("0").pow_int_checked(0, @lf_arith.ArithmeticContext::new(16)) {
    Ok(value) => assert_eq(value.to_string(), "1")
    Err(_) => fail("checked integer zero power should be defined as one")
  }
  match d("NaN").pow_nat_checked(0U, @lf_arith.ArithmeticContext::new(16)) {
    Ok(value) => assert_eq(value.to_string(), "1")
    Err(_) => fail("checked NaN zero power should be defined as one")
  }
  match d("0").pow_int_checked(-1, @lf_arith.ArithmeticContext::new(16)) {
    Err(error) => assert_true(error.is_division_by_zero())
    Ok(_) =>
      fail("checked negative power of zero should report division by zero")
  }
  match
    Decimal::signaling_nan().pow_nat_checked(
      1U,
      @lf_arith.ArithmeticContext::new(16),
    ) {
    Err(error) => assert_true(error.is_domain_error())
    Ok(_) =>
      fail("checked power with signaling NaN should report a domain error")
  }
  match
    Decimal::signaling_nan().pow_int_checked(
      0,
      @lf_arith.ArithmeticContext::new(16),
    ) {
    Err(error) => assert_true(error.is_domain_error())
    Ok(_) => fail("checked zero power with signaling NaN should be invalid")
  }
}

///|
// oracle: A
// source: IEEE 754-2019 9.2.1 (pow and pown lists): pow(+-0, +inf) is +0, pow(+-0, -inf) is +inf, pown(-0, 2147483647) is -0, pown(-0, -2147483648) is +inf with divideByZero, pown(+-inf, n) by the sign rules of odd and even n at the Int32 limits, pow(-0, 1E+30) is +0 and pow(-1, 1E+30) is 1; written out
// shares: Decimal::from_string (the local d: builds the operands), to_string and power_issue166_case (print value and flags), pow_ctx and pown_ctx (the code under test)
test "decimal power handles signed zero infinity and Int exponent limits" {
  let ctx = DecimalContext::decimal64()
  let d = fn(text : String) { Decimal::from_string(text).unwrap() }
  assert_eq(power_issue166_case(d("0").pow_ctx(d("Inf"), ctx)), "0")
  assert_eq(power_issue166_case(d("-0").pow_ctx(d("Inf"), ctx)), "0")
  assert_eq(power_issue166_case(d("0").pow_ctx(d("-Inf"), ctx)), "inf")
  assert_eq(power_issue166_case(d("-0").pow_ctx(d("-Inf"), ctx)), "inf")
  assert_eq(power_issue166_case(d("-0").pown_ctx(2147483647, ctx)), "-0")
  assert_eq(
    power_issue166_case(d("-0").pown_ctx(-2147483648, ctx)),
    "inf division_by_zero",
  )
  assert_eq(power_issue166_case(d("-Inf").pown_ctx(3, ctx)), "-inf")
  assert_eq(power_issue166_case(d("-Inf").pown_ctx(-3, ctx)), "-0")
  assert_eq(power_issue166_case(d("-Inf").pown_ctx(2, ctx)), "inf")
  assert_eq(power_issue166_case(d("-Inf").pown_ctx(-2, ctx)), "0")
  assert_eq(power_issue166_case(d("-Inf").pown_ctx(2147483647, ctx)), "-inf")
  assert_eq(power_issue166_case(d("-Inf").pown_ctx(-2147483648, ctx)), "0")
  assert_eq(power_issue166_case(d("Inf").pown_ctx(2147483647, ctx)), "inf")
  assert_eq(power_issue166_case(d("Inf").pown_ctx(-2147483648, ctx)), "0")
  assert_eq(power_issue166_case(d("-0").pow_ctx(d("1E+30"), ctx)), "0")
  assert_eq(power_issue166_case(d("-1").pow_ctx(d("1E+30"), ctx)), "1")
}

///|
/// IEEE 754-2019 §9.2.1: pow(+1, y) is exact 1 for every y; pow(-1, +-Inf)
/// is 1; and an infinite exponent classifies finite bases by magnitude.
// oracle: A
// source: IEEE 754-2019 9.2.1 (pow list): pow(+1, y) is 1, pow(-1, +-inf) is 1, pow(x, +inf) is +0 for -1 < x < 1 and +inf for |x| > 1 (also for -inf), pow(x, -inf) is +inf for -1 < x < 1 and +0 for |x| > 1, pow(-inf, y) for finite y > 0 that is not an odd integer is +inf and for y < 0 it is +0; written out
// shares: Decimal::from_string (the local d: builds the operands), to_string and power_issue166_case (print value and flags), pow_ctx and pown_ctx (the code under test)
test "decimal power special values for one and infinite exponents" {
  let ctx = DecimalContext::decimal64()
  let d = fn(text : String) { Decimal::from_string(text).unwrap() }
  assert_eq(power_issue166_case(d("1").pow_ctx(d("1.5"), ctx)), "1")
  assert_eq(power_issue166_case(d("-1").pow_ctx(d("Inf"), ctx)), "1")
  assert_eq(power_issue166_case(d("-1").pow_ctx(d("-Inf"), ctx)), "1")
  assert_eq(power_issue166_case(d("-0.5").pow_ctx(d("Inf"), ctx)), "0")
  assert_eq(power_issue166_case(d("-2").pow_ctx(d("Inf"), ctx)), "inf")
  assert_eq(power_issue166_case(d("-0.5").pow_ctx(d("-Inf"), ctx)), "inf")
  assert_eq(power_issue166_case(d("-2").pow_ctx(d("-Inf"), ctx)), "0")
  assert_eq(power_issue166_case(d("-Inf").pow_ctx(d("Inf"), ctx)), "inf")
  assert_eq(power_issue166_case(d("-Inf").pow_ctx(d("2.5"), ctx)), "inf")
  assert_eq(power_issue166_case(d("-Inf").pow_ctx(d("-Inf"), ctx)), "0")
  assert_eq(power_issue166_case(d("-Inf").pow_ctx(d("-2.5"), ctx)), "0")
}

///|
/// IEEE 754-2019 §9.2.1: a zero base with a negative nonzero exponent is an
/// infinity and raises DivisionByZero, including a nonintegral exponent.
// oracle: A
// source: IEEE 754-2019 9.2.1 (pow list): pow(+-0, y) is +inf and signals divideByZero for finite y < 0 that is not an odd integer, here y = -0.5; written out
// shares: Decimal::from_string (the local d: builds the operands), to_string and power_issue166_case (print value and flags), pow_ctx and pown_ctx (the code under test)
test "decimal power negative exponent on zero raises division by zero" {
  let ctx = DecimalContext::decimal64()
  let d = fn(text : String) { Decimal::from_string(text).unwrap() }
  assert_eq(
    power_issue166_case(d("0").pow_ctx(d("-0.5"), ctx)),
    "inf division_by_zero",
  )
}
