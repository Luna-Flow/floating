///|
test "certified atan2 handles axes and branch cut" {
  let zero = Interval::from_double(0.0, precision=53)
  let one = Interval::from_double(1.0, precision=53)
  let minus_one = Interval::from_double(-1.0, precision=53)
  assert_true(
    one
    .atan2(zero)
    .is_member(@bin_float.BinFloat::from_double(1.5707963267948966)),
  )
  assert_true(zero.atan2(one).is_member(@bin_float.BinFloat::zero()))
  let crossing = Interval::from_bounds(
    @bin_float.BinFloat::from_double(-1.0),
    @bin_float.BinFloat::from_double(1.0),
    precision=53,
  ).atan2(minus_one)
  assert_true(crossing.is_member(@bin_float.BinFloat::from_double(-3.0)))
  assert_true(crossing.is_member(@bin_float.BinFloat::from_double(3.0)))
  assert_true(one.try_atan2(zero) is Ok(_))
  assert_true(crossing.try_atan2(minus_one) is Ok(_))
}

///|
test "atan2 identifies signed zero endpoints with the real interval zero" {
  let ordinate = Interval::from_bounds(
    @bin_float.BinFloat::negative_zero(precision=53),
    @bin_float.BinFloat::zero(precision=53),
    precision=53,
  )
  let actual = ordinate.atan2(Interval::entire(precision=53))
  let rounded = actual.apply_ctx(IntervalContext::binary64()).0
  assert_true(rounded.lower_bound().is_zero())
  assert_eq(
    rounded.upper_bound().compare(expected_binary64("0x1921FB54442D19p-51")),
    0,
  )
}

///|
test "decorated atan2 downgrades an upper-side branch-cut touch" {
  let ordinate = DecoratedInterval::new(
    Interval::from_bounds(
      @bin_float.BinFloat::negative_zero(precision=53),
      @bin_float.BinFloat::one(precision=53),
      precision=53,
    ),
    decoration=Decoration::Com,
  )
  let abscissa = DecoratedInterval::new(
    Interval::from_bounds(
      @bin_float.BinFloat::from_int(-2, precision=53),
      @bin_float.BinFloat::from_double(-0.1, precision=53),
      precision=53,
    ),
    decoration=Decoration::Com,
  )
  assert_true(ordinate.atan2(abscissa).decoration() == Decoration::Dac)
}
