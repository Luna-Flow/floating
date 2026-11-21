// `cancelMinus` / `cancelPlus` (IEEE 1788-2015 9.2, 12.12.5) at the bottom of the
// exponent range (issue #582): Entire exactly when width(x) < width(y), decided on
// the exact end values; equal widths give a point.

///|
fn cn_next(state : Ref[UInt64]) -> UInt64 {
  let mut x = state.val
  x = x ^ (x << 13)
  x = x ^ (x >> 7)
  x = x ^ (x << 17)
  state.val = x
  x
}

///|
fn cn_value(
  c : UInt64,
  exponent : Int32,
  negative : Bool,
) -> @bin_float.BinFloat {
  @bin_float.BinFloat::make(
    @bin_float.BinCoeff::from_uint64(c),
    exponent,
    200,
    negative~,
  )
}

///|
/// `[lo, hi]` of multiples of `2^exponent`, coefficients signed.
fn cn_ball(
  lo : Int64,
  hi : Int64,
  exponent : Int32,
  precision : Int32,
) -> BallFloat {
  let value = fn(c : Int64) {
    cn_value(
      if c < 0L {
        (-c).reinterpret_as_uint64()
      } else {
        c.reinterpret_as_uint64()
      },
      exponent,
      c < 0L,
    )
  }
  BallFloat::from_bounds(value(lo), value(hi), precision~)
}

///|
test "cancel_plus and cancel_minus at the bottom of the range: the cases of the issue" {
  let e_min = @bin_float.binary_implementation_e_min
  let u = e_min - 60
  // lo = x.lo + y.hi = 4u > hi = x.hi + y.lo = 3u: width(x) = u < width(y) = 2u
  let x = cn_ball(1L, 2L, u, 113)
  let y = cn_ball(1L, 3L, u, 113)
  assert_true(x.cancel_plus(y).is_entire())
  // lo = x.lo - y.lo = 0 > hi = x.hi - y.hi = -2u: width(x) = 2u < width(y) = 4u
  let x = cn_ball(1L, 3L, u, 113)
  let y = cn_ball(1L, 5L, u, 113)
  assert_true(x.cancel_minus(y).is_entire())
}

///|
test "equal widths give a point, with a canonical zero" {
  let e_min = @bin_float.binary_implementation_e_min
  let u = e_min - 60
  // cancel_minus([1u, 3u], [0, 2u]) = [1u, 1u]
  let z = cn_ball(1L, 3L, u, 113).cancel_minus(cn_ball(0L, 2L, u, 113))
  assert_eq(z.lower_bound().compare(cn_value(1UL, u, false)), 0)
  assert_eq(z.upper_bound().compare(cn_value(1UL, u, false)), 0)
  // cancel_plus([1u, 3u], [-2u, 0]) = cancel_minus(x, [0, 2u]) = [1u, 1u]
  let z = cn_ball(1L, 3L, u, 113).cancel_plus(cn_ball(-2L, 0L, u, 113))
  assert_eq(z.lower_bound().compare(cn_value(1UL, u, false)), 0)
  assert_eq(z.upper_bound().compare(cn_value(1UL, u, false)), 0)
  // the point 0: [3u, 5u] - [3u, 5u] = [0, 0], both ends +0
  let z = cn_ball(3L, 5L, u, 113).cancel_minus(cn_ball(3L, 5L, u, 113))
  assert_true(z.lower_bound().is_zero() && !z.lower_bound().is_negative())
  assert_true(z.upper_bound().is_zero() && !z.upper_bound().is_negative())
  assert_true(!z.is_entire())
}

///|
/// The oracle: the exact end values by `add_ctx` in 600 bits.
fn cn_check(x : BallFloat, y : BallFloat, plus : Bool) -> Unit {
  let wide = @bin_float.BinaryContext::new(precision=600)
  let (lo, hi) = if plus {
    (
      x.lower_bound().add_ctx(y.upper_bound(), wide).0,
      x.upper_bound().add_ctx(y.lower_bound(), wide).0,
    )
  } else {
    (
      x.lower_bound().sub_ctx(y.lower_bound(), wide).0,
      x.upper_bound().sub_ctx(y.upper_bound(), wide).0,
    )
  }
  let z = if plus { x.cancel_plus(y) } else { x.cancel_minus(y) }
  if lo.compare(hi) > 0 {
    if !z.is_entire() {
      abort(
        "expected Entire: lo \{lo} hi \{hi} got \{z.lower_bound()} \{z.upper_bound()}",
      )
    }
  } else {
    let p = Int32::max(x.precision(), y.precision())
    let down = lo.with_precision(
      p,
      @bin_float.BinaryRoundingMode::RoundTowardNegative,
    )
    let up = hi.with_precision(
      p,
      @bin_float.BinaryRoundingMode::RoundTowardPositive,
    )
    if z.is_entire() ||
      z.lower_bound().compare(down) != 0 ||
      z.upper_bound().compare(up) != 0 {
      abort(
        "ends: expected \{down} \{up}, got \{z.lower_bound()} \{z.upper_bound()}",
      )
    }
  }
}

///|
test "cancel_plus and cancel_minus decide on the exact values near the bottom of the range" {
  let state = Ref(0x9e3779b97f4a7c15UL)
  let e_min = @bin_float.binary_implementation_e_min
  let precisions = [53, 113, 128]
  let mut entire = 0
  let mut points = 0
  for _ in 0..<4000 {
    let exponent = e_min - 65 + (cn_next(state) % 40UL).to_int()
    let a = (cn_next(state) % 1000000UL).reinterpret_as_int64() + 1L
    let b = (cn_next(state) % 1000000UL).reinterpret_as_int64() + 1L
    let d = (cn_next(state) % 1000000UL).reinterpret_as_int64() + 2L
    let delta = (cn_next(state) % 3UL).reinterpret_as_int64() - 1L
    let p = precisions[(cn_next(state) % 3UL).to_int()]
    // widths d and d + delta: Entire exactly when delta > 0
    let x = cn_ball(a, a + d, exponent, p)
    let y = cn_ball(b, b + d + delta, exponent, p)
    cn_check(x, y, false)
    // cancel_plus(x, y) = cancel_minus(x, -y)
    let y_neg = cn_ball(-(b + d + delta), -b, exponent, p)
    cn_check(x, y_neg, true)
    if delta > 0L {
      entire += 1
    }
    if delta == 0L {
      points += 1
    }
  }
  assert_true(entire > 800 && points > 800)
}

///|
test "away from the bottom of the range the result is the same as before" {
  let state = Ref(0x2545f4914f6cdd1dUL)
  for _ in 0..<3000 {
    let exponent = (cn_next(state) % 200UL).to_int() - 100
    let a = (cn_next(state) % 1000000UL).reinterpret_as_int64() + 1L
    let b = (cn_next(state) % 1000000UL).reinterpret_as_int64() + 1L
    let d = (cn_next(state) % 1000000UL).reinterpret_as_int64() + 2L
    let delta = (cn_next(state) % 3UL).reinterpret_as_int64() - 1L
    let x = cn_ball(a, a + d, exponent, 53)
    let y = cn_ball(b, b + d + delta, exponent, 53)
    // the old formula: exact ends made at their own bit length, decision, ends
    let old_lo = exact_sub(
      min_bits=1,
      x.lower_bound(),
      y.lower_bound(),
      mode=BinaryRoundingMode::RoundTowardNegative,
    )
    let old_hi = exact_sub(
      min_bits=1,
      x.upper_bound(),
      y.upper_bound(),
      mode=BinaryRoundingMode::RoundTowardPositive,
    )
    let old = if old_lo.compare(old_hi) > 0 {
      whole_real(53)
    } else {
      quantize_interval(old_lo, old_hi, 53)
    }
    let new = x.cancel_minus(y)
    assert_eq(new.lower_bound(), old.lower_bound())
    assert_eq(new.upper_bound(), old.upper_bound())
  }
}

///|
test "cancel_plus and cancel_minus: the special cases of IEEE 1788-2015 12.12.5" {
  let bounded = cn_ball(1L, 3L, 0, 53)
  let empty = BallFloat::empty(precision=53)
  let unbounded = BallFloat::entire(precision=53)
  let half_bounded = BallFloat::from_bounds(
    cn_value(1UL, 0, false),
    @bin_float.BinFloat::inf(Sign::Positive, precision=53),
    precision=53,
  )
  for plus in [false, true] {
    let op = fn(x : BallFloat, y : BallFloat) {
      if plus {
        x.cancel_plus(y)
      } else {
        x.cancel_minus(y)
      }
    }
    // x empty and y bounded: Empty
    assert_true(op(empty, bounded).is_empty())
    // x nonempty and y empty: Entire
    assert_true(op(bounded, empty).is_entire())
    // either operand unbounded: Entire
    assert_true(op(unbounded, bounded).is_entire())
    assert_true(op(bounded, unbounded).is_entire())
    assert_true(op(half_bounded, bounded).is_entire())
    assert_true(op(bounded, half_bounded).is_entire())
    // empty and unbounded: no Level 1 value, Entire
    assert_true(op(empty, unbounded).is_entire())
  }
}
