// `Interval::midpoint` is the exact midpoint (lo + hi) / 2 rounded once to
// nearest at the precision (IEEE 1788-2015 12.12.8, Table 9.2). The exact center
// was made at its own bit length in the nearest mode, so below the normal range
// the sum of a few-bit endpoints rounded to the quantum of those few bits: a
// midpoint of 0 for `[1, 3] * 2^(e_min - 60)` (issue #578).

///|
fn mid_next(state : Ref[UInt64]) -> UInt64 {
  let mut x = state.val
  x = x ^ (x << 13)
  x = x ^ (x >> 7)
  x = x ^ (x << 17)
  state.val = x
  x
}

///|
fn mid_value(
  coefficient : UInt64,
  exponent : Int32,
  precision : Int32,
) -> @binary.Binary {
  @binary.Binary::make(
    @binary.BinCoeff::from_uint64(coefficient),
    exponent,
    precision,
  )
}

///|
/// The independent oracle: the sum in a context of 600 bits (exact for the
/// operands used here), halved by a product with 1/2 (exact), rounded once to
/// `precision` bits by `with_precision` (nearest, ties to even, onto the grid of
/// the stored range).
fn mid_oracle(
  lo : @binary.Binary,
  hi : @binary.Binary,
  precision : Int32,
) -> @binary.Binary {
  let wide = @binary.BinaryContext::new(precision=600)
  let sum = lo.add_ctx(hi, wide).0
  let half = @binary.Binary::make(@binary.BinCoeff::one(), -1, 1)
  sum.mul_ctx(half, wide).0.with_precision(
    precision,
    @binary.BinaryRoundingMode::RoundTiesToEven,
  )
}

///|
test "the midpoint of intervals at the bottom of the range is not zero" {
  let e_min = @binary.binary_value_e_min
  let mut cases = 0
  for shift in [60, 45, 40, 30, 10, 3] {
    for pair in [(1, 3), (1, 5), (3, 5), (5, 7), (1, 7), (7, 9), (9, 15)] {
      let (x, y) = pair
      for p in [24, 53, 113] {
        let lo = mid_value(x.to_uint64(), e_min - shift, 200)
        let hi = mid_value(y.to_uint64(), e_min - shift, 200)
        let interval = Interval::from_bounds(lo, hi, precision=p)
        let m = interval.midpoint()
        // the endpoints of the interval are the ones rounded outward to p bits
        let expected = mid_oracle(
          interval.lower_bound(),
          interval.upper_bound(),
          p,
        )
        assert_identical(m, expected)
        assert_true(interval.is_member(m))
        // endpoints that p bits hold exactly: the midpoint is (x + y) / 2 * 2^(e_min - shift)
        if shift <= p - 1 {
          assert_identical(
            m,
            mid_value(((x + y) / 2).to_uint64(), e_min - shift, p),
          )
        }
        cases += 1
      }
    }
  }
  assert_eq(cases, 126)
  // printed values
  let interval = Interval::from_bounds(
    mid_value(1UL, e_min - 60, 200),
    mid_value(3UL, e_min - 60, 200),
    precision=113,
  )
  inspect(interval.midpoint().to_string(), content="1p-1073741881")
  // `radius` and `width` are bounds (their smallest values are tracked in #579)
  let radius = interval.radius()
  assert_true(radius.compare(mid_value(1UL, e_min - 60, 200)) >= 0)
  let (m, flags) = interval.midpoint_ctx(
    IntervalContext::new(precision=113, e_max=@binary.binary_value_e_max),
  )
  inspect(m.to_string(), content="1p-1073741881")
  inspect(flags.inexact(), content="false")
  assert_eq(
    interval_center(interval, interval.precision()).compare(
      mid_value(1UL, e_min - 59, 200),
    ),
    0,
  )
}

///|
test "the midpoint of a seeded class near the bottom of the range is the correctly rounded midpoint" {
  let state = Ref(0x9e3779b97f4a7c15UL)
  let e_min = @binary.binary_value_e_min
  let precisions = [24, 53, 113, 128]
  let mut checked = 0
  for _ in 0..<3000 {
    let bits_x = 1 + (mid_next(state) % 60UL).to_int()
    let bits_y = 1 + (mid_next(state) % 60UL).to_int()
    let x = (mid_next(state) % (1UL << bits_x)) | 1UL
    let y = (mid_next(state) % (1UL << bits_y)) | 1UL
    let a = mid_value(x, e_min - 70 + (mid_next(state) % 90UL).to_int(), 200)
    let b = mid_value(y, e_min - 70 + (mid_next(state) % 90UL).to_int(), 200)
    let (lo, hi) = if a.compare(b) <= 0 { (a, b) } else { (b, a) }
    let precision = precisions[(mid_next(state) % 4UL).to_int()]
    let interval = Interval::from_bounds(lo, hi, precision~)
    let m = interval.midpoint()
    assert_identical(
      m,
      mid_oracle(interval.lower_bound(), interval.upper_bound(), precision),
    )
    assert_true(interval.is_member(m))
    checked += 1
  }
  assert_eq(checked, 3000)
}

///|
// oracle: B
// source: the sum of the bounds in a context of 600 bits (exact for these operands) times 1/2 (exact)
// shares: `Binary::add_ctx` and `mul_ctx` at precision 600 (level A in the binary gate)
// primitives: add_ctx, mul_ctx
test "far from the edges the center is the exact center" {
  // the value of the exact center equals the sum in 600 bits (exact) times 1/2
  let state = Ref(0x2545f4914f6cdd1dUL)
  for _ in 0..<3000 {
    let x = mid_next(state) % 1000000UL + 1UL
    let y = mid_next(state) % 1000000UL + 1UL
    let a = mid_value(x, (mid_next(state) % 400UL).to_int() - 200, 53)
    let b = mid_value(y, (mid_next(state) % 400UL).to_int() - 200, 53)
    let (lo, hi) = if a.compare(b) <= 0 { (a, b) } else { (b, a) }
    let interval = Interval::from_bounds(lo, hi, precision=53)
    let wide = @binary.BinaryContext::new(precision=600)
    let half = @binary.Binary::make(@binary.BinCoeff::one(), -1, 1)
    let exact = interval.lower_bound().add_ctx(interval.upper_bound(), wide).0.mul_ctx(
        half, wide,
      ).0
    assert_eq(interval_center(interval, interval.precision()).compare(exact), 0)
    assert_identical(
      interval.midpoint(),
      mid_oracle(interval.lower_bound(), interval.upper_bound(), 53),
    )
  }
}

///|
test "a zero endpoint with the smallest stored value" {
  let e_min = @binary.binary_value_e_min
  let zero = @binary.Binary::zero(precision=53)
  // the smallest stored value of 53 bits is 2^(e_min - 52); half of it lies
  // between 0 and it, a tie: the even neighbour is 0
  let smallest = mid_value(1UL, e_min - 52, 53)
  let interval = Interval::from_bounds(zero, smallest, precision=53)
  assert_true(interval.midpoint().is_zero())
  assert_true(interval.is_member(interval.midpoint()))
  inspect(
    interval_center(interval, interval.precision()).to_string(),
    content="1p-1073741875",
  )
  // three times the smallest: 1.5 * smallest, a tie between 1 and 2 times it,
  // the even one is 2 * smallest = 1p-1073741873
  let interval = Interval::from_bounds(
    zero,
    mid_value(3UL, e_min - 52, 53),
    precision=53,
  )
  inspect(interval.midpoint().to_string(), content="1p-1073741873")
}

///|
/// The datum built for the sum is `lo + hi` exactly: the sums of 1 to 6 odd
/// coefficients of several bits at the bottom of the range, against a sum made
/// in a context of 600 bits (exact).
test "the exact center datum equals lo + hi and its half" {
  let state = Ref(0x5851f42d4c957f2dUL)
  let e_min = @binary.binary_value_e_min
  let wide = @binary.BinaryContext::new(precision=600)
  let half = @binary.Binary::make(@binary.BinCoeff::one(), -1, 1)
  let mut multi_bit = 0
  for _ in 0..<3000 {
    let bits_x = 1 + (mid_next(state) % 40UL).to_int()
    let bits_y = 1 + (mid_next(state) % 40UL).to_int()
    let x = (mid_next(state) % (1UL << bits_x)) | 1UL
    let y = (mid_next(state) % (1UL << bits_y)) | 1UL
    let a = mid_value(x, e_min - 60 + (mid_next(state) % 70UL).to_int(), 200)
    let b = mid_value(y, e_min - 60 + (mid_next(state) % 70UL).to_int(), 200)
    let sum = exact_add_full(a, b)
    let reference = a.add_ctx(b, wide).0
    assert_eq(sum.compare(reference), 0)
    let halved = halve(sum)
    assert_eq(halved.compare(reference.mul_ctx(half, wide).0), 0)
    if sum.coefficient().bit_length() >= 3 {
      multi_bit += 1
    }
  }
  assert_true(multi_bit > 1000)
}

///|
/// An operand at `binary_precision_max` bits whose lowest bit is the lowest
/// representable one (`2^(e_min - max + 1)`) and an operand with a higher lowest
/// bit: the sum has the lowest bit of the first, its half needs `max + 1` bits
/// and the datum is made at `max` bits (the clamp of `exact_value`): the half is
/// rounded to nearest at `max` bits, which is the rounding `midpoint` makes at
/// the same precision.
test "the center at the precision limit is rounded once at the limit" {
  let e_min = @binary.binary_value_e_min
  let max = @binary.binary_precision_max
  let lowest = e_min - max + 1
  let lo = mid_value(1UL, lowest, max)
  let hi = mid_value(1UL, lowest + 1, max)
  // lo + hi = 3 * 2^lowest, half = 1.5 * 2^lowest: a tie between 2^lowest and
  // 2 * 2^lowest, the even neighbour is 2 * 2^lowest
  let interval = Interval::from_bounds(lo, hi, precision=max)
  assert_eq(interval.midpoint().compare(mid_value(1UL, lowest + 1, max)), 0)
  assert_true(interval.is_member(interval.midpoint()))
}

///|
/// `Interval::from_midpoint_radius`: the endpoints `c - R` and `c + R` are made by directed sums
/// that are not rounded to the precision. Away from the bottom of the range they
/// are exact, so the midpoint is the center the interval was made from; at the
/// bottom they are directed-rounded at their own bit length (looser than
/// necessary: #579) and the midpoint is a member of the interval but not always `c`.
test "the midpoint of an interval made from a center is a member" {
  let state = Ref(0x2545f4914f6cdd1dUL)
  let e_min = @binary.binary_value_e_min
  for _ in 0..<500 {
    let bits = 1 + (mid_next(state) % 60UL).to_int()
    let x = (mid_next(state) % (1UL << bits)) | 1UL
    let r = mid_next(state) % 1000UL + 1UL
    // away from the bottom: the center itself
    let c = mid_value(x, (mid_next(state) % 200UL).to_int() - 100, 53)
    let interval = Interval::from_midpoint_radius(
      c,
      mid_value(r, -150, 53),
      precision=53,
    )
    assert_eq(
      interval
      .midpoint()
      .compare(
        c.with_precision(53, @binary.BinaryRoundingMode::RoundTiesToEven),
      ),
      0,
    )
    assert_true(interval.is_member(interval.midpoint()))
    // at the bottom: a member
    let c = mid_value(x, e_min - 40 + (mid_next(state) % 80UL).to_int(), 53)
    let low = mid_value(r, e_min - 70 + (mid_next(state) % 80UL).to_int(), 53)
    let interval = Interval::from_midpoint_radius(c, low, precision=53)
    assert_true(interval.is_member(interval.midpoint()))
  }
}
