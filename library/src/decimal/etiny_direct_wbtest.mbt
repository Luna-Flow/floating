///|
test "etiny and etop equal the exponent bounds they replace" {
  for precision in [1, 2, 7, 16, 34, 999_999_999] {
    for e_max in [1, 96, 6144, 999_999_999] {
      match DecimalContext::try_new(precision~, e_max~) {
        Ok(ctx) => {
          let bounds = @internal.DecimalExponentBounds::new(
            precision,
            1 - e_max,
            e_max,
          )
          assert_eq(etiny(ctx), bounds.etiny())
          assert_eq(etop(ctx, precision), bounds.etop())
          for digits in [1, 5, 40] {
            let sized = @internal.DecimalExponentBounds::new(
              digits,
              1 - e_max,
              e_max,
            )
            assert_eq(etop(ctx, digits), sized.etop())
          }
        }
        Err(_) => ()
      }
    }
  }
}
