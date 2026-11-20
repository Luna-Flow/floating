///|
test "certified atan contains exact origin and odd symmetry" {
  let zero = BallFloat::from_double(0.0, precision=53).atan()
  assert_true(zero.is_member(@bin_float.BinFloat::zero()))
  let positive = BallFloat::from_double(1.0, precision=53).atan()
  let negative = BallFloat::from_double(-1.0, precision=53).atan()
  assert_true(positive.neg().set_equal(negative))
}
