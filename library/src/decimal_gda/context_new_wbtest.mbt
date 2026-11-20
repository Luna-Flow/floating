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
  let ctx = GdaContext::new(precision=7, e_min=-50, e_max=60)
  match GdaContext::try_new(precision=7, e_min=-50, e_max=60) {
    Ok(other) => assert_true(other.precision() == ctx.precision())
    Err(_) => fail("a valid context must be accepted")
  }
  assert_eq(ctx.precision(), 7)
  assert_eq(ctx.e_min(), -50)
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
