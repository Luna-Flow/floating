///|
// oracle: A
// source: worked by hand from IEEE 754-2019 3.3, 4.3.1 and 7.5: in a 4-bit context with e_max = 3 (e_min = -2, subnormal grid 2^-5) the center 2^-6 + 2^-20 is nearest to 2^-5 on that grid, rounded once, with the inexact and underflow flags and no overflow
// shares: IntervalContext::new, Interval::from_bounds, Interval::from_int, endpoint_rounding_value (a test helper that builds m * 2^e), IntervalFlags and Binary::from_int build the inputs and read the flags; midpoint_ctx and apply_ctx are the code under test
test "midpoint_ctx rounds to nearest once" {
  // 2^-6 + 2^-20 lies in the subnormal range of a 4-bit context with
  // e_min = -2 (grid 2^-5); the nearest grid point is 2^-5, not 0.
  let c = endpoint_rounding_value((1UL << 14) + 1UL, -20, 53)
  let ctx = IntervalContext::new(precision=4, e_max=3)
  let (m, flags) = Interval::from_bounds(c, c).midpoint_ctx(ctx)
  assert_eq(m.compare(endpoint_rounding_value(1UL, -5, 4)), 0)
  assert_true(flags.inexact())
  assert_true(flags.underflow())
  assert_false(flags.overflow())
}

///|
// oracle: A
// source: written out from IEEE 754-2019 3.3, 4.3.1 and 7.4: the largest finite number of precision p and e_max is (2 - 2^(1-p)) * 2^e_max, (2^53 - 1) * 2^-42 for (53, 10) and 15 for (4, 3), written as literals; 2^20 overflows e_max = 10; 15.5 is the tie between 15 and 16 and ties to even gives 16, which overflows; 15.25 rounds to 15
// shares: IntervalContext::new, Interval::from_bounds, Binary::from_int, Binary::make, endpoint_rounding_value (a test helper that builds m * 2^e) and IntervalFlags (to build the inputs and read the flags)
test "midpoint_ctx applies e_max" {
  let ctx = IntervalContext::new(precision=53, e_max=10)
  let big = @binary.Binary::from_int(1 << 20, precision=53)
  let (m, flags) = Interval::from_bounds(big, big).midpoint_ctx(ctx)
  assert_eq(m.classify(), FpClass::Infinity)
  assert_true(m.signum() == Sign::Positive)
  assert_true(flags.overflow())
  assert_true(flags.inexact())
  let (n, negative_flags) = Interval::from_bounds(big.neg(), big.neg()).midpoint_ctx(
    ctx,
  )
  assert_eq(n.classify(), FpClass::Infinity)
  assert_true(n.signum() == Sign::Negative)
  assert_true(negative_flags.overflow())
  // The largest finite value of the context is not an overflow.
  // (2 - 2^(1 - p)) * 2^e_max = (2^53 - 1) * 2^-42 for p = 53, e_max = 10
  let max = @binary.Binary::make(
    @binary.BinCoeff::from_uint64((1UL << 53) - 1UL),
    -42,
    53,
  )
  let (kept, kept_flags) = Interval::from_bounds(max, max).midpoint_ctx(ctx)
  assert_eq(kept.compare(max), 0)
  assert_true(kept_flags == IntervalFlags::new())
  // 15.5 lies halfway between 15, the largest finite value of a 4-bit
  // context with e_max = 3, and 16; ties to even rounds it up past e_max.
  let small_ctx = IntervalContext::new(precision=4, e_max=3)
  let tie = endpoint_rounding_value(31UL, -1, 53)
  let (rounded_up, tie_flags) = Interval::from_bounds(tie, tie).midpoint_ctx(
    small_ctx,
  )
  assert_eq(rounded_up.classify(), FpClass::Infinity)
  assert_true(tie_flags.overflow())
  let below = endpoint_rounding_value(61UL, -2, 53)
  let (rounded_down, below_flags) = Interval::from_bounds(below, below).midpoint_ctx(
    small_ctx,
  )
  assert_eq(rounded_down.compare(@binary.Binary::from_int(15)), 0)
  assert_false(below_flags.overflow())
  assert_true(below_flags.inexact())
}

///|
// oracle: A
// source: worked by hand from IEEE 754-2019 3.3: -3 and 2^-5 are exact numbers of a 4-bit context with e_max = 3 (2^-5 is the smallest subnormal), so the center is unchanged and no flag is raised
// shares: IntervalContext::new, Interval::from_bounds, Interval::from_int, endpoint_rounding_value (a test helper that builds m * 2^e), IntervalFlags and Binary::from_int build the inputs and read the flags; midpoint_ctx and apply_ctx are the code under test
test "midpoint_ctx keeps exact and normal centers" {
  let ctx = IntervalContext::new(precision=4, e_max=3)
  let (m, flags) = Interval::from_int(-3, precision=53).midpoint_ctx(ctx)
  assert_eq(m.compare(@binary.Binary::from_int(-3)), 0)
  assert_true(flags == IntervalFlags::new())
  let tiny = endpoint_rounding_value(1UL, -5, 53)
  let (t, tiny_flags) = Interval::from_bounds(tiny, tiny).midpoint_ctx(ctx)
  assert_eq(t.compare(tiny), 0)
  assert_true(tiny_flags == IntervalFlags::new())
}

///|
// oracle: A
// source: worked by hand from IEEE 754-2019 7.5 in a 4-bit context with e_max = 3: 2^-3 (1 + 2^-10) is below 2^e_min = 2^-2 and not on the subnormal grid 2^-5, so rounding down gives 2^-3 with the inexact and underflow flags
// shares: IntervalContext::new, Interval::from_bounds, Interval::from_int, endpoint_rounding_value (a test helper that builds m * 2^e), IntervalFlags and Binary::from_int build the inputs and read the flags; midpoint_ctx and apply_ctx are the code under test
test "apply_ctx raises underflow for a tiny inexact endpoint" {
  // 2^-3 (1 + 2^-10) is below 2^e_min = 2^-2; rounding it down to 4 bits
  // gives 2^-3, which is on the subnormal grid, so only the first step is
  // inexact. The result is tiny and inexact, which IEEE 754 calls underflow.
  let v = endpoint_rounding_value((1UL << 10) + 1UL, -13, 53)
  let ctx = IntervalContext::new(precision=4, e_max=3)
  let x = Interval::from_bounds(v, endpoint_rounding_value(1UL, -2, 53))
  let (r, flags) = x.apply_ctx(ctx)
  assert_eq(r.lower_bound().compare(endpoint_rounding_value(1UL, -3, 4)), 0)
  assert_true(flags.inexact())
  assert_true(flags.underflow())
  assert_false(flags.overflow())
}

///|
// oracle: A, S
// source: worked by hand from IEEE 754-2019 7.5: 2^-5 is an exact subnormal of the 4-bit context (no flag), and 17 * 2^-4 = 1.0625 needs 5 bits so it is inexact in the normal range without underflow; the containment check of the exact endpoint is self-consistency (S)
// shares: IntervalContext::new, Interval::from_bounds, Interval::from_int, endpoint_rounding_value (a test helper that builds m * 2^e), IntervalFlags and Binary::from_int build the inputs and read the flags; midpoint_ctx and apply_ctx are the code under test
test "apply_ctx does not raise underflow for exact tiny endpoints" {
  let ctx = IntervalContext::new(precision=4, e_max=3)
  let tiny = endpoint_rounding_value(1UL, -5, 53)
  let (r, flags) = Interval::from_bounds(tiny, tiny).apply_ctx(ctx)
  assert_true(r.is_member(tiny))
  assert_true(flags == IntervalFlags::new())
  // An inexact endpoint in the normal range is not an underflow.
  let (_, normal_flags) = Interval::from_bounds(
    @binary.Binary::one(precision=53),
    endpoint_rounding_value(17UL, -4, 53),
  ).apply_ctx(ctx)
  assert_true(normal_flags.inexact())
  assert_false(normal_flags.underflow())
}

///|
// oracle: A
// source: IEEE 1788-2015 12.12.8 (mid of Empty is NaN, of a half-bounded interval the finite number of largest magnitude, of a zero midpoint +0), with the largest finite number 15 of a 4-bit format with e_max = 3 written out
// shares: IntervalContext::new, Interval::from_bounds, Interval::empty, Binary::from_int, Binary::one, Binary::zero and the helpers pos_inf and neg_inf (to build the inputs)
test "midpoint_ctx follows the IEEE 1788 mid cases" {
  // IEEE 1788-2015 12.12.8: NaN for Empty, 0 for Entire, the finite number
  // of largest magnitude for a half-bounded interval, +0 for a zero midpoint.
  let ctx = IntervalContext::new(precision=4, e_max=3)
  // (2 - 2^-3) * 2^3 = 15, the largest finite number of a 4-bit format with e_max = 3
  let max = @binary.Binary::from_int(15)
  let (e, empty_flags) = Interval::empty(precision=53).midpoint_ctx(ctx)
  assert_eq(e.classify(), FpClass::NaN)
  assert_true(empty_flags == IntervalFlags::new())
  let one = @binary.Binary::one(precision=53)
  let (up, up_flags) = Interval::from_bounds(one, pos_inf(53)).midpoint_ctx(ctx)
  assert_eq(up.compare(max), 0)
  assert_true(up_flags == IntervalFlags::new())
  let (down, down_flags) = Interval::from_bounds(neg_inf(53), one).midpoint_ctx(
    ctx,
  )
  assert_eq(down.compare(max.neg()), 0)
  assert_true(down_flags == IntervalFlags::new())
  let (z, zero_flags) = Interval::from_bounds(
    @binary.Binary::zero(precision=53).neg(),
    @binary.Binary::zero(precision=53).neg(),
  ).midpoint_ctx(ctx)
  assert_true(z.is_zero())
  assert_false(z.is_negative_zero())
  assert_true(zero_flags == IntervalFlags::new())
}
