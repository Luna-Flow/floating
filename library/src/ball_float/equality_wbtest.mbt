///|
test "== is set equality and ignores the precision tag (IEEE 1788-2015 Table 10.3)" {
  let a = BallFloat::from_bounds(
    @bin_float.BinFloat::from_int(1, precision=24),
    @bin_float.BinFloat::from_int(3, precision=24),
    precision=24,
  )
  let b = BallFloat::from_bounds(
    @bin_float.BinFloat::from_int(1, precision=113),
    @bin_float.BinFloat::from_int(3, precision=113),
    precision=113,
  )
  assert_true(a == b)
  assert_false(a != b)
  assert_false(a.identical(b))
  assert_true(a.identical(a))
  assert_true(BallFloat::empty(precision=24) == BallFloat::empty(precision=113))
  assert_false(
    BallFloat::empty(precision=24).identical(BallFloat::empty(precision=113)),
  )
  assert_true(
    BallFloat::entire(precision=24) == BallFloat::entire(precision=53),
  )
  assert_false(a == BallFloat::empty())
  assert_false(BallFloat::empty() == a)
  assert_false(a == BallFloat::from_int(1, precision=53))
  // -0 and +0 bounds are the same set
  let z = @bin_float.BinFloat::zero(precision=53)
  assert_true(
    BallFloat::from_bounds(z.neg(), z) == BallFloat::from_bounds(z, z.neg()),
  )
}

///|
test "== on decorated intervals is the equal relation: NaI is never equal, decorations are ignored" {
  let x = BallFloat::from_int(2, precision=53)
  let com = BallFloatDecorated::new(x, decoration=Com)
  let trv = BallFloatDecorated::new(x, decoration=Trv)
  assert_true(com == trv)
  assert_false(com.identical(trv))
  assert_true(com.identical(BallFloatDecorated::new(x, decoration=Com)))
  let nai = BallFloatDecorated::nai()
  assert_false(nai == nai)
  assert_false(nai == com)
  assert_true(nai.identical(nai))
  assert_false(nai.identical(com))
  assert_true(nai != nai)
}

///|
test "from_int and from_coefficient default to 53 bits" {
  assert_eq(BallFloat::from_int(5, precision=53).precision(), 53)
  assert_eq(
    BallFloat::from_coefficient(@bin_float.BinCoeff::from_uint64(5UL)).precision(),
    53,
  )
  assert_true(BallFloat::from_int(1 << 30, precision=53).is_singleton())
  assert_eq(BallFloat::from_int(5, precision=16).precision(), 16)
}
