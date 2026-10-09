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
  // A subset context keeps the X3.274 rule: a zero operand is invalid.
  let subset = DecimalContext::new(precision=9, extended=false)
  inspect(
    log_zero_show(d("0").ln_ctx(subset)),
    content="nan [invalid_operation]",
  )
}
