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
fn cn_value(c : UInt64, exponent : Int32, negative : Bool) -> @binary.Binary {
  @binary.Binary::make(
    @binary.BinCoeff::from_uint64(c),
    exponent,
    200,
    negative~,
  )
}

///|
/// `[lo, hi]` of multiples of `2^exponent`, coefficients signed.
fn cn_interval(
  lo : Int64,
  hi : Int64,
  exponent : Int32,
  precision : Int32,
) -> Interval {
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
  Interval::from_bounds(value(lo), value(hi), precision~)
}

///|
// oracle: A
// source: two cases of the issue worked by hand at the bottom of the range: x = [u, 2u], y = [u, 3u]: cancelPlus bounds 4u > 3u so Entire (width 1u < 2u); x = [u, 3u], y = [u, 5u]: cancelMinus bounds 0 > -2u so Entire (width 2u < 4u); IEEE 1788-2015 10.5.6, 12.12.5
// shares: cn_interval and cn_value (Binary::make, Interval::from_bounds), is_entire; cancel_plus and cancel_minus are the code under test
test "cancel_plus and cancel_minus at the bottom of the range: the cases of the issue" {
  let e_min = @binary.binary_value_e_min
  let u = e_min - 60
  // lo = x.lo + y.hi = 4u > hi = x.hi + y.lo = 3u: width(x) = u < width(y) = 2u
  let x = cn_interval(1L, 2L, u, 113)
  let y = cn_interval(1L, 3L, u, 113)
  assert_true(x.cancel_plus(y).is_entire())
  // lo = x.lo - y.lo = 0 > hi = x.hi - y.hi = -2u: width(x) = 2u < width(y) = 4u
  let x = cn_interval(1L, 3L, u, 113)
  let y = cn_interval(1L, 5L, u, 113)
  assert_true(x.cancel_minus(y).is_entire())
}

///|
// oracle: A
// source: IEEE 1788-2015 10.5.6: equal widths give a point: cancelMinus([1u,3u],[0,2u]) = [1u,1u], cancelPlus([1u,3u],[-2u,0]) = [1u,1u], cancelMinus([3u,5u],[3u,5u]) = [0,0]; 12.12.8 gives a zero lower end as -0 and a zero upper end as +0
// shares: cn_interval and cn_value (Binary::make, Interval::from_bounds), is_zero, is_sign_minus; cancel_plus and cancel_minus are the code under test
test "equal widths give a point, with a canonical zero" {
  let e_min = @binary.binary_value_e_min
  let u = e_min - 60
  // cancel_minus([1u, 3u], [0, 2u]) = [1u, 1u]
  let z = cn_interval(1L, 3L, u, 113).cancel_minus(cn_interval(0L, 2L, u, 113))
  assert_eq(z.lower_bound().compare(cn_value(1UL, u, false)), 0)
  assert_eq(z.upper_bound().compare(cn_value(1UL, u, false)), 0)
  // cancel_plus([1u, 3u], [-2u, 0]) = cancel_minus(x, [0, 2u]) = [1u, 1u]
  let z = cn_interval(1L, 3L, u, 113).cancel_plus(cn_interval(-2L, 0L, u, 113))
  assert_eq(z.lower_bound().compare(cn_value(1UL, u, false)), 0)
  assert_eq(z.upper_bound().compare(cn_value(1UL, u, false)), 0)
  // the point 0: [3u, 5u] - [3u, 5u] = [0, 0]. The old assertion claimed both ends are +0
  // ("a canonical zero"); that was wrong for the lower end: 12.12.8 requires `inf` to return -0
  // for a Level 1 value of 0 and `sup` +0, so the observers return (-0, +0), the Level 2
  // representative of [0, 0]. The canonical zero is a property of storage, which the
  // observers do not expose.
  let z = cn_interval(3L, 5L, u, 113).cancel_minus(cn_interval(3L, 5L, u, 113))
  assert_true(z.lower_bound().is_zero() && z.lower_bound().is_sign_minus())
  assert_true(z.upper_bound().is_zero() && !z.upper_bound().is_sign_minus())
  assert_true(!z.is_entire())
}

///|
/// The expected result of cancel_minus(x, y) (and of cancel_plus(x, -y)) for x = [a, a + d] * 2^e and
/// y = [b, b + d + delta] * 2^e, by integer algebra on the coefficients. Below the range floor the
/// numbers of a p-bit format lie on the grid of the quantum 2^(e_min - p + 1), a multiple of `unit`
/// units of 2^e; the constructor rounds the lower end of an operand down and the upper end up to that
/// grid (IEEE 1788-2015 12.12.7), so the operands are [floor(a / unit), ceil((a + d) / unit)] * unit and
/// the same for y; the result ends are the exact differences of the operand ends, and the result is
/// Entire when the lower end lies above the upper end (10.5.6).
fn cn_check_integers(
  z : Interval,
  a : Int64,
  b : Int64,
  d : Int64,
  delta : Int64,
  exponent : Int32,
  p : Int32,
) -> Unit {
  let quantum_exponent = @binary.binary_value_e_min - p + 1
  let unit = if exponent < quantum_exponent {
    1L << (quantum_exponent - exponent)
  } else {
    1L
  }
  let floor_unit = fn(c : Int64) { c / unit * unit }
  let ceil_unit = fn(c : Int64) { (c + unit - 1L) / unit * unit }
  let lo = floor_unit(a) - floor_unit(b)
  let hi = ceil_unit(a + d) - ceil_unit(b + d + delta)
  if lo > hi {
    if !z.is_entire() {
      abort(
        "expected Entire: a=\{a} b=\{b} d=\{d} delta=\{delta} e=\{exponent} p=\{p}",
      )
    }
  } else {
    let expected = cn_interval(lo, hi, exponent, p)
    if z.is_entire() ||
      z.lower_bound().compare(expected.lower_bound()) != 0 ||
      z.upper_bound().compare(expected.upper_bound()) != 0 {
      abort(
        "ends differ: a=\{a} b=\{b} d=\{d} delta=\{delta} e=\{exponent} p=\{p} got \{z.lower_bound()} \{z.upper_bound()}",
      )
    }
  }
}

///|
// oracle: A
// source: integer algebra written in cn_check_integers on the coefficients (x = [a, a + d] * 2^e, y = [b, b + d + delta] * 2^e with e just below e_min, 20-bit coefficients): the operand ends are rounded outward to the grid of the quantum 2^(e_min - p + 1) (12.12.7; at 53 bits this is coarser than 2^e for part of the exponents), the result ends are the exact differences of the operand ends, and the result is Entire when the lower end is above the upper end (IEEE 1788-2015 10.5.6, 12.12.5); cancelPlus(x, y) = cancelMinus(x, -y)
// shares: cn_interval and cn_value (Binary::make, Interval::from_bounds), cn_next (the xorshift of the inputs); cancel_plus and cancel_minus are the code under test
test "cancel_plus and cancel_minus decide on the exact values near the bottom of the range" {
  let state = Ref(0x9e3779b97f4a7c15UL)
  let e_min = @binary.binary_value_e_min
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
    let x = cn_interval(a, a + d, exponent, p)
    let y = cn_interval(b, b + d + delta, exponent, p)
    cn_check_integers(x.cancel_minus(y), a, b, d, delta, exponent, p)
    // cancel_plus(x, y) = cancel_minus(x, -y)
    let y_neg = cn_interval(-(b + d + delta), -b, exponent, p)
    cn_check_integers(x.cancel_plus(y_neg), a, b, d, delta, exponent, p)
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
// oracle: A
// source: integer algebra written in the test on the coefficients: x = [a, a + d] * 2^e and y = [b, b + d + delta] * 2^e have the widths d and d + delta, so cancelMinus (IEEE 1788-2015 12.12.5) is [a - b, a - b - delta] * 2^e when delta <= 0 and Entire when width(x) < width(y), that is delta = 1; exponents -100 to 99 and coefficients below 2^20 keep every value exact in 53 bits; the sign of a zero end is checked by the zero sign tests
// shares: cn_interval and cn_value (build a coefficient times 2^e with Binary::make), cn_next (the xorshift of the inputs)
test "away from the bottom of the range cancel_minus is the exact difference of the ends" {
  let state = Ref(0x2545f4914f6cdd1dUL)
  for _ in 0..<3000 {
    let exponent = (cn_next(state) % 200UL).to_int() - 100
    let a = (cn_next(state) % 1000000UL).reinterpret_as_int64() + 1L
    let b = (cn_next(state) % 1000000UL).reinterpret_as_int64() + 1L
    let d = (cn_next(state) % 1000000UL).reinterpret_as_int64() + 2L
    let delta = (cn_next(state) % 3UL).reinterpret_as_int64() - 1L
    let x = cn_interval(a, a + d, exponent, 53)
    let y = cn_interval(b, b + d + delta, exponent, 53)
    let result = x.cancel_minus(y)
    if delta > 0L {
      assert_true(result.is_entire())
    } else {
      let expected = cn_interval(a - b, a - b - delta, exponent, 53)
      assert_eq(result.lower_bound().compare(expected.lower_bound()), 0)
      assert_eq(result.upper_bound().compare(expected.upper_bound()), 0)
    }
  }
}

///|
// oracle: A
// source: IEEE 1788-2015 10.5.6 and 12.12.5: x empty with y bounded gives Empty; y empty with x nonempty, an unbounded operand, or both empty and unbounded, have no Level 1 value and are Entire at Level 2; written out
// shares: cn_interval, cn_value (Binary::make), Interval::empty, entire, from_bounds and Binary::inf build the inputs; cancel_plus and cancel_minus are the code under test
test "cancel_plus and cancel_minus: the special cases of IEEE 1788-2015 12.12.5" {
  let bounded = cn_interval(1L, 3L, 0, 53)
  let empty = Interval::empty(precision=53)
  let unbounded = Interval::entire(precision=53)
  let half_bounded = Interval::from_bounds(
    cn_value(1UL, 0, false),
    @binary.Binary::inf(precision=53),
    precision=53,
  )
  for plus in [false, true] {
    let op = fn(x : Interval, y : Interval) {
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
