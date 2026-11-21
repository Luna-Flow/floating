// #443: IEEE 1788-2015 11.5.2, setDec(x, ill) returns NaI for any x, empty or
// not; the other two forbidden combinations are repaired (empty with com is
// trv, unbounded with com is dac).

///|
test "new with the decoration ill returns NaI (#443)" {
  let one = Interval::from_int(1, precision=53)
  for
    x in [
      one,
      Interval::empty(),
      Interval::entire(),
      Interval::from_int(-7, precision=53),
    ] {
    let d = DecoratedInterval::new(x, decoration=Ill)
    assert_true(d.is_nai())
    assert_true(d.decoration() == Ill)
    assert_true(d.identical(DecoratedInterval::nai(precision=x.precision())))
  }
  // The precision of the interval is kept.
  let p24 = DecoratedInterval::new(
    Interval::from_int(1, precision=24),
    decoration=Ill,
  )
  assert_eq(p24.interval().precision(), 24)
}

///|
test "the other forbidden combinations of 11.5.2 are repaired (#443)" {
  let empty = DecoratedInterval::new(Interval::empty(), decoration=Com)
  assert_true(empty.decoration() == Trv)
  assert_false(empty.is_nai())
  let entire = DecoratedInterval::new(Interval::entire(), decoration=Com)
  assert_true(entire.decoration() == Dac)
  for decoration in [Trv, Def, Dac, Com] {
    let d = DecoratedInterval::new(
      Interval::from_int(2, precision=53),
      decoration~,
    )
    assert_false(d.is_nai())
  }
}
