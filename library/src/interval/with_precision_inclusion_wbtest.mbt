///|
fn with_precision_power(exponent : Int32, precision : Int32) -> @binary.Binary {
  @binary.Binary::make(@binary.BinCoeff::one(), exponent, precision)
}

///|
/// `Interval::with_precision` rebuilt a bounded interval from `center()` and
/// `radius()`. The center adds the endpoints in round-to-nearest mode, which
/// replaced an addend far below the larger one
/// with a sticky surrogate (of the exact route that the directed sums replaced), while the radius drops that addend. Once the new
/// precision stored the surrogate exactly, `center - radius` landed above the
/// original lower endpoint and the result lost it.
test "Interval::with_precision keeps a far lower endpoint" {
  let lo = with_precision_power(-200000, 53)
  let hi = @binary.Binary::one(precision=53)
  let x = Interval::from_bounds(lo, hi, precision=53)
  assert_true(x.is_member(lo))
  let y = x.with_precision(70000)
  assert_true(y.is_member(lo))
  assert_true(y.is_member(hi))
  assert_eq(y.lower_bound().exponent2(), -200000)
}

///|
/// The margin is 65536 bits, so only a target precision wide enough to store
/// the surrogate exposed the bug; cover both sides of it.
test "Interval::with_precision encloses across the far addend margin" {
  let hi = @binary.Binary::one(precision=53)
  for gap in [65535, 65540, 70003, 200000, 1000000] {
    let lo = with_precision_power(-gap, 53)
    for pair in [(lo, hi), (lo.neg(), hi), (hi.neg(), lo), (hi.neg(), lo.neg())] {
      let (low, high) = pair
      let x = Interval::from_bounds(low, high, precision=53)
      for precision in [1, 8, 53, 65535, 65536, 65539, 70000, 131072] {
        let y = x.with_precision(precision)
        assert_true(y.is_member(x.lower_bound()))
        assert_true(y.is_member(x.upper_bound()))
        assert_eq(y.precision(), Int32::max(1, precision))
      }
    }
  }
}

///|
/// Widening a wide interval must be exact: the endpoints already fit, so the
/// result has to be the same set, not a center-and-radius reconstruction.
test "Interval::with_precision widening keeps a wide interval exact" {
  let lo = with_precision_power(-200000, 53)
  let hi = @binary.Binary::one(precision=53)
  let x = Interval::from_bounds(lo, hi, precision=53)
  for precision in [65539, 70000, 200001] {
    let y = x.with_precision(precision)
    assert_eq(y.lower_bound().compare(lo), 0)
    assert_eq(y.upper_bound().compare(hi), 0)
  }
}

///|
// oracle: A
// source: end values written out, computed with Python integers and fractions (round the lower end down and the upper end up to p significant bits): 1 + 2^-52 rounds up to 1 + 2^-7, 1 + 2^-15, 1 + 2^-23 at p = 8, 16, 24 and is exact at 53 and 113 bits; 100001 (17 bits) rounds down to 99840 at 8 bits and 100000 at 16 bits and is exact from 24 bits; powers of two are exact at every precision (two intervals: [1,2], [-1/8,1/8], [2^-60,2^70]); rows are (lo, hi, p, expected lo, expected hi)
// shares: Interval::from_bounds, Binary::from_double and Interval::equal (building and comparing only)
test "Interval::with_precision does not widen ordinary intervals" {
  let rows : Array[(Double, Double, Int32, Double, Double)] = [
    (1.0, 2.0, 8, 1.0, 2.0),
    (1.0, 2.0, 113, 1.0, 2.0),
    (1.0, 1.0000000000000002, 8, 1.0, 1.0078125),
    (1.0, 1.0000000000000002, 16, 1.0, 1.000030517578125),
    (1.0, 1.0000000000000002, 24, 1.0, 1.0000001192092896),
    (1.0, 1.0000000000000002, 53, 1.0, 1.0000000000000002),
    (1.0, 1.0000000000000002, 113, 1.0, 1.0000000000000002),
    (-0.125, 0.125, 8, -0.125, 0.125),
    (-0.125, 0.125, 113, -0.125, 0.125),
    (
      8.673617379884035e-19, 1.1805916207174113e+21, 8, 8.673617379884035e-19, 1.1805916207174113e+21,
    ),
    (
      8.673617379884035e-19, 1.1805916207174113e+21, 113, 8.673617379884035e-19,
      1.1805916207174113e+21,
    ),
    (100001.0, 1048576.0, 8, 99840.0, 1048576.0),
    (100001.0, 1048576.0, 16, 100000.0, 1048576.0),
    (100001.0, 1048576.0, 24, 100001.0, 1048576.0),
    (100001.0, 1048576.0, 53, 100001.0, 1048576.0),
  ]
  for row in rows {
    let (lo, hi, precision, expected_lo, expected_hi) = row
    let x = Interval::from_bounds(
      @binary.Binary::from_double(lo),
      @binary.Binary::from_double(hi),
      precision=53,
    )
    let tightest = Interval::from_bounds(
      @binary.Binary::from_double(expected_lo, precision~),
      @binary.Binary::from_double(expected_hi, precision~),
      precision~,
    )
    assert_true(x.with_precision(precision).equal(tightest))
  }
}

///|
/// Re-quantizing at the interval's own precision is the identity, and empty and
/// unbounded intervals keep their shape.
test "Interval::with_precision keeps degenerate intervals" {
  let x = Interval::from_bounds(
    with_precision_power(-3, 53),
    with_precision_power(2, 53),
    precision=53,
  )
  assert_true(x.with_precision(53).equal(x))
  assert_true(Interval::empty(precision=53).with_precision(70000).is_empty())
  assert_true(Interval::entire(precision=53).with_precision(70000).is_entire())
}
