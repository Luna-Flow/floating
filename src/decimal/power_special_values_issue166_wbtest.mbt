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
  assert_eq(power_issue166_case(d("0").power_ctx(d("-0"), ctx)), "1")
  assert_eq(power_issue166_case(d("1").power_ctx(d("NaN"), ctx)), "1")
  assert_eq(
    power_issue166_case(d("1").power_ctx(Decimal::signaling_nan(), ctx)),
    "nan invalid_operation",
  )
}

///|
test "decimal power identities across formats modes and checked routes" {
  let d = fn(text : String) { Decimal::from_string(text).unwrap() }
  let contexts = [
    DecimalContext::decimal32(),
    DecimalContext::decimal64(),
    DecimalContext::decimal128(),
  ]
  for base in [d("0"), d("-0"), d("Inf"), d("-Inf"), d("NaN")] {
    for ctx in contexts {
      assert_eq(power_issue166_case(base.power_ctx(d("0"), ctx)), "1")
      assert_eq(power_issue166_case(base.power_ctx(d("-0"), ctx)), "1")
    }
  }
  let down = DecimalContext::decimal32().with_rounding(
    @lf_arith.RoundingMode::TowardZero,
  )
  let ceiling = DecimalContext::decimal128().with_rounding(
    @lf_arith.RoundingMode::TowardPositive,
  )
  assert_eq(power_issue166_case(d("1").power_ctx(d("1.5"), down)), "1")
  assert_eq(power_issue166_case(d("1").power_ctx(d("Inf"), ceiling)), "1")

  let restricted = DecimalContext::new(extended=false).unwrap()
  assert_eq(power_issue166_case(d("0").power_ctx(d("0"), restricted)), "1")
  assert_eq(
    power_issue166_case(d("0").power_ctx(d("-0.5"), restricted)),
    "nan invalid_operation",
  )

  match d("0").try_power_ctx(d("0"), DecimalContext::decimal64()) {
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
}

///|
test "decimal power handles signed zero infinity and Int exponent limits" {
  let ctx = DecimalContext::decimal64()
  let d = fn(text : String) { Decimal::from_string(text).unwrap() }
  assert_eq(power_issue166_case(d("0").power_ctx(d("Inf"), ctx)), "0")
  assert_eq(power_issue166_case(d("-0").power_ctx(d("Inf"), ctx)), "0")
  assert_eq(power_issue166_case(d("0").power_ctx(d("-Inf"), ctx)), "inf")
  assert_eq(power_issue166_case(d("-0").power_ctx(d("-Inf"), ctx)), "inf")
  assert_eq(power_issue166_case(d("-0").pown_ctx(2147483647, ctx)), "-0")
  assert_eq(
    power_issue166_case(d("-0").pown_ctx(-2147483648, ctx)),
    "inf division_by_zero",
  )
  assert_eq(power_issue166_case(d("-Inf").pown_ctx(3, ctx)), "-inf")
  assert_eq(power_issue166_case(d("-Inf").pown_ctx(-3, ctx)), "-0")
  assert_eq(power_issue166_case(d("-Inf").pown_ctx(2, ctx)), "inf")
  assert_eq(power_issue166_case(d("-Inf").pown_ctx(-2, ctx)), "0")
}

///|
/// IEEE 754-2019 §9.2.1: pow(+1, y) is exact 1 for every y; pow(-1, +-Inf)
/// is 1; and an infinite exponent classifies finite bases by magnitude.
test "decimal power special values for one and infinite exponents" {
  let ctx = DecimalContext::decimal64()
  let d = fn(text : String) { Decimal::from_string(text).unwrap() }
  assert_eq(power_issue166_case(d("1").power_ctx(d("1.5"), ctx)), "1")
  assert_eq(power_issue166_case(d("-1").power_ctx(d("Inf"), ctx)), "1")
  assert_eq(power_issue166_case(d("-1").power_ctx(d("-Inf"), ctx)), "1")
  assert_eq(power_issue166_case(d("-0.5").power_ctx(d("Inf"), ctx)), "0")
  assert_eq(power_issue166_case(d("-2").power_ctx(d("Inf"), ctx)), "inf")
  assert_eq(power_issue166_case(d("-0.5").power_ctx(d("-Inf"), ctx)), "inf")
  assert_eq(power_issue166_case(d("-2").power_ctx(d("-Inf"), ctx)), "0")
  assert_eq(power_issue166_case(d("-Inf").power_ctx(d("Inf"), ctx)), "inf")
  assert_eq(power_issue166_case(d("-Inf").power_ctx(d("2.5"), ctx)), "inf")
  assert_eq(power_issue166_case(d("-Inf").power_ctx(d("-Inf"), ctx)), "0")
  assert_eq(power_issue166_case(d("-Inf").power_ctx(d("-2.5"), ctx)), "0")
}

///|
/// IEEE 754-2019 §9.2.1: a zero base with a negative nonzero exponent is an
/// infinity and raises DivisionByZero, including a nonintegral exponent.
test "decimal power negative exponent on zero raises division by zero" {
  let ctx = DecimalContext::decimal64()
  let d = fn(text : String) { Decimal::from_string(text).unwrap() }
  assert_eq(
    power_issue166_case(d("0").power_ctx(d("-0.5"), ctx)),
    "inf division_by_zero",
  )
}
