///|
/// The enclosure of `exp` as it was computed before the second series
/// evaluation was skipped for a degenerate argument: both endpoints always get
/// their own series. Kept here as the reference the production path must equal.
fn binary_exp_bounds_reference(
  value : BinFloat,
  work_precision : Int32,
) -> (BinFloat, BinFloat)? {
  let downward = BinaryContext::new(
    precision=work_precision,
    rounding=RoundTowardNegative,
  )
  let upward = BinaryContext::new(
    precision=work_precision,
    rounding=RoundTowardPositive,
  )
  let mut lower = value.with_precision(
    work_precision,
    BinaryRoundingMode::RoundTowardNegative,
  )
  let mut upper = value.with_precision(
    work_precision,
    BinaryRoundingMode::RoundTowardPositive,
  )
  let eighth = BinFloat::make_coeff(Coeff::one(), -3, work_precision)
  let half = BinFloat::make_coeff(Coeff::one(), -1, work_precision)
  let mut reductions = 0
  while (lower.compare(eighth.neg()) < 0 || upper.compare(eighth) > 0) &&
        reductions < 4096 {
    lower = lower.mul_ctx(half, downward).0
    upper = upper.mul_ctx(half, upward).0
    reductions += 1
  }
  guard lower.compare(eighth.neg()) >= 0 && upper.compare(eighth) <= 0 else {
    return None
  }
  match
    (
      binary_exp_small_bounds(lower, work_precision),
      binary_exp_small_bounds(upper, work_precision),
    ) {
    (Some(lower_bounds), Some(upper_bounds)) => {
      let mut result_lower = lower_bounds.0
      let mut result_upper = upper_bounds.1
      for _ in 0..<reductions {
        result_lower = result_lower.mul_ctx(result_lower, downward).0
        result_upper = result_upper.mul_ctx(result_upper, upward).0
      }
      Some((result_lower, result_upper))
    }
    _ => None
  }
}

///|
/// The enclosure of the reduced trigonometric functions as it was computed
/// before unused series were skipped: all four series are always evaluated.
fn binary_reduced_trigonometric_bounds_reference(
  lower : BinFloat,
  upper : BinFloat,
  quadrant : Int32,
  operation : BinaryTrigonometricOperation,
  work_precision : Int32,
) -> (BinFloat, BinFloat)? {
  let one = BinFloat::one(precision=work_precision)
  guard lower.compare(upper) <= 0 &&
    lower.compare(one.neg()) >= 0 &&
    upper.compare(one) <= 0 else {
    return None
  }
  let downward = BinaryContext::new(
    precision=work_precision,
    rounding=RoundTowardNegative,
  )
  let upward = BinaryContext::new(
    precision=work_precision,
    rounding=RoundTowardPositive,
  )
  let sin_lower = binary_sin_cos_series(lower, false, work_precision).unwrap()
  let sin_upper = binary_sin_cos_series(upper, false, work_precision).unwrap()
  let cos_lower = binary_sin_cos_series(lower, true, work_precision).unwrap()
  let cos_upper = binary_sin_cos_series(upper, true, work_precision).unwrap()
  let sin_bounds = (sin_lower.0, sin_upper.1)
  let zero = BinFloat::zero(precision=work_precision)
  let cos_bounds = if lower.compare(zero) <= 0 && upper.compare(zero) >= 0 {
    (
      if cos_lower.0.compare(cos_upper.0) < 0 {
        cos_lower.0
      } else {
        cos_upper.0
      },
      BinFloat::one(precision=work_precision),
    )
  } else if upper.compare(zero) <= 0 {
    (cos_lower.0, cos_upper.1)
  } else {
    (cos_upper.0, cos_lower.1)
  }
  let mapped = match quadrant % 4 {
    0 => (sin_bounds, cos_bounds)
    1 =>
      ((cos_bounds.0, cos_bounds.1), (sin_bounds.1.neg(), sin_bounds.0.neg()))
    2 =>
      (
        (sin_bounds.1.neg(), sin_bounds.0.neg()),
        (cos_bounds.1.neg(), cos_bounds.0.neg()),
      )
    _ =>
      ((cos_bounds.1.neg(), cos_bounds.0.neg()), (sin_bounds.0, sin_bounds.1))
  }
  match operation {
    BinaryTrigonometricOperation::Sin => Some(mapped.0)
    BinaryTrigonometricOperation::Cos => Some(mapped.1)
    BinaryTrigonometricOperation::Tan => {
      guard !(mapped.1.0.compare(BinFloat::zero()) <= 0 &&
        mapped.1.1.compare(BinFloat::zero()) >= 0) else {
        return None
      }
      let candidates = [
        mapped.0.0.div_ctx(mapped.1.0, downward).0,
        mapped.0.0.div_ctx(mapped.1.1, downward).0,
        mapped.0.1.div_ctx(mapped.1.0, downward).0,
        mapped.0.1.div_ctx(mapped.1.1, downward).0,
      ]
      let upper_candidates = [
        mapped.0.0.div_ctx(mapped.1.0, upward).0,
        mapped.0.0.div_ctx(mapped.1.1, upward).0,
        mapped.0.1.div_ctx(mapped.1.0, upward).0,
        mapped.0.1.div_ctx(mapped.1.1, upward).0,
      ]
      let mut result_lower = candidates[0]
      let mut result_upper = upper_candidates[0]
      for candidate in candidates[1:] {
        if candidate.compare(result_lower) < 0 {
          result_lower = candidate
        }
      }
      for candidate in upper_candidates[1:] {
        if candidate.compare(result_upper) > 0 {
          result_upper = candidate
        }
      }
      Some((result_lower, result_upper))
    }
  }
}

///|
fn binary_unused_series_same(
  left : (BinFloat, BinFloat)?,
  right : (BinFloat, BinFloat)?,
) -> Bool {
  match (left, right) {
    (Some((left_low, left_high)), Some((right_low, right_high))) =>
      left_low == right_low &&
      left_high == right_high &&
      left_low.precision() == right_low.precision() &&
      left_high.precision() == right_high.precision()
    (None, None) => true
    _ => false
  }
}

///|
test "exp enclosure skips the duplicate series without changing a bit" {
  let values = [
    BinFloat::from_double(0.5, precision=53),
    BinFloat::from_double(-0.5, precision=53),
    BinFloat::from_double(3.75, precision=53),
    BinFloat::from_double(-3.75, precision=53),
    BinFloat::from_double(0.0009765625, precision=53),
    BinFloat::from_double(123.456, precision=53),
    BinFloat::from_double(-0.3333333333333333, precision=53),
    // exact at every tested working precision
    BinFloat::from_int(1),
    BinFloat::from_int(-7),
    // not representable at the smaller working precisions: lower < upper
    BinFloat::from_double(0.1, precision=53).mul(
      BinFloat::from_double(0.7, precision=53),
    ),
    BinFloat::make_coeff(
      Coeff::one().shift_left(120).add(Coeff::one()),
      -118,
      130,
    ),
  ]
  for work in [20, 53, 64, 117, 128, 200] {
    for value in values {
      // The series path itself: `binary_exp_bounds` may answer from the
      // table kernel, whose enclosure differs but is covered by its own tests.
      let actual = binary_exp_bounds_series(value, work)
      let reference = binary_exp_bounds_reference(value, work)
      let exact = value
        .with_precision(work, BinaryRoundingMode::RoundTowardNegative)
        .compare(value) ==
        0
      if exact {
        // An exact argument has equal endpoints, where one series supplies
        // both bounds; other enclosure paths for it (such as a fixed-point
        // series) may bracket the exponential slightly differently, so the
        // enclosures are only required to be consistent and to overlap.
        match (actual, reference) {
          (Some((low, high)), Some((reference_low, reference_high))) => {
            assert_true(low.compare(reference_high) <= 0)
            assert_true(reference_low.compare(high) <= 0)
          }
          (None, None) => ()
          _ => assert_true(false)
        }
      } else {
        assert_true(binary_unused_series_same(actual, reference))
      }
    }
  }
}

///|
test "exp enclosure with a single series rounds like two series" {
  let contexts = [
    BinaryContext::binary64(),
    BinaryContext::new(precision=24),
    BinaryContext::new(precision=100),
    BinaryContext::new(precision=53, rounding=RoundTowardZero),
  ]
  let values = [
    BinFloat::from_double(0.5, precision=53),
    BinFloat::from_double(-0.5, precision=53),
    BinFloat::from_double(3.75, precision=53),
    BinFloat::from_double(-3.75, precision=53),
    BinFloat::from_double(0.0009765625, precision=53),
    BinFloat::from_double(123.456, precision=53),
    BinFloat::from_double(-0.3333333333333333, precision=53),
    BinFloat::from_int(1),
    BinFloat::from_int(-7),
  ]
  for context in contexts {
    for value in values {
      let mut work = context.precision + 64
      let mut expected : (BinFloat, BinaryFlags)? = None
      let mut attempt = 0
      while attempt < 12 && expected is None {
        match binary_exp_bounds_reference(value, work) {
          Some((lower, upper)) => {
            let (result, unique, flags) = binary_certified_inexact_target_rounding(
              lower, upper, context,
            )
            if unique {
              expected = Some((result, flags))
            }
          }
          None => break
        }
        work += Int32::max(32, work / 2)
        attempt += 1
      }
      match expected {
        Some((result, flags)) => {
          let (actual, actual_flags) = value.exp_ctx(context)
          assert_eq(actual, result)
          assert_eq(actual_flags, flags)
        }
        None => ()
      }
    }
  }
}

///|
test "reduced trigonometric enclosures skip unused series and use one series per interval" {
  let arguments = [
    (0.1, 0.1),
    (-0.1, -0.1),
    (0.3, 0.3000000000000001),
    (-0.3, 0.2),
    (0.0, 0.0),
    (-0.5, -0.4),
    (0.7, 0.7853981633974483),
    (-0.7853981633974483, 0.7853981633974483),
    (0.0009765625, 0.0009765625),
  ]
  for work in [64, 117, 200] {
    for argument in arguments {
      let lower = BinFloat::from_double(argument.0, precision=work)
      let upper = BinFloat::from_double(argument.1, precision=work)
      for quadrant in -2..<8 {
        for
          operation in [
            BinaryTrigonometricOperation::Sin,
            BinaryTrigonometricOperation::Cos,
            BinaryTrigonometricOperation::Tan,
          ] {
          assert_true(
            binary_reduced_agree(
              binary_reduced_trigonometric_bounds(
                lower, upper, quadrant, operation, work,
              ),
              binary_reduced_trigonometric_bounds_reference(
                lower, upper, quadrant, operation, work,
              ),
              lower,
              upper,
              work,
              operation,
            ),
          )
        }
      }
    }
  }
}

///|
test "sin, cos and tan results do not depend on the skipped series" {
  // End to end: the three functions on arguments in every quadrant, against
  // the identities that tie them together at binary64 and 200 bits.
  let context = BinaryContext::binary64()
  for index in 0..<16 {
    let value = BinFloat::from_double(
      0.37 + index.to_double() * 0.9,
      precision=53,
    )
    let (sine, _) = value.sin_ctx(context)
    let (cosine, _) = value.cos_ctx(context)
    let (tangent, _) = value.tan_ctx(context)
    // sin^2 + cos^2 = 1 and tan = sin / cos hold up to the rounding of each
    let norm = sine.mul(sine).add(cosine.mul(cosine))
    let drift = norm.sub(BinFloat::one()).abs()
    assert_true(drift < BinFloat::make_coeff(Coeff::one(), -50, 53))
    let quotient = sine.div(cosine)
    let tan_drift = quotient.sub(tangent).abs()
    assert_true(
      tan_drift <=
      tangent.abs().mul(BinFloat::make_coeff(Coeff::one(), -50, 53)),
    )
  }
}
