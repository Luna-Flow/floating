///|
fn with_precision_power(exponent : Int, precision : Int) -> @bin_float.BinFloat {
  @bin_float.BinFloat::make(@bin_float.BinCoeff::one(), exponent, precision)
}

///|
/// Every rounding mode an interval can be re-quantized with.
let with_precision_modes : Array[RoundingMode] = [
  RoundingMode::ToNearestEven,
  RoundingMode::TowardPositive,
  RoundingMode::TowardNegative,
  RoundingMode::TowardZero,
  RoundingMode::AwayFromZero,
]

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
  assert_true(x.contains(lo))
  let y = x.with_precision(70000, RoundingMode::ToNearestEven)
  assert_true(y.contains(lo))
  assert_true(y.contains(hi))
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
        for mode in with_precision_modes {
          let y = x.with_precision(precision, mode)
          assert_true(y.contains(x.lower_bound()))
          assert_true(y.contains(x.upper_bound()))
          assert_eq(y.precision(), Int::max(1, precision))
        }
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
    let y = x.with_precision(precision, RoundingMode::ToNearestEven)
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
      for mode in with_precision_modes {
        let y = x.with_precision(precision, mode)
        let tightest = BallFloat::from_bounds(
          x
          .lower_bound()
          .with_precision(precision, RoundingMode::TowardNegative),
          x
          .upper_bound()
          .with_precision(precision, RoundingMode::TowardPositive),
          precision~,
        )
        assert_true(y.set_equal(tightest))
      }
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
  for mode in with_precision_modes {
    assert_true(x.with_precision(53, mode).set_equal(x))
    assert_true(
      BallFloat::empty(precision=53).with_precision(70000, mode).is_empty(),
    )
    assert_true(
      BallFloat::whole(precision=53).with_precision(70000, mode).is_entire(),
    )
  }
}
