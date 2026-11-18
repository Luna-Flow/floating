///|
fn exp_tiny_show(text : String, ctx : DecimalContext) -> String {
  let (value, flags) = Decimal::from_string(text).unwrap().exp_ctx(ctx)
  let names = []
  if flags.inexact {
    names.push("inexact")
  }
  if flags.rounded {
    names.push("rounded")
  }
  if flags.underflow {
    names.push("underflow")
  }
  if flags.subnormal {
    names.push("subnormal")
  }
  value.to_string() + " [" + names.join(",") + "]"
}

///|
fn exp_tiny_ctx(
  precision : Int32,
  mode : DecimalRoundingMode,
  tininess : DecimalTininessDetection,
) -> DecimalContext {
  DecimalContext::new(
    precision~,
    decimal_rounding=mode,
    e_min=-10004,
    e_max=10001,
    tininess~,
  ).unwrap()
}

///|
/// `AfterRounding` is a non-standard option of this library (IEEE 754-2019 §7.5
/// requires tininess before rounding for decimal formats; #217). Its own rule,
/// the one §7.5(a) states for binary formats, is that a result is tiny when it,
/// computed with an unbounded exponent range and precision p, lies below
/// 10^e_min. exp(-8E+4) is about 1E-34743, far below 10^e_min, whatever the
/// bounded rounding then gives. With `precision = 1` the smallest subnormal
/// `10^etiny` equals the smallest normal number `10^e_min`, and the coarse
/// underflow path of `exp` compared `etiny` with `e_min` and raised neither
/// underflow nor subnormal under that option (#333). Tininess before rounding,
/// the default, was already right.
test "exp far below the range is tiny after rounding when etiny = e_min (#333)" {
  for
    mode in [
      DecimalRoundingMode::Up,
      DecimalRoundingMode::Ceiling,
      DecimalRoundingMode::ZeroFiveUp,
    ] {
    inspect(
      exp_tiny_show(
        "-8E+4",
        exp_tiny_ctx(1, mode, DecimalTininessDetection::AfterRounding),
      ),
      content="1E-10004 [inexact,rounded,underflow,subnormal]",
    )
    inspect(
      exp_tiny_show(
        "-8E+4",
        exp_tiny_ctx(1, mode, DecimalTininessDetection::BeforeRounding),
      ),
      content="1E-10004 [inexact,rounded,underflow,subnormal]",
    )
  }
}

///|
test "exp coarse underflow flags do not depend on the precision (#333)" {
  for precision in [1, 2, 3, 7] {
    for
      tininess in [
        DecimalTininessDetection::AfterRounding,
        DecimalTininessDetection::BeforeRounding,
      ] {
      let (value, flags) = Decimal::from_string("-8E+4")
        .unwrap()
        .exp_ctx(exp_tiny_ctx(precision, DecimalRoundingMode::Up, tininess))
      assert_true(value.is_finite())
      assert_true(
        flags.underflow && flags.subnormal && flags.inexact && flags.rounded,
        msg="p=\{precision}",
      )
    }
  }
  // Rounding to nearest underflows to zero with the same flags.
  inspect(
    exp_tiny_show(
      "-8E+4",
      exp_tiny_ctx(
        1,
        DecimalRoundingMode::HalfEven,
        DecimalTininessDetection::AfterRounding,
      ),
    ),
    content="0E-10004 [inexact,rounded,underflow,subnormal]",
  )
}
