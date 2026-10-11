///|
/// The flags of an inexact quotient come from rounding the quotient itself,
/// not from looking at the delivered value: a tiny quotient that rounds up to
/// 10^e_min is no longer subnormal, but it was tiny and underflows (IEEE
/// 754-2019 7.5), and a quotient that rounds to zero below Etiny is clamped.
/// Expected values from Python `decimal` where it applies.
test "division reports the underflow flags of the quotient" {
  let d = fn(s : String) { Decimal::from_string(s).unwrap() }
  // Tiny under both rules: 9.99999899...E-96 rounds to 9.999999E-96 at p = 7.
  let (v1, f1) = d("9.999998E-96").div_ctx(
    d("0.9999999"),
    DecimalContext::decimal32(),
  )
  assert_eq(v1.to_string(), "1.000000E-95")
  assert_true(f1.underflow && f1.subnormal && f1.inexact && f1.rounded)
  // Precision 1: the quotient 2.2E-42 rounds down to zero at Etiny = -23.
  let p1 = DecimalContext::new(
    precision=1,
    decimal_rounding=Down,
    e_min=-23,
    e_max=23,
    tininess=BeforeRounding,
  ).unwrap()
  let (v2, f2) = d("-2E-23").div_ctx(d("-9E+18"), p1)
  assert_eq(v2.to_string(), "0E-23")
  assert_true(f2.underflow && f2.subnormal && f2.clamped && f2.inexact)
  // A subnormal quotient that rounds to zero is clamped, as in mul_ctx.
  let (v3, f3) = d("1E-101").div_ctx(d("3"), DecimalContext::decimal32())
  assert_eq(v3.to_string(), "0E-101")
  assert_true(f3.clamped && f3.underflow && f3.subnormal && f3.inexact)
  let p3 = DecimalContext::new(
    precision=3,
    e_min=-5,
    e_max=5,
    clamp=true,
    tininess=BeforeRounding,
  ).unwrap()
  let (v4, f4) = d("4.39E-7").div_ctx(d("440"), p3)
  assert_eq(v4.to_string(), "0E-7")
  assert_true(f4.clamped && f4.underflow)
}
