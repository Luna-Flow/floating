///|
fn tininess_after_rounding_show(text : String, ctx : DecimalContext) -> String {
  let (value, flags) = Decimal::from_string(text).unwrap().plus_ctx(ctx)
  let names = []
  if flags.underflow {
    names.push("underflow")
  }
  if flags.subnormal {
    names.push("subnormal")
  }
  if flags.inexact {
    names.push("inexact")
  }
  value.to_string() + " [" + names.join(",") + "]"
}

///|
test "after-rounding tininess rounds to the precision with unbounded exponent" {
  // IEEE 754 clause 7.5: tiny after rounding when the result rounded to p
  // digits with an unbounded exponent range is below b^emin in magnitude.
  let ctx = DecimalContext::new(
    precision=3,
    e_min=0,
    e_max=10,
    tininess=DecimalTininessDetection::AfterRounding,
  ).unwrap()
  // 0.9951 rounds to 0.995 < 1 at three digits: tiny, although rounding on
  // the subnormal grid gives the normal 1.00.
  inspect(
    tininess_after_rounding_show("0.9951", ctx),
    content="1.00 [underflow,subnormal,inexact]",
  )
  inspect(
    tininess_after_rounding_show("0.996", ctx),
    content="1.00 [underflow,subnormal,inexact]",
  )
  // 0.99951 rounds to 1.00 at three digits: not tiny.
  inspect(
    tininess_after_rounding_show("0.99951", ctx),
    content="1.00 [inexact]",
  )
  inspect(
    tininess_after_rounding_show("0.9941", ctx),
    content="0.99 [underflow,subnormal,inexact]",
  )
  // The rounding mode decides: rounded up to three digits, 0.9991 is 1.00.
  let up = DecimalContext::new(
    precision=3,
    e_min=0,
    e_max=10,
    decimal_rounding=DecimalRoundingMode::Up,
    tininess=DecimalTininessDetection::AfterRounding,
  ).unwrap()
  inspect(tininess_after_rounding_show("0.9991", up), content="1.00 [inexact]")
}
