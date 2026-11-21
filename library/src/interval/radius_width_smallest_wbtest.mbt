// `radius` and `width` at the bottom of the exponent range (issue #579): `rad(x)`
// is the smallest F-number r with x inside [m - r, m + r], and `wid(x)` the
// width rounded toward +infinity (IEEE 1788-2015 12.12.8). The distances were
// made at their own bit length, so below the normal range they were rounded up
// to the quantum of those few bits, far above the smallest number.
// (the helpers `mid_next` and `mid_value` are those of
// `midpoint_subnormal_wbtest.mbt`)

///|
fn rw_wide() -> @binary.BinaryContext {
  @binary.BinaryContext::new(precision=600)
}

///|
/// The number of the precision just below `x` (x > 0).
fn rw_below(x : @binary.Binary, precision : Int32) -> @binary.Binary {
  x.next_down_ctx(@binary.BinaryContext::new(precision~)).0
}

///|
/// `[lo, hi]` inside `[m - r, m + r]`, exactly.
fn rw_covers(
  interval : Interval,
  m : @binary.Binary,
  r : @binary.Binary,
) -> Bool {
  let wide = rw_wide()
  m.sub_ctx(r, wide).0.compare(interval.lower_bound()) <= 0 &&
  interval.upper_bound().compare(m.add_ctx(r, wide).0) <= 0
}

///|
fn rw_interval(state : Ref[UInt64]) -> Interval {
  let e_min = @binary.binary_implementation_e_min
  let bits_x = 1 + (mid_next(state) % 60UL).to_int()
  let bits_y = 1 + (mid_next(state) % 60UL).to_int()
  let x = (mid_next(state) % (1UL << bits_x)) | 1UL
  let y = (mid_next(state) % (1UL << bits_y)) | 1UL
  let a = mid_value(x, e_min - 70 + (mid_next(state) % 90UL).to_int(), 200)
  let b = mid_value(y, e_min - 70 + (mid_next(state) % 90UL).to_int(), 200)
  let (lo, hi) = if a.compare(b) <= 0 { (a, b) } else { (b, a) }
  let precisions = [24, 53, 113, 128]
  Interval::from_bounds(
    lo,
    hi,
    precision=precisions[(mid_next(state) % 4UL).to_int()],
  )
}

///|
test "radius and width of the interval of the issue" {
  let e_min = @binary.binary_implementation_e_min
  let interval = Interval::from_bounds(
    mid_value(1UL, e_min - 60, 200),
    mid_value(3UL, e_min - 60, 200),
    precision=113,
  )
  // mid = 2^(e_min - 59); both distances are 2^(e_min - 60); the width is 2^(e_min - 59)
  inspect(interval.radius().to_string(), content="1p-1073741882")
  inspect(interval.width().to_string(), content="1p-1073741881")
}

///|
test "radius and width are the smallest numbers with their properties near the bottom of the range" {
  let state = Ref(0x9e3779b97f4a7c15UL)
  let wide = rw_wide()
  let mut checked = 0
  for _ in 0..<3000 {
    let interval = rw_interval(state)
    let p = interval.precision()
    let m = interval.midpoint()
    let r = interval.radius()
    // r covers the interval
    assert_true(rw_covers(interval, m, r))
    // and no number below it does
    if !r.is_zero() {
      assert_true(!rw_covers(interval, m, rw_below(r, p)))
    }
    // the width is at least hi - lo, and no number below it is
    let exact_width = interval
      .upper_bound()
      .sub_ctx(interval.lower_bound(), wide).0
    let w = interval.width()
    assert_true(w.compare(exact_width) >= 0)
    if !w.is_zero() {
      assert_true(rw_below(w, p).compare(exact_width) < 0)
    }
    checked += 1
  }
  assert_eq(checked, 3000)
}

///|
test "radius and width are unchanged away from the bottom of the range" {
  let state = Ref(0x2545f4914f6cdd1dUL)
  for _ in 0..<3000 {
    let x = mid_next(state) % 1000000UL + 1UL
    let y = mid_next(state) % 1000000UL + 1UL
    let a = mid_value(x, (mid_next(state) % 400UL).to_int() - 200, 53)
    let b = mid_value(y, (mid_next(state) % 400UL).to_int() - 200, 53)
    let (lo, hi) = if a.compare(b) <= 0 { (a, b) } else { (b, a) }
    let interval = Interval::from_bounds(lo, hi, precision=53)
    let m = interval.midpoint()
    let old_width = upper_round_bound(
      exact_add_full(interval.upper_bound(), interval.lower_bound().neg()),
      53,
    )
    let old_radius = bin_max(
      upper_round_bound(exact_add_full(m, interval.lower_bound().neg()), 53),
      upper_round_bound(exact_add_full(interval.upper_bound(), m.neg()), 53),
    )
    assert_identical(interval.width(), old_width)
    assert_identical(interval.radius(), old_radius)
  }
}
