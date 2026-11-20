///|
fn with_precision_power(
  exponent : Int32,
  precision : Int32,
) -> @bin_float.BinFloat {
  @bin_float.BinFloat::make(@bin_float.BinCoeff::one(), exponent, precision)
}

///|
/// `BallFloat::with_precision` rebuilt a bounded interval from `center()` and
/// `radius()`. The center adds the endpoints in round-to-nearest mode, which
/// replaces an addend more than `far_addend_margin` bits below the larger one
/// with a sticky surrogate, while the radius drops that addend. Once the new
/// precision stored the surrogate exactly, `center - radius` landed above the
/// original lower endpoint and the result lost it.
test "BallFloat::with_precision keeps a far lower endpoint" {
  let lo = with_precision_power(-200000, 53)
  let hi = @bin_float.BinFloat::one(precision=53)
  let x = BallFloat::from_bounds(lo, hi, precision=53)
  assert_true(x.is_member(lo))
  let y = x.with_precision(70000)
  assert_true(y.is_member(lo))
  assert_true(y.is_member(hi))
  assert_eq(y.lower_bound().exponent2(), -200000)
}

///|
/// The margin is 65536 bits, so only a target precision wide enough to store
/// the surrogate exposed the bug; cover both sides of it.
test "BallFloat::with_precision encloses across the far addend margin" {
  let hi = @bin_float.BinFloat::one(precision=53)
  for gap in [65535, 65540, 70003, 200000, 1000000] {
    let lo = with_precision_power(-gap, 53)
    for pair in [(lo, hi), (lo.neg(), hi), (hi.neg(), lo), (hi.neg(), lo.neg())] {
      let (low, high) = pair
      let x = BallFloat::from_bounds(low, high, precision=53)
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
test "BallFloat::with_precision widening keeps a wide interval exact" {
  let lo = with_precision_power(-200000, 53)
  let hi = @bin_float.BinFloat::one(precision=53)
  let x = BallFloat::from_bounds(lo, hi, precision=53)
  for precision in [65539, 70000, 200001] {
    let y = x.with_precision(precision)
    assert_eq(y.lower_bound().compare(lo), 0)
    assert_eq(y.upper_bound().compare(hi), 0)
  }
}

///|
/// Ordinary intervals at ordinary precisions must not grow: the result is the
/// tightest representable enclosure, the endpoints rounded outward one by one.
test "BallFloat::with_precision does not widen ordinary intervals" {
  let candidates = [
    (with_precision_power(0, 53), with_precision_power(1, 53)),
    (
      @bin_float.BinFloat::one(precision=53),
      @bin_float.BinFloat::make(
        @bin_float.BinCoeff::from_uint64((1UL << 52) + 1UL),
        -52,
        53,
      ),
    ),
    (with_precision_power(-3, 53).neg(), with_precision_power(-3, 53)),
    (with_precision_power(-60, 24), with_precision_power(70, 24)),
    (
      BallFloat::from_int(100001, precision=53).lower_bound(),
      with_precision_power(20, 53),
    ),
  ]
  for pair in candidates {
    let (lo, hi) = pair
    let x = BallFloat::from_bounds(lo, hi, precision=53)
    for precision in [8, 16, 24, 53, 113] {
      let y = x.with_precision(precision)
      let tightest = BallFloat::from_bounds(
        x
        .lower_bound()
        .with_precision(
          precision,
          @bin_float.BinaryRoundingMode::RoundTowardNegative,
        ),
        x
        .upper_bound()
        .with_precision(
          precision,
          @bin_float.BinaryRoundingMode::RoundTowardPositive,
        ),
        precision~,
      )
      assert_true(y.equal(tightest))
    }
  }
}

///|
/// Re-quantizing at the interval's own precision is the identity, and empty and
/// unbounded intervals keep their shape.
test "BallFloat::with_precision keeps degenerate intervals" {
  let x = BallFloat::from_bounds(
    with_precision_power(-3, 53),
    with_precision_power(2, 53),
    precision=53,
  )
  assert_true(x.with_precision(53).equal(x))
  assert_true(BallFloat::empty(precision=53).with_precision(70000).is_empty())
  assert_true(BallFloat::entire(precision=53).with_precision(70000).is_entire())
}
