///|
fn exp_tiny_show(text : String, ctx : DecimalContext) -> String {
  let (value, flags) = Decimal::from_string(text).unwrap().exp_ctx(ctx)
  let names = []
  if flags.inexact {
    names.push("inexact")
  }
  if flags.underflow {
    names.push("underflow")
  }
  value.to_string() + " [" + names.join(",") + "]"
}

///|
fn exp_tiny_ctx(precision : Int32, mode : DecimalRound) -> DecimalContext {
  DecimalContext::new(precision~, e_max=10005).with_round(mode)
}

///|
/// exp(-8E+4) is about 1E-34743, far below 10^e_min, whatever the bounded
/// rounding then gives. With `precision = 1` the smallest subnormal `10^etiny`
/// equals the smallest normal number `10^e_min`, and the coarse underflow path
/// of `exp` compared `etiny` with `e_min` and raised neither underflow nor
/// subnormal under the after-rounding option, which `decimal` no longer has
/// (#333, IEEE 754-2019 7.5). Tininess is detected before rounding.
// oracle: A
// source: arithmetic and IEEE 754-2019 7.5, 4.3: exp(-8E+4) is about 1E-34743, below the least subnormal 1E-10004 of precision 1 and e_max 10005 (Etiny = e_min = -10004), so toward positive, away from zero and 05up give 1E-10004 with inexact and underflow (tininess before rounding), as CPython decimal plus of the same exact value does
// shares: exp_tiny_show and exp_tiny_ctx (build the context and print value and flags through to_string), Decimal::from_string, exp_ctx (the code under test)
test "exp far below the range is tiny when etiny = e_min (#333)" {
  for
    mode in [DecimalRound::Up, DecimalRound::Ceiling, DecimalRound::ZeroFiveUp] {
    inspect(
      exp_tiny_show("-8E+4", exp_tiny_ctx(1, mode)),
      content=(
        #|1E-10004 [inexact,underflow]
      ),
    )
  }
}
