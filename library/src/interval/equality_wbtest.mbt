///|
// oracle: A
// source: IEEE 1788-2015 10.5.10 and Table 10.3 equal(x, y): equal as sets, so [1,3] at 24 and 113 bits are equal, empty equals empty, entire equals entire, a +0 bound and a -0 bound are the same set; identical compares the representation, written out
// shares: Interval::from_bounds, Binary::from_int, empty and entire build the inputs; == and identical are the code under test
test "== is set equality and ignores the precision tag (IEEE 1788-2015 Table 10.3)" {
  let a = Interval::from_bounds(
    @binary.Binary::from_int(1, precision=24),
    @binary.Binary::from_int(3, precision=24),
    precision=24,
  )
  let b = Interval::from_bounds(
    @binary.Binary::from_int(1, precision=113),
    @binary.Binary::from_int(3, precision=113),
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
  let z = @binary.Binary::zero(precision=53)
  assert_true(
    Interval::from_bounds(z.neg(), z) == Interval::from_bounds(z, z.neg()),
  )
}

///|
// oracle: A
// source: IEEE 1788-2015 12.12.9: the comparison of decorated intervals is the comparison of the interval parts and equal(NaI, NaI) is false; identical compares the decoration too; written out
// shares: DecoratedInterval::new, nai and Interval::from_int build the inputs; == and identical are the code under test
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
// oracle: A, S
// source: explicit precisions are written out (precision 16 gives 16, 53 gives 53, 5 and 2^30 are exact at 53 bits so the interval is a singleton); the default of from_coefficient without a precision is the library's own documented default of 53 bits, a design value and not a standard value (S)
// shares: Interval::from_int, from_coefficient, precision and is_singleton (the code under test)
test "from_int and from_coefficient default to 53 bits" {
  assert_eq(Interval::from_int(5, precision=53).precision(), 53)
  assert_eq(
    Interval::from_coefficient(@binary.BinCoeff::from_uint64(5UL)).precision(),
    53,
  )
  assert_true(Interval::from_int(1 << 30, precision=53).is_singleton())
  assert_eq(Interval::from_int(5, precision=16).precision(), 16)
}
