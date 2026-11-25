///|
// oracle: S
// source: only Err or Ok is checked, for a precision outside 1..binary_precision_max and for the accepted values 16 and binary_precision_max; the contract of the limits, no numeric value
// shares: binary_precision_max (a limit of the code, not of a standard)
test "the checked constructors return an error for a precision outside the limits" {
  let one = @binary.Binary::one(precision=53)
  for p in [0, -1, @binary.binary_precision_max + 1] {
    assert_true(IntervalChecked::from_int(3, precision=p).is_err())
    assert_true(
      IntervalChecked::from_coefficient(@binary.BinCoeff::one(), precision=p).is_err(),
    )
    assert_true(IntervalChecked::from_double(1.5, precision=p).is_err())
    assert_true(IntervalChecked::from_float(1.5, precision=p).is_err())
    assert_true(IntervalChecked::exact(one, precision=p).is_err())
    assert_true(IntervalChecked::from_bounds(one, one, precision=p).is_err())
    assert_true(IntervalChecked::entire(precision=p).is_err())
  }
  assert_true(IntervalChecked::from_int(3, precision=16).is_ok())
  assert_true(IntervalChecked::from_int(3, precision=1).is_ok())
  assert_true(
    IntervalChecked::from_int(3, precision=@binary.binary_precision_max).is_ok(),
  )
}
