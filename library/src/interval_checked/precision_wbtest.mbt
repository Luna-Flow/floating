///|
test "the checked constructors return an error for a precision outside the limits" {
  let one = @bin_float.BinFloat::one(precision=53)
  for p in [0, -1, @bin_float.binary_precision_max + 1] {
    assert_true(IntervalResult::from_int(3, precision=p).is_err())
    assert_true(
      IntervalResult::from_coefficient(@bin_float.BinCoeff::one(), precision=p).is_err(),
    )
    assert_true(IntervalResult::from_double(1.5, precision=p).is_err())
    assert_true(IntervalResult::from_float(1.5, precision=p).is_err())
    assert_true(IntervalResult::exact(one, precision=p).is_err())
    assert_true(IntervalResult::from_bounds(one, one, precision=p).is_err())
    assert_true(IntervalResult::entire(precision=p).is_err())
  }
  assert_true(IntervalResult::from_int(3, precision=16).is_ok())
}
