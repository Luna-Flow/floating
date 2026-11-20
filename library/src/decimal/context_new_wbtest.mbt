///|
test "DecimalContext::new builds the format of a precision and an e_max" {
  let ctx = DecimalContext::new(precision=7, e_max=60)
  match DecimalContext::try_new(precision=7, e_max=60) {
    Ok(other) => assert_true(other == ctx)
    Err(_) => fail("a valid context must be accepted")
  }
  assert_eq(ctx.precision(), 7)
  assert_eq(ctx.e_max(), 60)
  // IEEE 754-2019 3.3: emin = 1 - emax
  assert_eq(ctx.e_min(), -59)
}

///|
test "the exponent range of a precision alone is max(999999, 1000 p) (IEEE 754-2019 3.7)" {
  let default = DecimalContext::new()
  assert_eq(default.precision(), 34)
  assert_eq(default.e_max(), 999_999)
  assert_eq(default.e_min(), -999_998)
  assert_eq(DecimalContext::new(precision=7).e_max(), 999_999)
  assert_eq(DecimalContext::new(precision=1000).e_max(), 1_000_000)
  assert_eq(DecimalContext::new(precision=2000).e_max(), 2_000_000)
  // 1000 p above the limit needs an explicit e_max
  assert_true(DecimalContext::try_new(precision=1_000_000) is Err(_))
  assert_true(
    DecimalContext::try_new(precision=1_000_000, e_max=999_999_999) is Ok(_),
  )
}

///|
test "the interchange presets are the formats of IEEE 754-2019 3.6" {
  for
    entry in [
      (DecimalContext::decimal32(), 7, 96),
      (DecimalContext::decimal64(), 16, 384),
      (DecimalContext::decimal128(), 34, 6144),
    ] {
    let (ctx, precision, e_max) = entry
    assert_eq(ctx.precision(), precision)
    assert_eq(ctx.e_max(), e_max)
    assert_eq(ctx.e_min(), 1 - e_max)
    assert_true(ctx == DecimalContext::new(precision~, e_max~))
  }
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
test "panic DecimalContext::new aborts on e_max below one" {
  ignore(DecimalContext::new(e_max=0))
}

///|
test "panic DecimalContext::new aborts on e_max above the limit" {
  ignore(DecimalContext::new(e_max=1_000_000_000))
}

///|
test "DecimalContext::try_new names the invalid parameter" {
  match DecimalContext::try_new(precision=0) {
    Err(error) => assert_true(error.message.contains("precision"))
    Ok(_) => fail("precision 0 must be rejected")
  }
  match DecimalContext::try_new(e_max=0) {
    Err(error) => assert_true(error.message.contains("e_max"))
    Ok(_) => fail("e_max 0 must be rejected")
  }
}

///|
test "the setters keep the context valid" {
  let ctx = DecimalContext::decimal64().with_precision(9).with_e_max(50)
  assert_eq(ctx.precision(), 9)
  assert_eq(ctx.e_max(), 50)
  assert_eq(ctx.e_min(), -49)
  assert_true(ctx.with_rounding(RoundTiesToAway).rounding() == RoundTiesToAway)
}

///|
test "panic DecimalContext::with_e_max aborts on e_max 0" {
  ignore(DecimalContext::decimal64().with_e_max(0))
}
