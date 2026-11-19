///|
test "cached decimal contexts equal a fresh build for every parameter set" {
  let modes : Array[GdaRoundingMode] = [
    HalfEven,
    HalfUp,
    HalfDown,
    Down,
    Ceiling,
    Floor,
    Up,
    ZeroFiveUp,
  ]
  for precision in [1, 7, 16, 34] {
    for mode in modes {
      for clamp in [false, true] {
        for extended in [false, true] {
          let ctx = GdaContext::new(
            precision~,
            rounding=mode,
            e_min=-398,
            e_max=384,
            clamp~,
            extended~,
          ).unwrap()
          let fresh = DecimalContext::new(
            precision~,
            rounding=arithmetic_rounding(mode),
            decimal_rounding=decimal_rounding(mode),
            e_min=-398,
            e_max=384,
            clamp~,
            extended~,
            tininess=DecimalTininessDetection::BeforeRounding,
          ).unwrap()
          assert_true(ctx.decimal_context() == fresh)
          assert_true(
            ctx.mathematical_decimal_context() ==
            {
              ..fresh,
              rounding: @lf_arith.RoundingMode::ToNearestEven,
              decimal_rounding: DecimalRoundingMode::HalfEven,
            },
          )
          // changing the traps or the status keeps the cached contexts valid
          let trapped = ctx.trap(Overflow)
          assert_true(trapped.decimal_context() == fresh)
          assert_true(ctx.clear_status().decimal_context() == fresh)
        }
      }
    }
  }
}
