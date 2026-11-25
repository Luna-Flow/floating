///|
// oracle: A, S
// source: IEEE 754-2019 3.3: emin = 1 - emax, so (24, 127) has emin -126 and (15) has -14; the default context of the library has the maximum exponent 2^30 - 1 = 1073741823 (the design limit of the exponent range, written as a literal) and emin = 1 - emax = -1073741822
// shares: IntervalContext::new, with_precision, with_e_max and the accessors (the code under test is the same functions; the expected values are literals); the default e_max 2^30 - 1 and e_min -(2^30 - 2) are the library's own limit, not a value of a standard, so those two checks are S
test "IntervalContext is a binary format of IEEE 754-2019 3.3 with e_min = 1 - e_max" {
  let c = IntervalContext::new(precision=24, e_max=127)
  assert_eq(c.precision(), 24)
  assert_eq(c.e_max(), 127)
  assert_eq(c.e_min(), -126)
  let d = IntervalContext::new()
  assert_eq(d.precision(), 53)
  assert_eq(d.e_max(), 1073741823)
  assert_eq(d.e_min(), -1073741822)
  assert_eq(c.with_precision(11).precision(), 11)
  assert_eq(c.with_precision(11).e_max(), 127)
  assert_eq(c.with_e_max(15).e_min(), -14)
  assert_eq(c.with_e_max(15).precision(), 24)
}

///|
// oracle: A
// source: IEEE 754-2019 3.3 and Table 3.5: binary16 has 11 digits and emax 15, binary32 24 and 127, binary64 53 and 1023, binary128 113 and 16383, and emin = 1 - emax (written as the literals of the test)
// shares: IntervalContext::new, try_new, the presets and the accessors are the code under test; the expected values are literals; Binary::one, from_int and Interval constructors build the inputs
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
// oracle: A
// source: written out by hand: a format has a precision of at least 1 and at most the library limit binary_precision_max, and e_max of at least 1 (emin = 1 - emax must not exceed 0); so precision 0, -3 and binary_precision_max + 1, and e_max 0 and -5 are rejected, binary_precision_max and the pair (1, 1) are accepted
// shares: IntervalContext::new, try_new, the presets and the accessors are the code under test; the expected values are literals; Binary::one, from_int and Interval constructors build the inputs
test "IntervalContext::try_new rejects what no format has" {
  assert_true(IntervalContext::try_new(precision=0) is Err(_))
  assert_true(IntervalContext::try_new(precision=-3) is Err(_))
  assert_true(
    IntervalContext::try_new(precision=@binary.binary_precision_max + 1)
    is Err(_),
  )
  assert_true(
    IntervalContext::try_new(precision=@binary.binary_precision_max) is Ok(_),
  )
  assert_true(IntervalContext::try_new(e_max=0) is Err(_))
  assert_true(IntervalContext::try_new(e_max=-5) is Err(_))
  assert_true(IntervalContext::try_new(precision=1, e_max=1) is Ok(_))
}

///|
// oracle: A
// source: written out by hand: a precision beyond binary_precision_max is not a format, so the constructor that does not return a result aborts (the test is a panic test)
// shares: IntervalContext::new, try_new, the presets and the accessors are the code under test; the expected values are literals; Binary::one, from_int and Interval constructors build the inputs
test "panic IntervalContext::new aborts on a precision beyond the limit" {
  ignore(IntervalContext::new(precision=@binary.binary_precision_max + 1))
}

///|
// oracle: A
// source: written out by hand: precision 0 is not a format, so with_precision aborts (panic test)
// shares: IntervalContext::new, try_new, the presets and the accessors are the code under test; the expected values are literals; Binary::one, from_int and Interval constructors build the inputs
test "panic IntervalContext::with_precision aborts on an illegal precision" {
  ignore(IntervalContext::binary64().with_precision(0))
}

///|
// A precision is checked where a value is made (issue 442): the `try_`
// constructors return an error instead of replacing it by 1.
// oracle: A
// source: written out by hand (issue 442): try_from_bounds, try_exact, try_from_double and try_from_float return an error for the precisions 0, -1 and binary_precision_max + 1 and succeed at 1
// shares: IntervalContext::new, try_new, the presets and the accessors are the code under test; the expected values are literals; Binary::one, from_int and Interval constructors build the inputs
test "interval constructors report a precision outside 1..binary_precision_max" {
  let one = @binary.Binary::one(precision=53)
  for p in [0, -1, @binary.binary_precision_max + 1] {
    assert_true(Interval::try_from_bounds(one, one, precision=p) is Err(_))
    assert_true(Interval::try_exact(one, precision=p) is Err(_))
    assert_true(Interval::try_from_double(1.5, precision=p) is Err(_))
    assert_true(Interval::try_from_float(1.5, precision=p) is Err(_))
  }
  assert_true(Interval::try_from_bounds(one, one, precision=1) is Ok(_))
}

///|
// oracle: A
// source: written out by hand: precision 0 is outside 1..binary_precision_max, so from_bounds aborts (panic test)
// shares: IntervalContext::new, try_new, the presets and the accessors are the code under test; the expected values are literals; Binary::one, from_int and Interval constructors build the inputs
test "panic Interval::from_bounds aborts on precision 0" {
  let one = @binary.Binary::one(precision=53)
  ignore(Interval::from_bounds(one, one, precision=0))
}

///|
// oracle: A
// source: written out by hand: a negative precision is outside 1..binary_precision_max, so empty aborts (panic test)
// shares: IntervalContext::new, try_new, the presets and the accessors are the code under test; the expected values are literals; Binary::one, from_int and Interval constructors build the inputs
test "panic Interval::empty aborts on a negative precision" {
  ignore(Interval::empty(precision=-4))
}

///|
// oracle: A
// source: written out by hand: precision 0 is outside 1..binary_precision_max, so with_precision aborts (panic test)
// shares: IntervalContext::new, try_new, the presets and the accessors are the code under test; the expected values are literals; Binary::one, from_int and Interval constructors build the inputs
test "panic Interval::with_precision aborts on precision 0" {
  ignore(Interval::from_int(1, precision=16).with_precision(0))
}

///|
// oracle: A
// source: written out by hand: try_from_midpoint_radius of (1, 0) returns an error for the precisions 0 and binary_precision_max + 1 and succeeds at 1
// shares: IntervalContext::new, try_new, the presets and the accessors are the code under test; the expected values are literals; Binary::one, from_int and Interval constructors build the inputs
test "try_new rejects a precision outside 1..=binary_precision_max" {
  let one = @binary.Binary::from_int(1)
  let zero = @binary.Binary::from_int(0)
  assert_true(
    Interval::try_from_midpoint_radius(one, zero, precision=0) is Err(_),
  )
  assert_true(
    Interval::try_from_midpoint_radius(
      one,
      zero,
      precision=@binary.binary_precision_max + 1,
    )
    is Err(_),
  )
  assert_true(
    Interval::try_from_midpoint_radius(one, zero, precision=1) is Ok(_),
  )
}
