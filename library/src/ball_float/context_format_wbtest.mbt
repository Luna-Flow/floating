///|
test "BallContext is a binary format of IEEE 754-2019 3.3 with e_min = 1 - e_max" {
  let c = BallContext::new(precision=24, e_max=127)
  assert_eq(c.precision(), 24)
  assert_eq(c.e_max(), 127)
  assert_eq(c.e_min(), -126)
  let d = BallContext::new()
  assert_eq(d.precision(), 53)
  assert_eq(d.e_max(), @bin_float.binary_implementation_e_max)
  assert_eq(d.e_min(), @bin_float.BinaryContext::new().e_min())
  assert_eq(c.with_precision(11).precision(), 11)
  assert_eq(c.with_precision(11).e_max(), 127)
  assert_eq(c.with_e_max(15).e_min(), -14)
  assert_eq(c.with_e_max(15).precision(), 24)
}

///|
test "BallContext presets are the interchange formats" {
  for
    item in [
      (BallContext::binary16(), 11, 15),
      (BallContext::binary32(), 24, 127),
      (BallContext::binary64(), 53, 1023),
      (BallContext::binary128(), 113, 16383),
    ] {
    let (ctx, p, e_max) = item
    assert_eq(ctx.precision(), p)
    assert_eq(ctx.e_max(), e_max)
    assert_eq(ctx.e_min(), 1 - e_max)
  }
}

///|
test "BallContext::try_new rejects what no format has" {
  assert_true(BallContext::try_new(precision=0) is Err(_))
  assert_true(BallContext::try_new(precision=-3) is Err(_))
  assert_true(
    BallContext::try_new(precision=@bin_float.binary_precision_max + 1)
    is Err(_),
  )
  assert_true(
    BallContext::try_new(precision=@bin_float.binary_precision_max) is Ok(_),
  )
  assert_true(BallContext::try_new(e_max=0) is Err(_))
  assert_true(BallContext::try_new(e_max=-5) is Err(_))
  assert_true(BallContext::try_new(precision=1, e_max=1) is Ok(_))
}

///|
test "panic BallContext::new aborts on a precision beyond the limit" {
  ignore(BallContext::new(precision=@bin_float.binary_precision_max + 1))
}

///|
test "panic BallContext::with_precision aborts on an illegal precision" {
  ignore(BallContext::binary64().with_precision(0))
}

///|
/// A precision is checked where a value is made (issue 442): the `try_`
/// constructors return an error instead of replacing it by 1.
test "interval constructors report a precision outside 1..binary_precision_max" {
  let one = @bin_float.BinFloat::one(precision=53)
  for p in [0, -1, @bin_float.binary_precision_max + 1] {
    assert_true(BallFloat::try_from_bounds(one, one, precision=p) is Err(_))
    assert_true(BallFloat::try_exact(one, precision=p) is Err(_))
    assert_true(BallFloat::try_from_double(1.5, precision=p) is Err(_))
    assert_true(BallFloat::try_from_float(1.5, precision=p) is Err(_))
  }
  assert_true(BallFloat::try_from_bounds(one, one, precision=1) is Ok(_))
}

///|
test "panic BallFloat::from_bounds aborts on precision 0" {
  let one = @bin_float.BinFloat::one(precision=53)
  ignore(BallFloat::from_bounds(one, one, precision=0))
}

///|
test "panic BallFloat::empty aborts on a negative precision" {
  ignore(BallFloat::empty(precision=-4))
}

///|
test "panic BallFloat::with_precision aborts on precision 0" {
  ignore(BallFloat::from_int(1, precision=16).with_precision(0))
}

///|
test "try_new rejects a precision outside 1..=binary_precision_max" {
  let one = @bin_float.BinFloat::from_int(1)
  let zero = @bin_float.BinFloat::from_int(0)
  assert_true(BallFloat::try_new(one, zero, precision=0) is Err(_))
  assert_true(
    BallFloat::try_new(one, zero, precision=@bin_float.binary_precision_max + 1)
    is Err(_),
  )
  assert_true(BallFloat::try_new(one, zero, precision=1) is Ok(_))
}
