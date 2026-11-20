///|
test "outward endpoints enclose the exact expansion" {
  let ctx = DecimalContext::new(precision=20, e_min=-999999, e_max=999999)
  let texts = [
    "1E-30", "-1E-30", "123.456E-400", "-7.25E-3000", "9.99E+300", "-3.5E+250", "0.1",
    "-0.1", "1E-5000", "2E+5000",
  ]
  for text in texts {
    let x = Decimal::from_string_ctx(text, ctx).0
    let lower = x.to_bin_float(precision=200, mode=RoundingMode::TowardNegative)
    let upper = x.to_bin_float(precision=200, mode=RoundingMode::TowardPositive)
    for digits in [8, 32, 60] {
      let lo = decimal_outward_dyadic_endpoint(lower, ctx, digits, false).unwrap()
      let hi = decimal_outward_dyadic_endpoint(upper, ctx, digits, true).unwrap()
      let exact_lo = decimal_exact_dyadic_endpoint(lower, ctx).unwrap()
      let exact_hi = decimal_exact_dyadic_endpoint(upper, ctx).unwrap()
      assert_true(lo.total_order_compare(exact_lo) <= 0)
      assert_true(hi.total_order_compare(exact_hi) >= 0)
      assert_true(digits10(lo.coefficient.to_bigint()) <= digits + 1)
      assert_true(digits10(hi.coefficient.to_bigint()) <= digits + 1)
    }
  }
}

///|
test "wide-range expm1 of a tiny argument is fast and unchanged" {
  let ctx = DecimalContext::new(precision=20, e_min=-999999, e_max=999999)
  for n in [1000, 100000, 300000] {
    let x = Decimal::from_string_ctx("1E-\{n}", ctx).0
    let (r, flags) = x.expm1_ctx(ctx)
    inspect(r.to_string(), content="1.0000000000000000000E-\{n}")
    assert_true(flags.inexact)
  }
}
