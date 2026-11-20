///|
/// sqrt(0.9999999) = 0.99999994999999875..., just below 10^e_min = 1. Before
/// rounding it is tiny in every mode. After rounding (IEEE 754-2019 7.5) it is
/// tiny only where rounding to seven digits with an unbounded exponent range
/// stays below 1: Up and Ceiling give 1.000000, which is not tiny, while
/// HalfEven gives 0.9999999 and is tiny although the delivered result, rounded
/// on the subnormal grid, is 1.000000.
test "sqrt detects tininess per the context's rule" {
  let check = (
    mode : DecimalRoundingMode,
    tininess : DecimalTininessDetection,
    expected : String,
    tiny : Bool,
  ) => {
    let ctx = DecimalContext::new(
      precision=7,
      decimal_rounding=mode,
      e_min=0,
      e_max=1,
      clamp=true,
      tininess~,
    ).unwrap()
    let (value, flags) = Decimal::from_string("0.9999999")
      .unwrap()
      .sqrt_ctx(ctx)
    assert_eq(value.to_string(), expected)
    assert_true(flags.inexact)
    assert_eq(flags.underflow, tiny)
    assert_eq(flags.subnormal, tiny)
  }
  check(Up, AfterRounding, "1.000000", false)
  check(Ceiling, AfterRounding, "1.000000", false)
  check(Up, BeforeRounding, "1.000000", true)
  check(Down, AfterRounding, "0.999999", true)
  check(HalfEven, AfterRounding, "1.000000", true)
  check(HalfEven, BeforeRounding, "1.000000", true)
}
