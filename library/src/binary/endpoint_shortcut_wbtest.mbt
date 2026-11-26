///|
// oracle: S
// source: the evaluation count (one for a point pair, two for distinct ends) and the comparison of binary_bounds_at_ends with separate calls of binary_exp_bounds at each end (lower of the first, upper of the second); no value of exp is stated from outside
// shares: Binary::from_double builds the arguments; binary_exp_bounds is the evaluation on both sides; binary_bounds_at_ends is the code under test
test "binary_bounds_at_ends evaluates a point once and gives the two-ends result" {
  for d in [0.3, 1.0, 2.5, 40.0] {
    let x = Binary::from_double(d, precision=64)
    let y = Binary::from_double(d + 0.001, precision=64)
    for w in [64, 130] {
      let mut calls = 0
      let point = binary_bounds_at_ends(x, x, fn(p) {
        calls += 1
        binary_exp_bounds(p, w)
      })
      assert_eq(calls, 1)
      let reference = binary_exp_bounds(x, w).unwrap()
      let (point_low, point_high) = point.unwrap()
      assert_true(
        point_low.identical(reference.0) && point_high.identical(reference.1),
      )
      // Distinct ends: both are evaluated, lower of the first and upper of the
      // second.
      let mut pair_calls = 0
      let pair = binary_bounds_at_ends(x, y, fn(p) {
        pair_calls += 1
        binary_exp_bounds(p, w)
      })
      assert_eq(pair_calls, 2)
      let low = binary_exp_bounds(x, w).unwrap()
      let high = binary_exp_bounds(y, w).unwrap()
      let (pair_low, pair_high) = pair.unwrap()
      assert_true(pair_low.identical(low.0) && pair_high.identical(high.1))
    }
  }
  // A missing end gives None.
  assert_true(
    binary_bounds_at_ends(Binary::one(), Binary::from_int(2), fn(_) { None })
    is None,
  )
}
