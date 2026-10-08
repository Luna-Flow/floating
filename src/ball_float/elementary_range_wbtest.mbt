///|
fn elementary_range_power(
  exponent : Int,
  precision : Int,
) -> @bin_float.BinFloat {
  @bin_float.BinFloat::make(@bin_float.BinCoeff::one(), exponent, precision)
}

///|
/// An integer endpoint outside the exponent range has no exact power of two;
/// building one rounded to nearest gave `{0}` below the range and a lower
/// bound of `+inf` (an abort) above it.
test "exp2_interval encloses integer endpoints beyond the exponent range" {
  for n in [-1073742000, -1073741900, -1073741824, -2147483647 - 1] {
    let y = BallFloat::from_int(n, precision=53).exp2_interval()
    assert_true(y.lower_bound().compare(@bin_float.BinFloat::zero()) >= 0)
    assert_true(y.upper_bound().compare(@bin_float.BinFloat::zero()) > 0)
  }
  for n in [1073741824, 2147483647] {
    let y = BallFloat::from_int(n, precision=53).exp2_interval()
    assert_eq(y.upper_bound().classify(), FpClass::Infinity)
    assert_eq(y.lower_bound().classify(), FpClass::Finite)
  }
  // Integer endpoints inside the range stay exact.
  for
    n in [
      @bin_float.binary_implementation_e_min, -1074, 0, 1023, @bin_float.binary_implementation_e_max,
    ] {
    let y = BallFloat::from_int(n, precision=53).exp2_interval()
    let expected = elementary_range_power(n, 53)
    assert_eq(y.lower_bound().compare(expected), 0)
    assert_eq(y.upper_bound().compare(expected), 0)
  }
}

///|
/// `ln` of a value just above 1 at high precision reduced the series bounds to
/// rationals whose gcd went through the Lehmer loop with operands of different
/// lengths, which never finished. `asinh` and `atanh` of tiny arguments go
/// through the same `ln`.
test "ln_interval of a value just above 1 at high precision terminates" {
  let precision = 245
  let v = @bin_float.BinFloat::one(precision~).add(
    elementary_range_power(-243, precision),
  )
  let y = BallFloat::exact(v, precision~).ln_interval()
  assert_true(y.lower_bound().compare(@bin_float.BinFloat::zero()) > 0)
  assert_true(y.upper_bound().compare(elementary_range_power(-243, 53)) <= 0)
  for exponent in [-238, -243] {
    let w = @bin_float.BinFloat::one(precision=300).add(
      elementary_range_power(exponent, 300),
    )
    assert_true(BallFloat::exact(w, precision=300).ln_interval().is_bounded())
  }
}

///|
test "asinh_interval and atanh_interval of a tiny argument terminate" {
  let x = elementary_range_power(-300, 53)
  let zero = @bin_float.BinFloat::zero()
  // asinh(x) and atanh(x) lie within a relative 2^-500 of x. The enclosures
  // are not tight for such tiny arguments, so only inclusion is checked.
  for
    y in [
      BallFloat::exact(x).asinh_interval(),
      BallFloat::exact(x).atanh_interval(),
    ] {
    assert_true(y.lower_bound().compare(zero) >= 0)
    assert_true(y.lower_bound().compare(x) <= 0)
    assert_true(y.upper_bound().compare(elementary_range_power(-301, 53)) >= 0)
    assert_eq(y.upper_bound().classify(), FpClass::Finite)
  }
}
