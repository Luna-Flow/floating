///|
fn gda_rounding_show(outcome : GdaOutcome[Decimal]) -> String {
  let raised = outcome.raised()
  let names = []
  for
    signal in [
      (GdaSignal::Clamped, "clamped"),
      (GdaSignal::Inexact, "inexact"),
      (GdaSignal::Overflow, "overflow"),
      (GdaSignal::Rounded, "rounded"),
      (GdaSignal::Subnormal, "subnormal"),
      (GdaSignal::Underflow, "underflow"),
    ] {
    if raised.contains(signal.0) {
      names.push(signal.1)
    }
  }
  outcome.value().to_string() + " [" + names.join(",") + "]"
}

///|
fn gda_rounding_dec(text : String) -> Decimal {
  Decimal::from_string(text).unwrap()
}

///|
/// An addend far below the other operand's last digit was folded into a
/// rounding decision that looked only at the larger operand. That is wrong
/// when the larger operand has digits below the rounding position or sits on a
/// midpoint, and for ZeroFiveUp whenever the addend lowers the magnitude.
/// Expected values agree with Python's decimal module.
test "gda add rounds sums with a far smaller addend once" {
  let ctx = fn(mode : GdaRoundingMode) {
    GdaContext::new(precision=7, rounding=mode).unwrap()
  }
  let d = gda_rounding_dec
  // 1598618 - 9.9E-11 truncates to 1598617, whose last digit is not 0 or 5.
  inspect(
    gda_rounding_show(
      subtract(d("1598618"), d("9.9E-11"), ctx(GdaRoundingMode::ZeroFiveUp)),
    ),
    content="1598617 [inexact,rounded]",
  )
  // 1598618.5 is a midpoint; the tiny addend breaks the tie upward.
  inspect(
    gda_rounding_show(
      add(d("1598618.5"), d("1E-20"), ctx(GdaRoundingMode::HalfEven)),
    ),
    content="1598619 [inexact,rounded]",
  )
  inspect(
    add(d("10000005E-2"), d("-91656910E-18"), ctx(GdaRoundingMode::HalfUp)).value(),
    content="100000.0",
  )
  inspect(
    add(d("6.0000005E-73"), d("1E-101"), ctx(GdaRoundingMode::HalfEven)).value(),
    content="6.000001E-73",
  )
  // 1598617.000000000001 - 0.000000000002 = 1598616.999999999999
  let high = d("1598617000000000001E-12")
  let low = d("-2E-12")
  for
    row in [
      (GdaRoundingMode::Down, "1598616"),
      (GdaRoundingMode::Floor, "1598616"),
      (GdaRoundingMode::Ceiling, "1598617"),
      (GdaRoundingMode::Up, "1598617"),
      (GdaRoundingMode::ZeroFiveUp, "1598616"),
    ] {
    assert_eq(add(high, low, ctx(row.0)).value().to_string(), row.1)
  }
}

///|
/// A normal result whose exact exponent is below Etiny must be rounded once,
/// to the context precision. 3.000001E-45 * 1.500001E-45 is exactly
/// 4.5000045000015E-90; rounding it to the subnormal grid first produced the
/// tie 4.5000045E-90, which the second rounding sent to even.
test "gda rounds normal results below Etiny once" {
  let c32 = GdaContext::decimal32()
  let d = gda_rounding_dec
  inspect(
    gda_rounding_show(multiply(d("3.000001E-45"), d("1.500001E-45"), c32)),
    content="4.500005E-90 [inexact,rounded]",
  )
  inspect(
    fma(d("3.000001E-45"), d("1.500001E-45"), d("0E-101"), c32).value(),
    content="4.500005E-90",
  )
  inspect(plus(d("1.00000050000001E-89"), c32).value(), content="1.000001E-89")
  // exp(-215.35) = 2.98320653786...E-94
  inspect(exp(d("-215.35"), c32).value(), content="2.983207E-94")
}

///|
/// 1 / 1.9999999999998E+101 = 5.0000000000005E-102. Rounding the guarded
/// quotient to seven digits gave the tie 5.000000E-102, which the subnormal
/// rounding then sent to 0E-101.
test "gda divide rounds subnormal quotients once" {
  inspect(
    gda_rounding_show(
      divide(
        gda_rounding_dec("1"),
        gda_rounding_dec("1.9999999999998E+101"),
        GdaContext::decimal32(),
      ),
    ),
    content="1E-101 [inexact,rounded,subnormal,underflow]",
  )
  // Exact quotients whose exponent is below Etiny but whose magnitude is
  // normal were rounded to Etiny only, leaving six digits at precision five:
  // 77223 / 16E+21 = 4.8264375E-18 gave 4.82644E-18 under Up.
  let d = gda_rounding_dec
  for
    row in [
      (GdaRoundingMode::Up, "4.8265E-18"),
      (GdaRoundingMode::HalfEven, "4.8264E-18"),
      (GdaRoundingMode::Down, "4.8264E-18"),
    ] {
    let ctx = GdaContext::new(precision=5, rounding=row.0, e_min=-19, e_max=20).unwrap()
    assert_eq(divide(d("77223"), d("16E+21"), ctx).value().to_string(), row.1)
    assert_eq(divide(d("4826437"), d("1E+24"), ctx).value().to_string(), row.1)
    assert_eq(
      divide(d("482643751"), d("1E+26"), ctx).value().to_string(),
      row.1,
    )
  }
}

///|
/// scaleb rounds, clamps and overflows like every other context operation:
/// a zero exponent is clamped into range, a coefficient longer than the
/// precision is rounded once, and overflow follows the rounding direction
/// (IEEE 754-2019 7.4).
test "gda scaleb rounds, clamps and overflows like other operations" {
  let c32 = GdaContext::decimal32()
  let c64 = GdaContext::decimal64()
  let d = gda_rounding_dec
  let n = fn(text : String) { Decimal::from_string(text).unwrap() }
  inspect(
    gda_rounding_show(scaleb(d("0E+300"), n("400"), c64)),
    content="0E+369 [clamped]",
  )
  inspect(
    gda_rounding_show(scaleb(d("-0E-390"), n("-700"), c64)),
    content="-0E-398 [clamped]",
  )
  inspect(
    gda_rounding_show(scaleb(d("12345678901234567890"), n("0"), c64)),
    content="1.234567890123457E+19 [inexact,rounded]",
  )
  inspect(
    gda_rounding_show(scaleb(d("12345678901234567890"), n("-400"), c64)),
    content="1.234567890123457E-381 [inexact,rounded]",
  )
  inspect(
    gda_rounding_show(scaleb(d("123"), n("-400"), c64)),
    content="1E-398 [inexact,rounded,subnormal,underflow]",
  )
  inspect(
    gda_rounding_show(
      scaleb(
        d("9E+96"),
        n("1"),
        GdaContext::new(
          precision=7,
          rounding=GdaRoundingMode::Down,
          e_min=-95,
          e_max=96,
          clamp=true,
        ).unwrap(),
      ),
    ),
    content="9.999999E+96 [inexact,overflow,rounded]",
  )
  inspect(
    gda_rounding_show(
      scaleb(
        d("-9.99"),
        n("97"),
        GdaContext::new(
          precision=7,
          rounding=GdaRoundingMode::Ceiling,
          e_min=-95,
          e_max=96,
          clamp=true,
        ).unwrap(),
      ),
    ),
    content="-9.999999E+96 [inexact,overflow,rounded]",
  )
  inspect(
    gda_rounding_show(scaleb(d("9E+96"), n("1"), c32)),
    content="inf [inexact,overflow,rounded]",
  )
}
