///|
fn log_zero_show(result : (Decimal, DecimalFlags)) -> String {
  let (value, flags) = result
  let names = []
  if flags.division_by_zero {
    names.push("division_by_zero")
  }
  if flags.invalid_operation {
    names.push("invalid_operation")
  }
  if flags.inexact {
    names.push("inexact")
  }
  value.to_string() + " [" + names.join(",") + "]"
}

///|
// oracle: A
// source: IEEE 754-2019 9.2.1 (read from the PDF text): log, log2 and log10 of +-0 are -inf and signal divideByZero, and so is log1p(-1); the operands 0, -0, 0E+5 and -0.000 are zeros of different cohorts; written out
// shares: Decimal::from_string (the local d: builds the operands), log_zero_show (prints value and flags through to_string), ln_ctx, log10_ctx, log2_ctx, log1p_ctx and the try_ forms (the code under test)
test "logarithms of zero signal division by zero (IEEE 754 9.2.1)" {
  let d = fn(s : String) { Decimal::from_string(s).unwrap() }
  let c64 = DecimalContext::decimal64()
  for text in ["0", "-0", "0E+5", "-0.000"] {
    inspect(
      log_zero_show(d(text).ln_ctx(c64)),
      content="-inf [division_by_zero]",
    )
    inspect(
      log_zero_show(d(text).log10_ctx(c64)),
      content="-inf [division_by_zero]",
    )
    inspect(
      log_zero_show(d(text).try_ln_ctx(c64).unwrap()),
      content="-inf [division_by_zero]",
    )
    inspect(
      log_zero_show(d(text).try_log10_ctx(c64).unwrap()),
      content="-inf [division_by_zero]",
    )
    // The other logarithms already agreed.
    inspect(
      log_zero_show(d(text).log2_ctx(c64)),
      content="-inf [division_by_zero]",
    )
  }
  inspect(
    log_zero_show(d("-1").log1p_ctx(c64)),
    content="-inf [division_by_zero]",
  )
}
