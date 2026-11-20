///|
test "etiny and etop equal the exponent bounds they replace" {
  for precision in [0, 1, 2, 7, 16, 34, 999_999_999] {
    for e_min in [0, -1, -101, -6176, -999_999_999] {
      for e_max in [0, 96, 6144, 999_999_999] {
        match
          DecimalContext::try_new(
            precision~,
            e_min~,
            e_max~,
            extended=precision == 0 || e_min != -101,
          ) {
          Ok(ctx) => {
            let default = if precision == 0 { 1 } else { precision }
            let bounds = @internal.DecimalExponentBounds::new(
              default, e_min, e_max,
            )
            assert_eq(etiny(ctx), bounds.etiny())
            assert_eq(etop(ctx, default), bounds.etop())
            for digits in [1, 5, 40] {
              let sized = @internal.DecimalExponentBounds::new(
                digits, e_min, e_max,
              )
              assert_eq(etop(ctx, digits), sized.etop())
            }
          }
          Err(_) => ()
        }
      }
    }
  }
}
