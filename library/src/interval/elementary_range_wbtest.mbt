///|
fn elementary_range_power(
  exponent : Int32,
  precision : Int32,
) -> @binary.Binary {
  @binary.Binary::make(@binary.BinCoeff::one(), exponent, precision)
}

///|
// An integer endpoint outside the exponent range has no exact power of two;
// building one rounded to nearest gave `{0}` below the range and a lower
// bound of `+inf` (an abort) above it.
// oracle: A, S
// source: exp2 of an integer n is the exact power 2^n: inside the range (n = e_min, -1074, 0, 1023, e_max) the result is the exact point 2^n (A); beyond the range (n below -1073741824, n above e_max) only the shape is checked: a lower end >= 0 and an upper end > 0 below, an infinite upper end and a finite lower end above (S)
// shares: Interval::from_int, exp2 (the code under test), Binary::make, classify and compare
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
// `ln` of a value just above 1 at high precision reduced the series bounds to
// rationals whose gcd went through the Lehmer loop with operands of different
// lengths, which never finished. `asinh` and `atanh` of tiny arguments go
// through the same `ln`.
// oracle: A, S
// source: ln(1 + x) < x for x = 2^-243 > 0 and ln(1 + x) > 0 (calculus, written out, A); the other values only check that a common interval comes back (S)
// shares: Binary::one, Binary::add, Binary::make, Interval::exact, lower_bound, upper_bound, compare and is_common_interval; ln is the code under test
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
// oracle: S
// source: inclusion only, as the comment of the test says: for x = 2^-300 the enclosures of asinh(x) and atanh(x) have a lower end in [0, x], an upper end of at least 2^-301 and finite; no tight end is checked
// shares: Interval::exact, asinh, atanh (the code under test), lower_bound, upper_bound, compare and classify
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
