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
