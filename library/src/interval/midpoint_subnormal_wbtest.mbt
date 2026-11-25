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
