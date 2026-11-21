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
// Oracle (level A): written out from the definition of the format. The
// smallest nonzero value of precision 53 in the implementation range is
// 2^(e_min - 52) = 2^-1073741874 (`binary_implementation_e_min` =
// -1073741822). For n >= -1073741874, 2^n is exactly representable, so the
// correctly rounded enclosure of exp2(n) is the point [2^n, 2^n] (IEEE 754-2019
// 9.2: correct rounding; exp2 of an integer is exact). For n = -1073741900 the
// exact value lies strictly between 0 and the smallest subnormal, so the
// enclosure is [0, 2^-1073741874]: rounding down gives +0, rounding up gives
// the smallest subnormal. The constants -1073741822 and 52 are the format
// definition, written here, not read from the library.
test "exp2 enclosures contain the exact subnormal powers of two" {
  for n in [-1073741823, -1073741824, -1073741825] {
    let exact = @bin_float.BinFloat::make(@bin_float.BinCoeff::one(), n, 53)
    let point = BallFloat::from_int(n, precision=53)
    for enclosure in [point.exp2(), point.try_exp2().unwrap()] {
      assert_true(enclosure.is_member(exact))
      assert_eq(enclosure.lo_.compare(exact), 0)
      assert_eq(enclosure.hi_.compare(exact), 0)
    }
  }
  let n = -1073741900
  let smallest = @bin_float.BinFloat::make(
    @bin_float.BinCoeff::one(),
    -1073741874,
    53,
  )
  let point = BallFloat::from_int(n, precision=53)
  for enclosure in [point.exp2(), point.try_exp2().unwrap()] {
    assert_true(enclosure.lo_.is_zero())
    assert_eq(enclosure.hi_.compare(smallest), 0)
  }
}
