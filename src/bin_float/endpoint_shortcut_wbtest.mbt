///|
test "binary_bounds_at_ends evaluates a point once and gives the two-ends result" {
  for d in [0.3, 1.0, 2.5, 40.0] {
    let x = BinFloat::from_double(d, precision=64)
    let y = BinFloat::from_double(d + 0.001, precision=64)
    for w in [64, 130] {
      let mut calls = 0
      let point = binary_bounds_at_ends(x, x, fn(p) {
        calls += 1
        binary_exp_bounds(p, w)
      })
      assert_eq(calls, 1)
      let reference = binary_exp_bounds(x, w).unwrap()
      assert_true(point.unwrap() == reference)
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
      assert_true(pair.unwrap() == (low.0, high.1))
    }
  }
  // A missing end gives None.
  assert_true(
    binary_bounds_at_ends(BinFloat::one(), BinFloat::from_int(2), fn(_) { None })
    is None,
  )
}
