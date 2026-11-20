// floating#383: atan2(y, x) with x > 0 and |y/x| below the implementation
// exponent range used to be an `Err` (the certified point evaluation never
// separated the result from 0). The point enclosure is now [0, smallest
// subnormal of the precision] for y > 0 and its mirror image for y < 0.

///|
test "try_atan2 of a quotient below the exponent range encloses zero tightly" {
  let tiny_unit = @bin_float.BinFloat::make(
    @bin_float.BinCoeff::one(),
    -1073741874,
    64,
  )
  for e in [1073741000, 540000000] {
    for negative in [false, true] {
      let y = @bin_float.BinFloat::make(
        @bin_float.BinCoeff::from_uint64(5UL),
        -e,
        64,
        negative~,
      )
      let x = @bin_float.BinFloat::make(
        @bin_float.BinCoeff::from_uint64(7UL),
        e,
        64,
      )
      let r = BallFloat::exact(y, precision=53)
        .try_atan2(BallFloat::exact(x, precision=53))
        .unwrap()
      let (low, high) = if negative {
        (tiny_unit.neg(), @bin_float.BinFloat::negative_zero())
      } else {
        (@bin_float.BinFloat::zero(), tiny_unit)
      }
      assert_eq(r.lower_bound().compare(low), 0)
      assert_eq(r.upper_bound().compare(high), 0)
      assert_eq(r.lower_bound().is_negative(), negative)
    }
  }
}
