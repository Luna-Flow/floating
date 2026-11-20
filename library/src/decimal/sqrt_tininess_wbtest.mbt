///|
/// sqrt(0.9999999) = 0.99999994999999875..., just below 10^e_min = 1. IEEE
/// 754-2019 7.5: for decimal formats tininess is detected before rounding, so
/// it is tiny in every mode, whatever the delivered result.
test "sqrt detects tininess before rounding" {
  let check = (mode : DecimalRound, expected : String, tiny : Bool) => {
    let ctx = DecimalContext::new(precision=7, e_max=1).with_round(mode)
    let (value, flags) = Decimal::from_string("0.9999999")
      .unwrap()
      .sqrt_ctx(ctx)
    assert_eq(value.to_string(), expected)
    assert_true(flags.inexact)
    assert_eq(flags.underflow, tiny)
  }
  check(Up, "1.000000", true)
  check(Ceiling, "1.000000", true)
  check(Down, "0.999999", true)
  check(HalfEven, "1.000000", true)
}
