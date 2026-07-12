///|
fn relation_interval(lo : Int, hi : Int) -> BallFloat {
  BallFloat::from_bounds(
    @bin_float.BinFloat::from_int(lo, precision=32),
    @bin_float.BinFloat::from_int(hi, precision=32),
    precision=32,
  )
}

///|
test "IEEE 1788 set relations follow endpoint definitions" {
  let empty = BallFloat::empty(precision=32)
  let entire = BallFloat::whole(precision=32)
  let left = relation_interval(1, 2)
  let right = relation_interval(2, 4)
  assert_true(empty.subset(left))
  assert_true(empty.less(empty))
  assert_false(empty.less(left))
  assert_true(empty.precedes(left))
  assert_true(left.precedes(right))
  assert_false(left.strictly_precedes(right))
  assert_true(empty.disjoint(entire))
  assert_true(entire.interior(entire))
  assert_true(entire.strictly_less(entire))
}

///|
test "IEEE 1788 interior permits shared infinite endpoints" {
  let precision = 32
  let negative_infinity = @bin_float.BinFloat::inf(Sign::Negative, precision~)
  let positive_infinity = @bin_float.BinFloat::inf(Sign::Positive, precision~)
  let zero = @bin_float.BinFloat::zero(precision~)
  let one = @bin_float.BinFloat::one(precision~)
  let left_half = BallFloat::from_bounds(negative_infinity, zero, precision~)
  let wider_left_half = BallFloat::from_bounds(
    negative_infinity,
    one,
    precision~,
  )
  let right_half = BallFloat::from_bounds(zero, positive_infinity, precision~)
  let wider_right_half = BallFloat::from_bounds(
    @bin_float.BinFloat::from_int(-1, precision~),
    positive_infinity,
    precision~,
  )
  assert_true(left_half.interior(wider_left_half))
  assert_true(right_half.interior(wider_right_half))
  assert_true(left_half.strictly_less(wider_left_half))
}

///|
test "IEEE 1788 overlap classification is exhaustive on representative pairs" {
  let empty = BallFloat::empty(precision=32)
  let a = relation_interval(1, 2)
  let b = relation_interval(3, 4)
  let meeting = relation_interval(2, 3)
  let containing = relation_interval(0, 3)
  assert_true(empty.overlap_state(empty) == BothEmpty)
  assert_true(a.overlap_state(b) == Before)
  assert_true(a.overlap_state(meeting) == Meets)
  assert_true(a.overlap_state(containing) == ContainedBy)
  assert_true(containing.overlap_state(a) == ContainsInterval)
  assert_true(a.overlap_state(a) == EqualIntervals)
}
