///|
/// The previous `certified_pi_interval` (Machin's formula on rationals),
/// test-only (finding 5 of #374).
fn old_certified_pi_interval(precision : Int32) -> BallFloat {
  let (lower, upper) = certified_pi_rational(precision + 64)
  store_interval(
    rat_dyadic_bounds(lower, precision).0,
    rat_dyadic_bounds(upper, precision).1,
    precision,
  )
}

///|
test "certified pi interval is contained in the Machin interval and contains pi" {
  let mut precision = 2
  while precision <= 400 {
    let fresh = certified_pi_interval(precision)
    let old = old_certified_pi_interval(precision)
    // Contained in the old interval.
    assert_true(
      fresh.lo_.compare(old.lo_) >= 0,
      msg="lower bound below the old one at \{precision}",
    )
    assert_true(
      fresh.hi_.compare(old.hi_) <= 0,
      msg="upper bound above the old one at \{precision}",
    )
    // Contains pi: overlaps the much tighter reference.
    let reference = old_certified_pi_interval(precision + 200)
    assert_true(fresh.lo_.compare(reference.hi_) <= 0)
    assert_true(fresh.hi_.compare(reference.lo_) >= 0)
    // Not degenerate.
    assert_true(fresh.lo_.compare(fresh.hi_) < 0)
    precision += if precision < 60 { 1 } else { 23 }
  }
}
