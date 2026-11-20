///|
/// IEEE 754-2019 §7.5: "For decimal formats, tininess is detected before
/// rounding". A context has no other option (#217). `0.99951` is below
/// `10^e_min = 1` before rounding (tiny, and inexact, so `underflow`) but
/// rounds to `1.00` at three digits.
test "decimal contexts detect tininess before rounding (#217)" {
  let ctx = DecimalContext::new(precision=3, e_max=1)
  for text in ["0.9951", "0.99951"] {
    let (value, flags) = Decimal::from_string(text).unwrap().plus_ctx(ctx)
    assert_eq(value.to_string(), "1.00")
    assert_true(flags.underflow && flags.inexact, msg=text)
  }
}
