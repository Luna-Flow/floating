///|
// oracle: A
// source: GDA 1.70 (section "Normal numbers, subnormal numbers and Underflow", the definition of Etiny: Emin - (precision - 1), with Emin = 1 - Emax as in IEEE 754-2019 3.3) and the clamp bound Emax - (digits - 1), as plain Int64 arithmetic written in the test from the definition, not from `DecimalExponentBounds`
// shares: DecimalContext::try_new (builds the context; its e_max and precision are what the arithmetic below reads back through the public accessors only)
test "etiny and etop equal the exponent bounds they replace" {
  for precision in [1, 2, 7, 16, 34, 999_999_999] {
    for e_max in [1, 96, 6144, 999_999_999] {
      match DecimalContext::try_new(precision~, e_max~) {
        Ok(ctx) => {
          let e_min = 1L - e_max.to_int64()
          assert_eq(etiny(ctx).to_int64(), e_min - (precision.to_int64() - 1L))
          for digits in [precision, 1, 5, 40] {
            assert_eq(
              etop(ctx, digits).to_int64(),
              e_max.to_int64() - (digits.to_int64() - 1L),
            )
          }
        }
        Err(_) => ()
      }
    }
  }
  // literal values at the three decimal formats (GDA/IEEE: Emax 96, 384, 6144)
  assert_eq(etiny(DecimalContext::decimal32()), -101)
  assert_eq(etiny(DecimalContext::decimal64()), -398)
  assert_eq(etiny(DecimalContext::decimal128()), -6176)
  assert_eq(etop(DecimalContext::decimal32(), 7), 90)
  assert_eq(etop(DecimalContext::decimal64(), 16), 369)
  assert_eq(etop(DecimalContext::decimal128(), 34), 6111)
}
