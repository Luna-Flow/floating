///|
fn special_case(result : (Decimal, DecimalFlags)) -> String {
  let (value, flags) = result
  let mut text = value.to_string()
  if flags.inexact {
    text = text + " inexact"
  }
  if flags.invalid_operation {
    text = text + " invalid"
  }
  if flags.division_by_zero {
    text = text + " division_by_zero"
  }
  text
}

///|
/// IEEE 754-2019 9.2.1: atan2 of a zero or infinite operand is an exact zero
/// or a multiple of pi/4 carrying the ordinate's sign. Infinite operands used
/// to abort the process inside the certified ball evaluation, and
/// atan2(+-0, -0) returned NaN.
// oracle: A
// source: IEEE 754-2019 9.2.1 (atan2 list, read from the PDF text): atan2(+-0, -0) is +-pi, atan2(-0, x < 0) is -pi, atan2(-0, +0) is -0, atan2(+inf, 1) is pi/2, atan2(-inf, -0) is -pi/2, atan2(1, -inf) is pi, atan2(-1, +inf) is -0, atan2(+inf, +inf) is pi/4, atan2(-inf, -inf) is -3pi/4, a NaN operand gives NaN; the 16-digit values pi = 3.141592653589793, pi/2 = 1.570796326794897, pi/4 = 0.7853981633974483, 3pi/4 = 2.356194490192345 are the correctly rounded digits (CPython decimal at 60 digits agrees)
// shares: special_case (prints value and flags through to_string), Decimal::from_string (the local d: builds the operands), atan2_ctx, cosh_ctx, log2_ctx, log1p_ctx and acosh_ctx (the code under test)
test "decimal atan2 handles zero and infinite operands" {
  let ctx = DecimalContext::decimal64()
  let d = fn(text : String) { Decimal::from_string(text).unwrap() }
  let atan2 = fn(y : String, x : String) {
    special_case(d(y).atan2_ctx(d(x), ctx))
  }
  assert_eq(atan2("0", "-0"), "3.141592653589793 inexact")
  assert_eq(atan2("-0", "-0"), "-3.141592653589793 inexact")
  assert_eq(atan2("-0", "-1"), "-3.141592653589793 inexact")
  assert_eq(atan2("-0", "0"), "-0")
  assert_eq(atan2("Inf", "1"), "1.570796326794897 inexact")
  assert_eq(atan2("-Inf", "-0"), "-1.570796326794897 inexact")
  assert_eq(atan2("1", "-Inf"), "3.141592653589793 inexact")
  assert_eq(atan2("-1", "Inf"), "-0")
  assert_eq(atan2("Inf", "Inf"), "0.7853981633974483 inexact")
  assert_eq(atan2("-Inf", "-Inf"), "-2.356194490192345 inexact")
  assert_eq(atan2("NaN", "Inf"), "nan")
}

///|
/// cosh(-inf), log2(+inf) and log1p(+inf) are exactly +inf with no exception
/// (IEEE 754-2019 9.2.1); they returned NaN with invalid_operation.
// oracle: A
// source: IEEE 754-2019 9.2.1: cosh(-inf) is +inf, log2(+inf) and log1p(+inf) are +inf with no exception; the logarithm and acosh of -inf are outside the domain (Table 9.1): NaN with invalid operation; written out
// shares: special_case (prints value and flags through to_string), Decimal::from_string (the local d: builds the operands), atan2_ctx, cosh_ctx, log2_ctx, log1p_ctx and acosh_ctx (the code under test)
test "decimal cosh log2 and log1p of infinities" {
  let ctx = DecimalContext::decimal64()
  let d = fn(text : String) { Decimal::from_string(text).unwrap() }
  assert_eq(special_case(d("-Inf").cosh_ctx(ctx)), "inf")
  assert_eq(special_case(d("Inf").log2_ctx(ctx)), "inf")
  assert_eq(special_case(d("Inf").log1p_ctx(ctx)), "inf")
  assert_eq(special_case(d("-Inf").log2_ctx(ctx)), "nan invalid")
  assert_eq(special_case(d("-Inf").log1p_ctx(ctx)), "nan invalid")
  assert_eq(special_case(d("-Inf").acosh_ctx(ctx)), "nan invalid")
}

///|
// oracle: A
// source: IEEE 754-2019 9.2.1 (read from the PDF text): for sin, tan, asin, atan, sinh, tanh, asinh, atanh, expm1 and log1p, f(+0) is +0 and f(-0) is -0 with no exception, and 9.2.2 gives the preferred exponent 0 (a zero operand of another cohort, 0E-3 and -0E+2, gives 0 and -0); cos(+-0) and cosh(+-0) are 1; written out, no value from the code under test
// shares: special_case (prints value and flags through to_string), Decimal::from_string (the local d: builds the operands), sin_ctx, tan_ctx, asin_ctx, atan_ctx, sinh_ctx, tanh_ctx, asinh_ctx, atanh_ctx, expm1_ctx, log1p_ctx, cos_ctx and cosh_ctx (the code under test)
test "the sign of a zero operand is kept by the odd functions (IEEE 754 9.2.1)" {
  let ctx = DecimalContext::decimal64()
  let d = fn(text : String) { Decimal::from_string(text).unwrap() }
  for text in ["0", "0E-3"] {
    assert_eq(special_case(d(text).sin_ctx(ctx)), "0")
    assert_eq(special_case(d(text).tan_ctx(ctx)), "0")
    assert_eq(special_case(d(text).asin_ctx(ctx)), "0")
    assert_eq(special_case(d(text).atan_ctx(ctx)), "0")
    assert_eq(special_case(d(text).sinh_ctx(ctx)), "0")
    assert_eq(special_case(d(text).tanh_ctx(ctx)), "0")
    assert_eq(special_case(d(text).asinh_ctx(ctx)), "0")
    assert_eq(special_case(d(text).atanh_ctx(ctx)), "0")
    assert_eq(special_case(d(text).expm1_ctx(ctx)), "0")
    assert_eq(special_case(d(text).log1p_ctx(ctx)), "0")
    assert_eq(special_case(d(text).cos_ctx(ctx)), "1")
    assert_eq(special_case(d(text).cosh_ctx(ctx)), "1")
  }
  for text in ["-0", "-0E+2"] {
    assert_eq(special_case(d(text).sin_ctx(ctx)), "-0")
    assert_eq(special_case(d(text).tan_ctx(ctx)), "-0")
    assert_eq(special_case(d(text).asin_ctx(ctx)), "-0")
    assert_eq(special_case(d(text).atan_ctx(ctx)), "-0")
    assert_eq(special_case(d(text).sinh_ctx(ctx)), "-0")
    assert_eq(special_case(d(text).tanh_ctx(ctx)), "-0")
    assert_eq(special_case(d(text).asinh_ctx(ctx)), "-0")
    assert_eq(special_case(d(text).atanh_ctx(ctx)), "-0")
    assert_eq(special_case(d(text).expm1_ctx(ctx)), "-0")
    assert_eq(special_case(d(text).log1p_ctx(ctx)), "-0")
    assert_eq(special_case(d(text).cos_ctx(ctx)), "1")
    assert_eq(special_case(d(text).cosh_ctx(ctx)), "1")
  }
}
