///|
/// sqrt(0.9999999) = 0.99999994999999875..., just below 10^e_min = 1. IEEE
/// 754-2019 7.5: for decimal formats tininess is detected before rounding, so
/// it is tiny in every mode, whatever the delivered result.

///|
// oracle: A
// source: written out from IEEE Std 754-2019 7.5 (for decimal formats tininess is detected before rounding): sqrt(0.9999999) = 0.99999994999999875..., below 10^e_min = 1 for precision 7 and e_max 1, so it is tiny and inexact in every mode, and on the subnormal grid 10^-6 it rounds to 1.000000 upward, in nearest and toward positive infinity, and to 0.999999 downward; the nearest row agrees with Python decimal (whose sqrt always rounds half even, so the directed rows are not re-derived there)
// shares: Decimal::from_string reads the operand; sqrt_ctx is the code under test; DecimalContext::new and with_round build the contexts; to_string and the flags read the result
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
