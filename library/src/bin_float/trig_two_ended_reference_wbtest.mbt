///|
/// The enclosure of the reduced trigonometric functions with one series at each
/// end of the interval (the form before the midpoint form), the reference of
/// the tests of the midpoint form.
fn binary_reduced_trigonometric_bounds_two_ended(
  lower : BinFloat,
  upper : BinFloat,
  quadrant : Int32,
  operation : BinaryTrigonometricOperation,
  work_precision : Int32,
) -> (BinFloat, BinFloat)? {
  let one = BinFloat::one_raw(precision=work_precision)
  guard lower.compare(upper) <= 0 &&
    lower.compare(one.neg()) >= 0 &&
    upper.compare(one) <= 0 else {
    return None
  }
  let downward = binary_working_context(
    work_precision,
    rounding=RoundTowardNegative,
  )
  let upward = binary_working_context(
    work_precision,
    rounding=RoundTowardPositive,
  )
  // The quadrant maps sine and cosine of the reduced argument onto the result
  // (see `mapped`): sine and cosine results of the even quadrants come from
  // the sine and cosine series, those of the odd quadrants from the other one.
  // A series that the requested operation does not read is not evaluated;
  // `zero` stands in for it and is never read.
  let zero = BinFloat::zero_raw(precision=work_precision)
  let sine_first = match quadrant % 4 {
    0 | 2 => true
    _ => false
  }
  let need_sin = match operation {
    BinaryTrigonometricOperation::Sin => sine_first
    BinaryTrigonometricOperation::Cos => !sine_first
    BinaryTrigonometricOperation::Tan => true
  }
  let need_cos = match operation {
    BinaryTrigonometricOperation::Sin => !sine_first
    BinaryTrigonometricOperation::Cos => sine_first
    BinaryTrigonometricOperation::Tan => true
  }
  let sin_bounds = if need_sin {
    let sin_lower = binary_sin_cos_series(lower, false, work_precision).unwrap()
    let sin_upper = if lower.compare(upper) == 0 {
      sin_lower
    } else {
      binary_sin_cos_series(upper, false, work_precision).unwrap()
    }
    (sin_lower.0, sin_upper.1)
  } else {
    (zero, zero)
  }
  let cos_bounds = if !need_cos {
    (zero, zero)
  } else {
    let cos_lower = binary_sin_cos_series(lower, true, work_precision).unwrap()
    let cos_upper = if lower.compare(upper) == 0 {
      cos_lower
    } else {
      binary_sin_cos_series(upper, true, work_precision).unwrap()
    }
    if lower.compare(zero) <= 0 && upper.compare(zero) >= 0 {
      (
        if cos_lower.0.compare(cos_upper.0) < 0 {
          cos_lower.0
        } else {
          cos_upper.0
        },
        BinFloat::one_raw(precision=work_precision),
      )
    } else if upper.compare(zero) <= 0 {
      (cos_lower.0, cos_upper.1)
    } else {
      (cos_upper.0, cos_lower.1)
    }
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
      guard !(mapped.1.0.compare(BinFloat::zero_raw()) <= 0 &&
        mapped.1.1.compare(BinFloat::zero_raw()) >= 0) else {
        return None
      }
      // The cosine enclosure has a definite sign here. For a negative cosine
      // n / d = (-n) / (-d) with -d positive.
      if mapped.1.0.compare(BinFloat::zero_raw()) > 0 {
        return binary_quotient_bounds(mapped.0, mapped.1, downward, upward)
      }
      // A zero end of the numerator: its sign depends on the candidate order of
      // the four-candidate form, so keep that form (rare: only for an exact
      // zero argument).
      if mapped.0.0.is_zero() || mapped.0.1.is_zero() {
        return Some(
          binary_quotient_bounds_general(mapped.0, mapped.1, downward, upward),
        )
      }
      return binary_quotient_bounds(
        (mapped.0.1.neg(), mapped.0.0.neg()),
        (mapped.1.1.neg(), mapped.1.0.neg()),
        downward,
        upward,
      )
    }
  }
}
