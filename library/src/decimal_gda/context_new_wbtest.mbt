///|
test "DecimalContext::new accepts the valid range and agrees with try_new" {
  let ctx = DecimalContext::new(precision=7, e_min=-50, e_max=60)
  match DecimalContext::try_new(precision=7, e_min=-50, e_max=60) {
    Ok(other) => assert_true(other.precision() == ctx.precision())
    Err(_) => fail("a valid context must be accepted")
  }
  assert_eq(ctx.precision(), 7)
  assert_eq(ctx.e_min(), -50)
}

///|
test "panic DecimalContext::new aborts on precision 0" {
  ignore(DecimalContext::new(precision=0))
}

///|
test "panic DecimalContext::new aborts on precision above the limit" {
  ignore(DecimalContext::new(precision=1_000_000_000))
}

///|
test "panic DecimalContext::new aborts on e_min above zero" {
  ignore(DecimalContext::new(e_min=1))
}

///|
test "panic DecimalContext::new aborts on e_max below zero" {
  ignore(DecimalContext::new(e_max=-1))
}

///|
test "panic DecimalContext::new aborts when e_min exceeds e_max" {
  ignore(DecimalContext::new(e_min=0, e_max=-1))
}

///|
test "DecimalContext::try_new names the invalid parameter" {
  match DecimalContext::try_new(precision=0) {
    Err(error) => assert_true(error.message.contains("precision"))
    Ok(_) => fail("precision 0 must be rejected")
  }
}

///|
test "GdaContext::new accepts the valid range and agrees with try_new" {
  let ctx = GdaContext::new(precision=7, e_min=-60, e_max=60)
  match GdaContext::try_new(precision=7, e_min=-60, e_max=60) {
    Ok(other) => assert_true(other.precision() == ctx.precision())
    Err(_) => fail("a valid context must be accepted")
  }
  assert_eq(ctx.precision(), 7)
  assert_eq(ctx.e_min(), -60)
}

///|
test "panic GdaContext::new aborts on precision 0" {
  ignore(GdaContext::new(precision=0))
}

///|
test "panic GdaContext::new aborts on precision above the limit" {
  ignore(GdaContext::new(precision=1_000_000_000))
}

///|
test "panic GdaContext::new aborts on e_min above zero" {
  ignore(GdaContext::new(e_min=1))
}

///|
test "panic GdaContext::new aborts on e_max below zero" {
  ignore(GdaContext::new(e_max=-1))
}

///|
test "panic GdaContext::new aborts when e_min exceeds e_max" {
  ignore(GdaContext::new(e_min=0, e_max=-1))
}

///|
test "GdaContext::try_new names the invalid parameter" {
  match GdaContext::try_new(precision=0) {
    Err(error) => assert_true(error.message.contains("precision"))
    Ok(_) => fail("precision 0 must be rejected")
  }
}

///|
/// GDA 1.70, page 10: the magnitudes of Emin and Emax differ by at most one.
test "GdaContext accepts only the exponent ranges of GDA 1.70 page 10" {
  for emax in [0, 1, 2, 96, 384, 999, 6144, 999_999, 999_999_999] {
    for emin in [-emax, 1 - emax, -emax - 1] {
      if emin >= -999_999_999 && emin <= 0 {
        assert_true(GdaContext::try_new(e_min=emin, e_max=emax) is Ok(_))
      }
    }
    for emin in [-emax + 2, -emax - 2, -emax / 2 - 5] {
      if emin >= -999_999_999 && emin <= 0 && emin != -emax + 1 && emin != -emax {
        match GdaContext::try_new(e_min=emin, e_max=emax) {
          Err(error) =>
            assert_true(
              error.message.contains(
                "e_min must be -e_max, 1 - e_max or -e_max - 1",
              ),
            )
          Ok(_) =>
            fail("e_min \{emin} with e_max \{emax} is not a GDA 1.70 range")
        }
      }
    }
  }
  // the defaults and the interchange presets are inside the rule
  assert_true(GdaContext::try_new() is Ok(_))
  assert_true(GdaContext::try_new(e_min=-95, e_max=96) is Ok(_))
  assert_true(GdaContext::try_new(e_min=-50, e_max=60) is Err(_))
  assert_true(GdaContext::try_new(e_min=0, e_max=999_999_999) is Err(_))
}

///|
test "panic GdaContext::new aborts on an exponent range outside GDA 1.70 page 10" {
  ignore(GdaContext::new(e_min=-50, e_max=60))
}

///|
test "GdaContext setters rebuild a valid context and keep status, traps and the refinement limit" {
  let traps = GdaTrapSet::new().with_signal(GdaSignal::Overflow)
  let base = GdaContext::new(precision=9, traps~).with_refinement_limit(Some(7))
  let changed = base
    .with_precision(20)
    .with_rounding(GdaRoundingMode::Floor)
    .with_exponent_range(e_min=-98, e_max=99)
  assert_eq(changed.precision(), 20)
  assert_true(changed.rounding() == GdaRoundingMode::Floor)
  assert_eq(changed.e_min(), -98)
  assert_eq(changed.e_max(), 99)
  assert_true(changed.traps() == traps)
  assert_true(changed.refinement_limit() == Some(7))
  assert_eq(base.precision(), 9)
}

///|
test "panic GdaContext::with_exponent_range aborts outside the GDA 1.70 rule" {
  ignore(GdaContext::new().with_exponent_range(e_min=-5, e_max=50))
}

///|
test "the presets take a rounding mode and keep the extended default otherwise" {
  assert_true(GdaContext::decimal64().rounding() == GdaRoundingMode::HalfEven)
  let up = GdaContext::decimal64(rounding=GdaRoundingMode::Up)
  assert_true(up.rounding() == GdaRoundingMode::Up)
  assert_eq(up.precision(), 16)
  assert_eq(up.e_max(), 384)
  assert_true(up.clamp())
  assert_eq(GdaContext::decimal32(rounding=GdaRoundingMode::Floor).e_min(), -95)
  assert_eq(
    GdaContext::decimal128(rounding=GdaRoundingMode::Ceiling).precision(),
    34,
  )
  let basic = GdaContext::basic_default()
  assert_eq(basic.precision(), 9)
  assert_true(basic.rounding() == GdaRoundingMode::HalfUp)
  assert_false(basic.extended())
}
