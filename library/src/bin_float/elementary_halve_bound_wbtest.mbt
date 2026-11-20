///|
test "halving the bounds of pi by the exponent equals the product by 1/2" {
  for work in [64, 65, 100, 128, 150, 192, 225, 609, 1536, 4160] {
    let pi = binary_pi_bounds(work).unwrap()
    let downward = binary_working_context(work, rounding=RoundTowardNegative)
    let upward = binary_working_context(work, rounding=RoundTowardPositive)
    let half = BinFloat::make_coeff(Coeff::one(), -1, work)
    let reference_low = pi.0.mul_ctx(half, downward).0
    let reference_high = pi.1.mul_ctx(half, upward).0
    let low = binary_halve_bound(pi.0, work, downward)
    let high = binary_halve_bound(pi.1, work, upward)
    assert_eq(low.compare(reference_low), 0)
    assert_eq(high.compare(reference_high), 0)
    assert_eq(low.precision(), reference_low.precision())
    assert_eq(high.precision(), reference_high.precision())
    assert_eq(low.exponent2(), reference_low.exponent2())
    assert_eq(low.coefficient_(), reference_low.coefficient_())
    // the quarter by the same function
    let quarter_low = binary_halve_bound(low, work, downward)
    let quarter_reference = reference_low.mul_ctx(half, downward).0
    assert_eq(quarter_low.compare(quarter_reference), 0)
    assert_eq(quarter_low.precision(), quarter_reference.precision())
  }
}

///|
test "halving falls back to the product off the exact case" {
  let work = 192
  let downward = binary_working_context(work, rounding=RoundTowardNegative)
  let half = BinFloat::make_coeff(Coeff::one(), -1, work)
  // a value of another precision, a value near the bottom of the exponent range,
  // zero: all through the product
  let values = [
    BinFloat::from_int(3, precision=53),
    BinFloat::make_coeff(Coeff::from_uint64(5UL), -1073741820, work),
    BinFloat::zero(precision=work),
  ]
  for value in values {
    let a = binary_halve_bound(value, work, downward)
    let b = value.mul_ctx(half, downward).0
    assert_eq(a.compare(b), 0)
    assert_eq(a.precision(), b.precision())
  }
}

///|
/// `binary_trigonometric_bounds_series` as it was before `pi / 2` and `pi / 4` were
/// halved by the exponent (four directed products by 1/2), kept as the reference
/// of the test and of the same-executable measurement.
fn binary_trigonometric_bounds_series_reference(
  value : BinFloat,
  operation : BinaryTrigonometricOperation,
  work_precision : Int32,
) -> (BinFloat, BinFloat)? {
  let pi = binary_pi_bounds(work_precision).unwrap()
  let downward = binary_working_context(
    work_precision,
    rounding=RoundTowardNegative,
  )
  let upward = binary_working_context(
    work_precision,
    rounding=RoundTowardPositive,
  )
  let half_pi = (
    pi.0.mul_ctx(
      BinFloat::make_coeff(Coeff::one(), -1, work_precision),
      downward,
    ).0,
    pi.1.mul_ctx(BinFloat::make_coeff(Coeff::one(), -1, work_precision), upward).0,
  )
  let quarter_pi = (
    half_pi.0.mul_ctx(
      BinFloat::make_coeff(Coeff::one(), -1, work_precision),
      downward,
    ).0,
    half_pi.1.mul_ctx(
      BinFloat::make_coeff(Coeff::one(), -1, work_precision),
      upward,
    ).0,
  )
  let reduction = binary_trigonometric_reduction(value, half_pi, work_precision)
  guard reduction is Some(((lower, upper), quadrant)) else { return None }
  guard lower.compare(quarter_pi.0.neg()) >= 0 &&
    upper.compare(quarter_pi.1) <= 0 else {
    return None
  }
  // The reduction needed `work_precision` bits for the cancellation of a huge
  // argument (its top bound is `top`); the reduced argument lies in
  // (-pi/4, pi/4) and the series needs only the precision of the result:
  // `work_precision - top`. The enclosure is rounded outward to it first.
  let top = binary_top_bound(value)
  let series_precision = if top > 256L {
    Int32::max(64, work_precision - top.to_int())
  } else {
    work_precision
  }
  if series_precision >= work_precision {
    return binary_reduced_trigonometric_bounds(
      lower, upper, quadrant, operation, work_precision,
    )
  }
  binary_reduced_trigonometric_bounds(
    lower.with_precision_raw(
      series_precision,
      BinaryRoundingMode::RoundTowardNegative,
    ),
    upper.with_precision_raw(
      series_precision,
      BinaryRoundingMode::RoundTowardPositive,
    ),
    quadrant,
    operation,
    series_precision,
  )
}

///|
test "series path with exact halves equals the series path with products" {
  let mut seed = 31UL
  for p in [53, 64, 128, 200, 512] {
    for top in [-3, -1, 0, 1, 2, 5, 40] {
      for
        operation in [
          BinaryTrigonometricOperation::Sin,
          BinaryTrigonometricOperation::Cos,
          BinaryTrigonometricOperation::Tan,
        ] {
        seed += 1UL
        let value = burst_test_value(p, top, seed % 2UL == 0UL, seed)
        let work = p + Int32::max(0, top) + 96
        let a = binary_trigonometric_bounds_series(value, operation, work)
        let b = binary_trigonometric_bounds_series_reference(
          value, operation, work,
        )
        match (a, b) {
          (Some(x), Some(y)) => {
            assert_eq(x.0.compare(y.0), 0)
            assert_eq(x.1.compare(y.1), 0)
          }
          (None, None) => ()
          _ => fail("paths disagree")
        }
      }
    }
  }
}
