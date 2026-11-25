///|
// oracle: S
// source: containment only: 0 is a member of expm1 and of log1p of [-0.125, 0.25] (both are 0 at 0, monotone); no end value is checked
// shares: Interval::from_bounds, Binary::from_double, is_member; expm1 and log1p are the code under test
test "expm1 and log1p preserve certified containment" {
  let source = Interval::from_bounds(
    @binary.Binary::from_double(-0.125, precision=53),
    @binary.Binary::from_double(0.25, precision=53),
    precision=53,
  )
  let expm1 = source.expm1()
  assert_true(expm1.is_member(@binary.Binary::from_double(0.0)))
  let log1p = source.log1p()
  assert_true(log1p.is_member(@binary.Binary::from_double(0.0)))
}

///|
// oracle: A
// source: IEEE 1788-2015 Table 9.1: log1p is defined for x > -1: [-0.5] is inside the domain and continuous, so com; [-2, 0] contains points outside the domain, so the result is trv (11.6 min-rule)
// shares: DecoratedInterval::new, decoration; Interval::from_double and from_bounds build the inputs; log1p is the code under test
test "decorated log1p uses its shifted IEEE domain" {
  let inside = DecoratedInterval::new(Interval::from_double(-0.5, precision=53)).log1p()
  assert_eq(inside.decoration(), Com)
  let crossing = DecoratedInterval::new(
    Interval::from_bounds(
      @binary.Binary::from_double(-2.0, precision=53),
      @binary.Binary::from_double(0.0, precision=53),
      precision=53,
    ),
  ).log1p()
  assert_eq(crossing.decoration(), Trv)
}
