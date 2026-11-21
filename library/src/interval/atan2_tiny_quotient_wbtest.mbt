// floating#383: atan2(y, x) with x > 0 and |y/x| below the implementation
// exponent range used to be an `Err` (the certified point evaluation never
// separated the result from 0). The point enclosure is now [0, smallest
// subnormal of the precision] for y > 0 and its mirror image for y < 0.

///|
test "try_atan2 of a quotient below the exponent range encloses zero tightly" {
  let tiny_unit = @binary.Binary::make(@binary.BinCoeff::one(), -1073741874, 64)
  for e in [1073741000, 540000000] {
    for negative in [false, true] {
      let y = @binary.Binary::make(
        @binary.BinCoeff::from_uint64(5UL),
        -e,
        64,
        negative~,
      )
      let x = @binary.Binary::make(@binary.BinCoeff::from_uint64(7UL), e, 64)
      let r = Interval::exact(y, precision=53)
        .try_atan2(Interval::exact(x, precision=53))
        .unwrap()
      let (low, high) = if negative {
        (tiny_unit.neg(), @binary.Binary::zero())
      } else {
        (@binary.Binary::zero(), tiny_unit)
      }
      assert_eq(r.lower_bound().compare(low), 0)
      assert_eq(r.upper_bound().compare(high), 0)
      // The old assertion was `lower_bound().is_negative() == negative` and, for a negative
      // quotient, a -0 upper bound. 12.12.8 requires `inf` to return -0 for a Level 1 value of 0
      // and `sup` +0: a zero lower bound is -0 (negative) for either sign of the quotient, and
      // a zero upper bound is +0.
      assert_true(r.lower_bound().is_negative())
      assert_true(!r.upper_bound().is_negative())
    }
  }
}
