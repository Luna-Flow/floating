// Interval enclosure of exp2 at the smallest representable powers of two (#271).
// `try_exp2` rounds both endpoints through `BinFloat::exp2_ctx`; when
// that returned +0 for the exact subnormal 2^-2^30 the enclosure was {0}, which
// does not contain the true value.
//
// IEEE 1788-2015 requires the result of an interval operation to contain the
// image of every point of the operand, and IEEE 754-2019 §9.2 ("A conforming
// operation shall return results correctly rounded for the applicable rounding
// direction for all operands in its domain.") fixes the endpoint values.

///|
test "exp2 enclosures contain the exact subnormal powers of two" {
  for n in [-1073741823, -1073741824, -1073741825, -1073741900] {
    let exact = @bin_float.BinFloat::make(@bin_float.BinCoeff::one(), n, 53)
    let point = BallFloat::from_int(n, precision=53)
    assert_true(point.exp2().is_member(exact))
    assert_true(point.try_exp2().unwrap().is_member(exact))
  }
}
