///|
test "certified atan2 handles axes and branch cut" {
  let zero = BallFloat::from_double(0.0, precision=53)
  let one = BallFloat::from_double(1.0, precision=53)
  let minus_one = BallFloat::from_double(-1.0, precision=53)
  assert_true(
    one
    .atan2_interval(zero)
    .contains(@bin_float.BinFloat::from_double(1.5707963267948966)),
  )
  assert_true(zero.atan2_interval(one).contains(@bin_float.BinFloat::zero()))
  let crossing = BallFloat::from_bounds(
    @bin_float.BinFloat::from_double(-1.0),
    @bin_float.BinFloat::from_double(1.0),
    precision=53,
  ).atan2_interval(minus_one)
  assert_true(crossing.contains(@bin_float.BinFloat::from_double(-3.0)))
  assert_true(crossing.contains(@bin_float.BinFloat::from_double(3.0)))
  assert_true(one.try_atan2_interval(zero) is Ok(_))
  assert_true(crossing.try_atan2_interval(minus_one) is Ok(_))
}

///|
test "decorated atan2 downgrades an upper-side branch-cut touch" {
  let ordinate = BallFloatDecorated::new(
    BallFloat::from_bounds(
      @bin_float.BinFloat::negative_zero(precision=53),
      @bin_float.BinFloat::one(precision=53),
      precision=53,
    ),
    decoration=Decoration::Com,
  )
  let abscissa = BallFloatDecorated::new(
    BallFloat::from_bounds(
      @bin_float.BinFloat::from_int(-2, precision=53),
      @bin_float.BinFloat::from_double(-0.1, precision=53),
      precision=53,
    ),
    decoration=Decoration::Com,
  )
  assert_true(ordinate.atan2_interval(abscissa).decoration() == Decoration::Dac)
}
