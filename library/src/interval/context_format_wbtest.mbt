///|
test "IntervalContext is a binary format of IEEE 754-2019 3.3 with e_min = 1 - e_max" {
  let c = IntervalContext::new(precision=24, e_max=127)
  assert_eq(c.precision(), 24)
  assert_eq(c.e_max(), 127)
  assert_eq(c.e_min(), -126)
  let d = IntervalContext::new()
  assert_eq(d.precision(), 53)
  assert_eq(d.e_max(), @bin_float.binary_implementation_e_max)
  assert_eq(d.e_min(), @bin_float.BinaryContext::new().e_min())
  assert_eq(c.with_precision(11).precision(), 11)
  assert_eq(c.with_precision(11).e_max(), 127)
  assert_eq(c.with_e_max(15).e_min(), -14)
  assert_eq(c.with_e_max(15).precision(), 24)
}

///|
test "IntervalContext presets are the interchange formats" {
  for
    item in [
      (IntervalContext::binary16(), 11, 15),
      (IntervalContext::binary32(), 24, 127),
      (IntervalContext::binary64(), 53, 1023),
      (IntervalContext::binary128(), 113, 16383),
    ] {
    let (ctx, p, e_max) = item
    assert_eq(ctx.precision(), p)
    assert_eq(ctx.e_max(), e_max)
    assert_eq(ctx.e_min(), 1 - e_max)
  }
}

///|
test "IntervalContext::try_new rejects what no format has" {
  assert_true(IntervalContext::try_new(precision=0) is Err(_))
  assert_true(IntervalContext::try_new(precision=-3) is Err(_))
  assert_true(
    IntervalContext::try_new(precision=@bin_float.binary_precision_max + 1)
    is Err(_),
  )
  assert_true(
    IntervalContext::try_new(precision=@bin_float.binary_precision_max) is Ok(_),
  )
  assert_true(IntervalContext::try_new(e_max=0) is Err(_))
  assert_true(IntervalContext::try_new(e_max=-5) is Err(_))
  assert_true(IntervalContext::try_new(precision=1, e_max=1) is Ok(_))
}

///|
test "panic IntervalContext::new aborts on a precision beyond the limit" {
  ignore(IntervalContext::new(precision=@bin_float.binary_precision_max + 1))
}

///|
test "panic IntervalContext::with_precision aborts on an illegal precision" {
  ignore(IntervalContext::binary64().with_precision(0))
}

///|
/// A precision is checked where a value is made (issue 442): the `try_`
/// constructors return an error instead of replacing it by 1.
test "interval constructors report a precision outside 1..binary_precision_max" {
  let one = @bin_float.BinFloat::one(precision=53)
  for p in [0, -1, @bin_float.binary_precision_max + 1] {
    assert_true(Interval::try_from_bounds(one, one, precision=p) is Err(_))
    assert_true(Interval::try_exact(one, precision=p) is Err(_))
    assert_true(Interval::try_from_double(1.5, precision=p) is Err(_))
    assert_true(Interval::try_from_float(1.5, precision=p) is Err(_))
  }
  assert_true(Interval::try_from_bounds(one, one, precision=1) is Ok(_))
}

///|
test "panic Interval::from_bounds aborts on precision 0" {
  let one = @bin_float.BinFloat::one(precision=53)
  ignore(Interval::from_bounds(one, one, precision=0))
}

///|
test "panic Interval::empty aborts on a negative precision" {
  ignore(Interval::empty(precision=-4))
}

///|
test "panic Interval::with_precision aborts on precision 0" {
  ignore(Interval::from_int(1, precision=16).with_precision(0))
}

///|
test "try_new rejects a precision outside 1..=binary_precision_max" {
  let one = @bin_float.BinFloat::from_int(1)
  let zero = @bin_float.BinFloat::from_int(0)
  assert_true(
    Interval::try_from_midpoint_radius(one, zero, precision=0) is Err(_),
  )
  assert_true(
    Interval::try_from_midpoint_radius(
      one,
      zero,
      precision=@bin_float.binary_precision_max + 1,
    )
    is Err(_),
  )
  assert_true(
    Interval::try_from_midpoint_radius(one, zero, precision=1) is Ok(_),
  )
}
