///|
test "midpoint_ctx rounds to nearest once" {
  // 2^-6 + 2^-20 lies in the subnormal range of a 4-bit context with
  // e_min = -2 (grid 2^-5); the nearest grid point is 2^-5, not 0.
  let c = endpoint_rounding_value((1UL << 14) + 1UL, -20, 53)
  let ctx = BallContext::new(precision=4, e_min=-2, e_max=10)
  let (m, flags) = BallFloat::from_bounds(c, c).midpoint_ctx(ctx)
  assert_eq(m.compare(endpoint_rounding_value(1UL, -5, 4)), 0)
  assert_true(flags.inexact())
  assert_true(flags.underflow())
  assert_false(flags.overflow())
}

///|
test "midpoint_ctx applies e_max" {
  let ctx = BallContext::new(precision=53, e_min=-10, e_max=10)
  let big = @bin_float.BinFloat::from_int(1 << 20, precision=53)
  let (m, flags) = BallFloat::from_bounds(big, big).midpoint_ctx(ctx)
  assert_eq(m.classify(), FpClass::Infinity)
  assert_true(m.sign() == Sign::Positive)
  assert_true(flags.overflow())
  assert_true(flags.inexact())
  let (n, negative_flags) = BallFloat::from_bounds(big.neg(), big.neg()).midpoint_ctx(
    ctx,
  )
  assert_eq(n.classify(), FpClass::Infinity)
  assert_true(n.sign() == Sign::Negative)
  assert_true(negative_flags.overflow())
  // The largest finite value of the context is not an overflow.
  let max = context_max_finite(ctx)
  let (kept, kept_flags) = BallFloat::from_bounds(max, max).midpoint_ctx(ctx)
  assert_eq(kept.compare(max), 0)
  assert_true(kept_flags == BallFlags::new())
  // 1984 lies halfway between 1920, the largest finite value of a 4-bit
  // context with e_max = 10, and 2048; ties to even rounds it up past e_max.
  let small_ctx = BallContext::new(precision=4, e_min=-2, e_max=10)
  let tie = @bin_float.BinFloat::from_int(1984, precision=53)
  let (rounded_up, tie_flags) = BallFloat::from_bounds(tie, tie).midpoint_ctx(
    small_ctx,
  )
  assert_eq(rounded_up.classify(), FpClass::Infinity)
  assert_true(tie_flags.overflow())
  let below = @bin_float.BinFloat::from_int(1950, precision=53)
  let (rounded_down, below_flags) = BallFloat::from_bounds(below, below).midpoint_ctx(
    small_ctx,
  )
  assert_eq(rounded_down.compare(context_max_finite(small_ctx)), 0)
  assert_false(below_flags.overflow())
  assert_true(below_flags.inexact())
}

///|
test "midpoint_ctx keeps exact and normal centers" {
  let ctx = BallContext::new(precision=4, e_min=-2, e_max=10)
  let (m, flags) = BallFloat::from_int(-3, precision=53).midpoint_ctx(ctx)
  assert_eq(m.compare(@bin_float.BinFloat::from_int(-3)), 0)
  assert_true(flags == BallFlags::new())
  let tiny = endpoint_rounding_value(1UL, -5, 53)
  let (t, tiny_flags) = BallFloat::from_bounds(tiny, tiny).midpoint_ctx(ctx)
  assert_eq(t.compare(tiny), 0)
  assert_true(tiny_flags == BallFlags::new())
}

///|
test "apply_ctx raises underflow for a tiny inexact endpoint" {
  // 2^-3 (1 + 2^-10) is below 2^e_min = 2^-2; rounding it down to 4 bits
  // gives 2^-3, which is on the subnormal grid, so only the first step is
  // inexact. The result is tiny and inexact, which IEEE 754 calls underflow.
  let v = endpoint_rounding_value((1UL << 10) + 1UL, -13, 53)
  let ctx = BallContext::new(precision=4, e_min=-2, e_max=10)
  let x = BallFloat::from_bounds(v, endpoint_rounding_value(1UL, -2, 53))
  let (r, flags) = x.apply_ctx(ctx)
  assert_eq(r.lower_bound().compare(endpoint_rounding_value(1UL, -3, 4)), 0)
  assert_true(flags.inexact())
  assert_true(flags.underflow())
  assert_false(flags.overflow())
}

///|
test "apply_ctx does not raise underflow for exact tiny endpoints" {
  let ctx = BallContext::new(precision=4, e_min=-2, e_max=10)
  let tiny = endpoint_rounding_value(1UL, -5, 53)
  let (r, flags) = BallFloat::from_bounds(tiny, tiny).apply_ctx(ctx)
  assert_true(r.contains(tiny))
  assert_true(flags == BallFlags::new())
  // An inexact endpoint in the normal range is not an underflow.
  let (_, normal_flags) = BallFloat::from_bounds(
    @bin_float.BinFloat::one(precision=53),
    endpoint_rounding_value(17UL, -4, 53),
  ).apply_ctx(ctx)
  assert_true(normal_flags.inexact())
  assert_false(normal_flags.underflow())
}

///|
test "midpoint_ctx follows the IEEE 1788 mid cases" {
  // IEEE 1788-2015 12.12.8: NaN for Empty, 0 for Entire, the finite number
  // of largest magnitude for a half-bounded interval, +0 for a zero midpoint.
  let ctx = BallContext::new(precision=4, e_min=-2, e_max=10)
  let max = context_max_finite(ctx)
  let (e, empty_flags) = BallFloat::empty(precision=53).midpoint_ctx(ctx)
  assert_eq(e.classify(), FpClass::NaN)
  assert_true(empty_flags == BallFlags::new())
  let one = @bin_float.BinFloat::one(precision=53)
  let (up, up_flags) = BallFloat::from_bounds(one, pos_inf(53)).midpoint_ctx(
    ctx,
  )
  assert_eq(up.compare(max), 0)
  assert_true(up_flags == BallFlags::new())
  let (down, down_flags) = BallFloat::from_bounds(neg_inf(53), one).midpoint_ctx(
    ctx,
  )
  assert_eq(down.compare(max.neg()), 0)
  assert_true(down_flags == BallFlags::new())
  let (z, zero_flags) = BallFloat::from_bounds(
    @bin_float.BinFloat::zero(precision=53).neg(),
    @bin_float.BinFloat::zero(precision=53).neg(),
  ).midpoint_ctx(ctx)
  assert_true(z.is_zero())
  assert_false(z.is_negative_zero())
  assert_true(zero_flags == BallFlags::new())
}
