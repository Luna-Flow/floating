///|
test "== is set equality and ignores the precision tag (IEEE 1788-2015 Table 10.3)" {
  let a = Interval::from_bounds(
    @bin_float.BinFloat::from_int(1, precision=24),
    @bin_float.BinFloat::from_int(3, precision=24),
    precision=24,
  )
  let b = Interval::from_bounds(
    @bin_float.BinFloat::from_int(1, precision=113),
    @bin_float.BinFloat::from_int(3, precision=113),
    precision=113,
  )
  assert_true(a == b)
  assert_false(a != b)
  assert_false(a.identical(b))
  assert_true(a.identical(a))
  assert_true(Interval::empty(precision=24) == Interval::empty(precision=113))
  assert_false(
    Interval::empty(precision=24).identical(Interval::empty(precision=113)),
  )
  assert_true(Interval::entire(precision=24) == Interval::entire(precision=53))
  assert_false(a == Interval::empty())
  assert_false(Interval::empty() == a)
  assert_false(a == Interval::from_int(1, precision=53))
  // -0 and +0 bounds are the same set
  let z = @bin_float.BinFloat::zero(precision=53)
  assert_true(
    Interval::from_bounds(z.neg(), z) == Interval::from_bounds(z, z.neg()),
  )
}

///|
test "== on decorated intervals is the equal relation: NaI is never equal, decorations are ignored" {
  let x = Interval::from_int(2, precision=53)
  let com = DecoratedInterval::new(x, decoration=Com)
  let trv = DecoratedInterval::new(x, decoration=Trv)
  assert_true(com == trv)
  assert_false(com.identical(trv))
  assert_true(com.identical(DecoratedInterval::new(x, decoration=Com)))
  let nai = DecoratedInterval::nai()
  assert_false(nai == nai)
  assert_false(nai == com)
  assert_true(nai.identical(nai))
  assert_false(nai.identical(com))
  assert_true(nai != nai)
}

///|
test "from_int and from_coefficient default to 53 bits" {
  assert_eq(Interval::from_int(5, precision=53).precision(), 53)
  assert_eq(
    Interval::from_coefficient(@bin_float.BinCoeff::from_uint64(5UL)).precision(),
    53,
  )
  assert_true(Interval::from_int(1 << 30, precision=53).is_singleton())
  assert_eq(Interval::from_int(5, precision=16).precision(), 16)
}
