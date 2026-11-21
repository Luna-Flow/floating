///|
test "expm1 and log1p preserve certified containment" {
  let source = Interval::from_bounds(
    @bin_float.BinFloat::from_double(-0.125, precision=53),
    @bin_float.BinFloat::from_double(0.25, precision=53),
    precision=53,
  )
  let expm1 = source.expm1()
  assert_true(expm1.is_member(@bin_float.BinFloat::from_double(0.0)))
  let log1p = source.log1p()
  assert_true(log1p.is_member(@bin_float.BinFloat::from_double(0.0)))
}

///|
test "decorated log1p uses its shifted IEEE domain" {
  let inside = DecoratedInterval::new(Interval::from_double(-0.5, precision=53)).log1p()
  assert_eq(inside.decoration(), Com)
  let crossing = DecoratedInterval::new(
    Interval::from_bounds(
      @bin_float.BinFloat::from_double(-2.0, precision=53),
      @bin_float.BinFloat::from_double(0.0, precision=53),
      precision=53,
    ),
  ).log1p()
  assert_eq(crossing.decoration(), Trv)
}
