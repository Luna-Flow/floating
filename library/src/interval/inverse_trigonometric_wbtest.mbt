///|
test "certified atan contains exact origin and odd symmetry" {
  let zero = Interval::from_double(0.0, precision=53).atan()
  assert_true(zero.is_member(@bin_float.BinFloat::zero()))
  let positive = Interval::from_double(1.0, precision=53).atan()
  let negative = Interval::from_double(-1.0, precision=53).atan()
  assert_true(positive.neg().equal(negative))
}
