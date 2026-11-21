///|
fn elementary_range_power(
  exponent : Int32,
  precision : Int32,
) -> @binary.Binary {
  @binary.Binary::make(@binary.BinCoeff::one(), exponent, precision)
}

///|
/// An integer endpoint outside the exponent range has no exact power of two;
/// building one rounded to nearest gave `{0}` below the range and a lower
/// bound of `+inf` (an abort) above it.
test "exp2 encloses integer endpoints beyond the exponent range" {
  for n in [-1073742000, -1073741900, -1073741824, -2147483647 - 1] {
    let y = Interval::from_int(n, precision=53).exp2()
    assert_true(y.lower_bound().compare(@binary.Binary::zero()) >= 0)
    assert_true(y.upper_bound().compare(@binary.Binary::zero()) > 0)
  }
  for n in [1073741824, 2147483647] {
    let y = Interval::from_int(n, precision=53).exp2()
    assert_eq(y.upper_bound().classify(), FpClass::Infinity)
    assert_eq(y.lower_bound().classify(), FpClass::Finite)
  }
  // Integer endpoints inside the range stay exact.
  for
    n in [
      @binary.binary_value_e_min, -1074, 0, 1023, @binary.binary_value_e_max,
    ] {
    let y = Interval::from_int(n, precision=53).exp2()
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
test "ln of a value just above 1 at high precision terminates" {
  let precision = 245
  let v = @binary.Binary::one(precision~).add(
    elementary_range_power(-243, precision),
  )
  let y = Interval::exact(v, precision~).ln()
  assert_true(y.lower_bound().compare(@binary.Binary::zero()) > 0)
  assert_true(y.upper_bound().compare(elementary_range_power(-243, 53)) <= 0)
  for exponent in [-238, -243] {
    let w = @binary.Binary::one(precision=300).add(
      elementary_range_power(exponent, 300),
    )
    assert_true(Interval::exact(w, precision=300).ln().is_common_interval())
  }
}

///|
test "asinh and atanh of a tiny argument terminate" {
  let x = elementary_range_power(-300, 53)
  let zero = @binary.Binary::zero()
  // asinh(x) and atanh(x) lie within a relative 2^-500 of x. The enclosures
  // are not tight for such tiny arguments, so only inclusion is checked.
  for y in [Interval::exact(x).asinh(), Interval::exact(x).atanh()] {
    assert_true(y.lower_bound().compare(zero) >= 0)
    assert_true(y.lower_bound().compare(x) <= 0)
    assert_true(y.upper_bound().compare(elementary_range_power(-301, 53)) >= 0)
    assert_eq(y.upper_bound().classify(), FpClass::Finite)
  }
}
