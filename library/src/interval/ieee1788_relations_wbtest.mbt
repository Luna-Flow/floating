///|
fn relation_interval(lo : Int32, hi : Int32) -> Interval {
  Interval::from_bounds(
    @binary.Binary::from_int(lo, precision=32),
    @binary.Binary::from_int(hi, precision=32),
    precision=32,
  )
}

///|
// oracle: A
// source: written out from the endpoint definitions of IEEE 1788-2015 10.5.10 (Table 10.3: subset, less, precedes, strictPrecedes, disjoint, interior, strictLess; Table 10.4 for an empty operand): the empty interval is a subset of every interval, less of itself and not less than a nonempty interval, precedes every interval; [1, 2] precedes [2, 4] but does not strictly precede it; the empty interval is disjoint from Entire; Entire is interior to and strictly less than itself
// shares: relation_interval (Interval::from_bounds with from_int bounds), Interval::empty and entire build the inputs
test "IEEE 1788 set relations follow endpoint definitions" {
  let empty = Interval::empty(precision=32)
  let entire = Interval::entire(precision=32)
  let left = relation_interval(1, 2)
  let right = relation_interval(2, 4)
  assert_true(empty.subset(left))
  assert_true(empty.less(empty))
  assert_false(empty.less(left))
  assert_true(empty.precedes(left))
  assert_true(left.precedes(right))
  assert_false(left.strict_precedes(right))
  assert_true(empty.disjoint(entire))
  assert_true(entire.interior(entire))
  assert_true(entire.strict_less(entire))
}

///|
// oracle: A
// source: written out from the endpoint definitions of IEEE 1788-2015 10.5.10 (Table 10.3: interior, where an infinite end may be shared, and strictLess): (-inf, 0] is interior to (-inf, 1] and [0, +inf) to [-1, +inf), and (-inf, 0] is strictly less than (-inf, 1]
// shares: Binary::inf, zero, one, from_int and Interval::from_bounds build the inputs
test "IEEE 1788 interior permits shared infinite endpoints" {
  let precision = 32
  let negative_infinity = @binary.Binary::inf(negative=true, precision~)
  let positive_infinity = @binary.Binary::inf(precision~)
  let zero = @binary.Binary::zero(precision~)
  let one = @binary.Binary::one(precision~)
  let left_half = Interval::from_bounds(negative_infinity, zero, precision~)
  let wider_left_half = Interval::from_bounds(
    negative_infinity,
    one,
    precision~,
  )
  let right_half = Interval::from_bounds(zero, positive_infinity, precision~)
  let wider_right_half = Interval::from_bounds(
    @binary.Binary::from_int(-1, precision~),
    positive_infinity,
    precision~,
  )
  assert_true(left_half.interior(wider_left_half))
  assert_true(right_half.interior(wider_right_half))
  assert_true(left_half.strict_less(wider_left_half))
}

///|
// oracle: A
// source: the sixteen overlapping states of IEEE 1788-2015 (10.5.14, Table 10.2), each with one pair of
//   integer intervals written out against the reference interval [4, 8]
// shares: nothing (only the call under test, overlap)
test "IEEE 1788 overlap classification covers all sixteen states" {
  let empty = Interval::empty(precision=32)
  let reference = relation_interval(4, 8)
  // the three cases with an empty operand
  assert_true(empty.overlap(empty) == BothEmpty)
  assert_true(empty.overlap(reference) == FirstEmpty)
  assert_true(reference.overlap(empty) == SecondEmpty)
  // the thirteen relations of two nonempty intervals: x.overlap([4, 8])
  assert_true(relation_interval(1, 2).overlap(reference) == Before)
  assert_true(relation_interval(1, 4).overlap(reference) == Meets)
  assert_true(relation_interval(1, 5).overlap(reference) == Overlaps)
  assert_true(relation_interval(4, 6).overlap(reference) == Starts)
  assert_true(relation_interval(5, 7).overlap(reference) == ContainedBy)
  assert_true(relation_interval(6, 8).overlap(reference) == Finishes)
  assert_true(relation_interval(4, 8).overlap(reference) == Equals)
  assert_true(relation_interval(10, 12).overlap(reference) == After)
  assert_true(relation_interval(8, 12).overlap(reference) == MetBy)
  assert_true(relation_interval(6, 12).overlap(reference) == OverlappedBy)
  assert_true(relation_interval(4, 12).overlap(reference) == StartedBy)
  assert_true(relation_interval(3, 9).overlap(reference) == Contains)
  assert_true(relation_interval(2, 8).overlap(reference) == FinishedBy)
}
