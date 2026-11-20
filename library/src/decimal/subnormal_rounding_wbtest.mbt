///|
/// A normal result whose exact exponent is below Etiny must be rounded once,
/// to the context precision. Rounding it to the subnormal grid first and then
/// to `precision` digits rounds twice. 3.000001E-45 * 1.500001E-45 is exactly
/// 4.5000045000015E-90: the first rounding produced the tie 4.5000045E-90 and
/// the second rounded it to even.
test "decimal rounds normal results below Etiny once" {
  let c32 = DecimalContext::decimal32()
  let d = fn(text : String) { Decimal::from_string(text).unwrap() }
  inspect(
    d("3.000001E-45").mul_ctx(d("1.500001E-45"), c32).0,
    content="4.500005E-90",
  )
  inspect(d("1.00000050000001E-89").apply_ctx(c32).0, content="1.000001E-89")
  inspect(
    d("3.000001E-45").fma_ctx(d("1.500001E-45"), d("0E-101"), c32).0,
    content="4.500005E-90",
  )
  // exp(-215.35) = 2.98320653786...E-94
  inspect(d("-215.35").exp_ctx(c32).0, content="2.983207E-94")
}

///|
/// 1 / 1.9999999999998E+101 = 5.0000000000005E-102. Rounding the guarded
/// quotient to seven digits gave the tie 5.000000E-102, which the subnormal
/// rounding then sent to 0E-101.
test "decimal division rounds subnormal quotients once" {
  let c32 = DecimalContext::decimal32()
  let d = fn(text : String) { Decimal::from_string(text).unwrap() }
  let (value, flags) = d("1").div_ctx(d("1.9999999999998E+101"), c32)
  inspect(value, content="1E-101")
  assert_true(flags.inexact && flags.underflow && flags.subnormal)
}

///|
/// An addend far below the other operand's last digit was folded into a
/// rounding decision that only looked at the larger operand. That is wrong
/// when the larger operand has digits below the rounding position or sits on
/// a midpoint, and for ZeroFiveUp whenever the addend reduces the magnitude.
test "decimal addition rounds sums with a far smaller addend correctly" {
  let d = fn(text : String) { Decimal::from_string(text).unwrap() }
  let ctx = fn(mode : DecimalRoundingMode) {
    DecimalContext::new(precision=7, decimal_rounding=mode)
  }
  // 1598617.000000000001 - 0.000000000002 = 1598616.999999999999
  let high = d("1598617000000000001E-12")
  let low = d("-2E-12")
  inspect(high.add_ctx(low, ctx(Down)).0, content="1598616")
  inspect(high.add_ctx(low, ctx(Floor)).0, content="1598616")
  inspect(high.add_ctx(low, ctx(Ceiling)).0, content="1598617")
  inspect(high.add_ctx(low, ctx(Up)).0, content="1598617")
  inspect(high.add_ctx(low, ctx(ZeroFiveUp)).0, content="1598616")
  // 1598618 - 9.9E-11 truncates to 1598617, whose last digit is not 0 or 5.
  inspect(
    d("1598618").add_ctx(d("-99E-12"), ctx(ZeroFiveUp)).0,
    content="1598617",
  )
  // 100000.05 sits on a midpoint; the tiny addend decides the tie.
  inspect(
    d("10000005E-2").add_ctx(d("-91656910E-18"), ctx(HalfUp)).0,
    content="100000.0",
  )
  inspect(
    d("6.0000005E-73").add_ctx(d("1E-101"), ctx(HalfEven)).0,
    content="6.000001E-73",
  )
}

///|
/// An exact quotient by a power of ten whose exponent is below Etiny but whose
/// magnitude is normal was rounded to Etiny only, which left six digits at
/// precision five: 4826437 / 1E+24 = 4.826437E-18 gave 4.82644E-18.
test "decimal exact division by a power of ten below Etiny rounds to precision" {
  let d = fn(text : String) { Decimal::from_string(text).unwrap() }
  for
    row in [
      (DecimalRoundingMode::Up, "4.8265E-18"),
      (DecimalRoundingMode::HalfEven, "4.8264E-18"),
      (DecimalRoundingMode::Down, "4.8264E-18"),
    ] {
    let ctx = DecimalContext::new(
      precision=5,
      decimal_rounding=row.0,
      e_min=-19,
      e_max=20,
    )
    let (value, flags) = d("4826437").div_ctx(d("1E+24"), ctx)
    assert_eq(value.to_string(), row.1)
    assert_true(flags.inexact && flags.rounded && !flags.subnormal)
    assert_eq(d("482643751").div_ctx(d("1E+26"), ctx).0.to_string(), row.1)
  }
  // A quotient that is subnormal is still rounded to Etiny.
  let ctx = DecimalContext::new(precision=5, e_min=-19, e_max=20)
  let (value, flags) = d("4826437").div_ctx(d("1E+29"), ctx)
  inspect(value, content="5E-23")
  assert_true(flags.subnormal && flags.underflow && flags.inexact)
}
