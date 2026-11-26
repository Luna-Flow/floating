///|
/// IEEE 754-2019 §7.5: "For decimal formats, tininess is detected before
/// rounding". A context has no other option (#217). `0.99951` is below
/// `10^e_min = 1` before rounding (tiny, and inexact, so `underflow`) but
/// rounds to `1.00` at three digits.

///|
// oracle: A
// source: written out from IEEE Std 754-2019 7.5 (for decimal formats tininess is detected before rounding): 0.9951 and 0.99951 are below 10^e_min = 1 before rounding for precision 3 and e_max 1, and round to 1.00 on the grid 10^-2, so they are tiny and inexact: underflow
// shares: Decimal::from_string reads the operands; plus_ctx is the code under test; DecimalContext::new builds the context; to_string and the flag fields read the result
test "decimal contexts detect tininess before rounding (#217)" {
  let ctx = DecimalContext::new(precision=3, e_max=1)
  for text in ["0.9951", "0.99951"] {
    let (value, flags) = Decimal::from_string(text).unwrap().plus_ctx(ctx)
    assert_eq(value.to_string(), "1.00")
    assert_true(flags.underflow && flags.inexact, msg=text)
  }
}
