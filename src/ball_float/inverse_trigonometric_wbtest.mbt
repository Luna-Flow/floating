///|
test "certified atan contains exact origin and odd symmetry" {
  let zero = BallFloat::from_double(0.0, precision=53).atan_interval()
  assert_true(zero.contains(@bin_float.BinFloat::zero()))
  let positive = BallFloat::from_double(1.0, precision=53).atan_interval()
  let negative = BallFloat::from_double(-1.0, precision=53).atan_interval()
  assert_true(positive.neg().set_equal(negative))
}
