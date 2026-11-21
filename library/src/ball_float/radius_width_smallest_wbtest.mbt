// `radius` and `width` at the bottom of the exponent range (issue #579): `rad(x)`
// is the smallest F-number r with x inside [m - r, m + r], and `wid(x)` the
// width rounded toward +infinity (IEEE 1788-2015 12.12.8). The distances were
// made at their own bit length, so below the normal range they were rounded up
// to the quantum of those few bits, far above the smallest number.
// (the helpers `mid_next` and `mid_value` are those of
// `midpoint_subnormal_wbtest.mbt`)

///|
fn rw_wide() -> @bin_float.BinaryContext {
  @bin_float.BinaryContext::new(precision=600)
}

///|
/// The number of the precision just below `x` (x > 0).
fn rw_below(x : @bin_float.BinFloat, precision : Int32) -> @bin_float.BinFloat {
  x.next_down_ctx(@bin_float.BinaryContext::new(precision~)).0
}

///|
/// `[lo, hi]` inside `[m - r, m + r]`, exactly.
fn rw_covers(
  ball : BallFloat,
  m : @bin_float.BinFloat,
  r : @bin_float.BinFloat,
) -> Bool {
  let wide = rw_wide()
  m.sub_ctx(r, wide).0.compare(ball.lower_bound()) <= 0 &&
  ball.upper_bound().compare(m.add_ctx(r, wide).0) <= 0
}

///|
fn rw_ball(state : Ref[UInt64]) -> BallFloat {
  let e_min = @bin_float.binary_implementation_e_min
  let bits_x = 1 + (mid_next(state) % 60UL).to_int()
  let bits_y = 1 + (mid_next(state) % 60UL).to_int()
  let x = (mid_next(state) % (1UL << bits_x)) | 1UL
  let y = (mid_next(state) % (1UL << bits_y)) | 1UL
  let a = mid_value(x, e_min - 70 + (mid_next(state) % 90UL).to_int(), 200)
  let b = mid_value(y, e_min - 70 + (mid_next(state) % 90UL).to_int(), 200)
  let (lo, hi) = if a.compare(b) <= 0 { (a, b) } else { (b, a) }
  let precisions = [24, 53, 113, 128]
  BallFloat::from_bounds(
    lo,
    hi,
    precision=precisions[(mid_next(state) % 4UL).to_int()],
  )
}

///|
test "radius and width of the interval of the issue" {
  let e_min = @bin_float.binary_implementation_e_min
  let ball = BallFloat::from_bounds(
    mid_value(1UL, e_min - 60, 200),
    mid_value(3UL, e_min - 60, 200),
    precision=113,
  )
  // mid = 2^(e_min - 59); both distances are 2^(e_min - 60); the width is 2^(e_min - 59)
  inspect(ball.radius().to_string(), content="1p-1073741882")
  inspect(ball.width().to_string(), content="1p-1073741881")
}

///|
test "radius and width are the smallest numbers with their properties near the bottom of the range" {
  let state = Ref(0x9e3779b97f4a7c15UL)
  let wide = rw_wide()
  let mut checked = 0
  for _ in 0..<3000 {
    let ball = rw_ball(state)
    let p = ball.precision()
    let m = ball.midpoint()
    let r = ball.radius()
    // r covers the interval
    assert_true(rw_covers(ball, m, r))
    // and no number below it does
    if !r.is_zero() {
      assert_true(!rw_covers(ball, m, rw_below(r, p)))
    }
    // the width is at least hi - lo, and no number below it is
    let exact_width = ball.upper_bound().sub_ctx(ball.lower_bound(), wide).0
    let w = ball.width()
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
    let ball = BallFloat::from_bounds(lo, hi, precision=53)
    let m = ball.midpoint()
    let old_width = upper_round_bound(
      exact_sub(
        min_bits=1,
        ball.upper_bound(),
        ball.lower_bound(),
        mode=BinaryRoundingMode::RoundTowardPositive,
      ),
      53,
    )
    let old_radius = bin_max(
      upper_round_bound(
        exact_sub(
          min_bits=1,
          m,
          ball.lower_bound(),
          mode=BinaryRoundingMode::RoundTowardPositive,
        ),
        53,
      ),
      upper_round_bound(
        exact_sub(
          min_bits=1,
          ball.upper_bound(),
          m,
          mode=BinaryRoundingMode::RoundTowardPositive,
        ),
        53,
      ),
    )
    assert_eq(ball.width(), old_width)
    assert_eq(ball.radius(), old_radius)
  }
}
