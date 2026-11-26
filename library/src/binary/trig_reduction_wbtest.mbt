///|
/// Test-only copies of the trigonometric reduction and reduced-bounds functions
/// before #378 (always divides by pi/2, runs the series at both ends, eight tan
/// quotients): the new path must return bit-identical bounds.
fn old_trigonometric_reduction(
  value : Binary,
  half_pi : (Binary, Binary),
  work_precision : Int32,
) -> ((Binary, Binary), Int32)? {
  let downward = BinaryContext::new(
    precision=work_precision,
    rounding=RoundTowardNegative,
  )
  let upward = BinaryContext::new(
    precision=work_precision,
    rounding=RoundTowardPositive,
  )
  let input_bounds = (
    value.with_precision(
      work_precision,
      BinaryRoundingMode::RoundTowardNegative,
    ),
    value.with_precision(
      work_precision,
      BinaryRoundingMode::RoundTowardPositive,
    ),
  )
  let quotient = binary_quotient_bounds(input_bounds, half_pi, downward, upward)
  guard quotient is Some((quotient_lower, quotient_upper)) else { return None }
  let half = Binary::make(BinCoeff::one(), -1, work_precision)
  let lower_integer = binary_floor_integer(
    quotient_lower.add_ctx(half, downward).0,
  )
  let upper_integer = binary_floor_integer(
    quotient_upper.add_ctx(half, upward).0,
  )
  guard lower_integer is Some(quadrant_integer) &&
    upper_integer is Some(upper_quadrant) &&
    quadrant_integer.compare(upper_quadrant) == 0 else {
    return None
  }
  let quadrant = binary_integer_mod4(quadrant_integer)
  guard quadrant is Some(residue) else { return None }
  let product = binary_product_bounds(
    (quadrant_integer, quadrant_integer),
    half_pi,
    downward,
    upward,
  )
  Some(
    (
      (
        input_bounds.0.sub_ctx(product.1, downward).0,
        input_bounds.1.sub_ctx(product.0, upward).0,
      ),
      residue,
    ),
  )
}

///|
/// The enclosure of `sin`, `cos` or `tan` by the reduction with an enclosure of
/// `pi / 2` and the series: the path below the bit-burst threshold and the
/// reference of its tests.
fn old_trigonometric_bounds_series(
  value : Binary,
  operation : BinaryTrigonometricOperation,
  work_precision : Int32,
) -> (Binary, Binary)? {
  let pi = binary_pi_bounds(work_precision).unwrap()
  let downward = BinaryContext::new(
    precision=work_precision,
    rounding=RoundTowardNegative,
  )
  let upward = BinaryContext::new(
    precision=work_precision,
    rounding=RoundTowardPositive,
  )
  let half_pi = (
    pi.0.mul_ctx(Binary::make(BinCoeff::one(), -1, work_precision), downward).0,
    pi.1.mul_ctx(Binary::make(BinCoeff::one(), -1, work_precision), upward).0,
  )
  let quarter_pi = (
    half_pi.0.mul_ctx(
      Binary::make(BinCoeff::one(), -1, work_precision),
      downward,
    ).0,
    half_pi.1.mul_ctx(Binary::make(BinCoeff::one(), -1, work_precision), upward).0,
  )
  let reduction = old_trigonometric_reduction(value, half_pi, work_precision)
  guard reduction is Some(((lower, upper), quadrant)) else { return None }
  guard lower.compare(quarter_pi.0.neg()) >= 0 &&
    upper.compare(quarter_pi.1) <= 0 else {
    return None
  }
  old_reduced_trigonometric_bounds(
    lower, upper, quadrant, operation, work_precision,
  )
}

///|
fn old_reduced_trigonometric_bounds(
  lower : Binary,
  upper : Binary,
  quadrant : Int32,
  operation : BinaryTrigonometricOperation,
  work_precision : Int32,
) -> (Binary, Binary)? {
  let one = Binary::one(precision=work_precision)
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
  // The quadrant maps sine and cosine of the reduced argument onto the result
  // (see `mapped`): sine and cosine results of the even quadrants come from
  // the sine and cosine series, those of the odd quadrants from the other one.
  // A series that the requested operation does not read is not evaluated;
  // `zero` stands in for it and is never read.
  let zero = Binary::zero(precision=work_precision)
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
    let sin_upper = binary_sin_cos_series(upper, false, work_precision).unwrap()
    (sin_lower.0, sin_upper.1)
  } else {
    (zero, zero)
  }
  let cos_bounds = if !need_cos {
    (zero, zero)
  } else {
    let cos_lower = binary_sin_cos_series(lower, true, work_precision).unwrap()
    let cos_upper = binary_sin_cos_series(upper, true, work_precision).unwrap()
    if lower.compare(zero) <= 0 && upper.compare(zero) >= 0 {
      (
        if cos_lower.0.compare(cos_upper.0) < 0 {
          cos_lower.0
        } else {
          cos_upper.0
        },
        Binary::one(precision=work_precision),
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
      guard !(mapped.1.0.compare(Binary::zero()) <= 0 &&
        mapped.1.1.compare(Binary::zero()) >= 0) else {
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

///|
// oracle: A, S
// source: A: enclosure_rows_wbtest.mbt, generated by tools/generate_enclosure_rows.py; sin, cos and tan rows at w + 128 bits (GNU MPFR 4.2.2 rounded toward negative and toward positive infinity at the stated precision), library-ran: no; the arguments are inputs of the test and the reference is the pair of MPFR results; S: binary_series_agree against old_trigonometric_bounds_series (the path before #378 kept in this file): the new bounds agree with it (bit-identical or within the stated slack)
// shares: Binary::to_hex writes the key of the request, Binary::from_hex_ctx and Binary::add_ctx read the pair exactly (level A through hex_ctx_rows and arith_rows), Binary::compare in the containment checks; Binary::from_double builds the arguments; old_trigonometric_bounds_series and binary_series_agree in the agreement check
test "trigonometric bounds are bit-identical to the pre-#378 path" {
  let values = [
    1.0e-300, 1.0e-10, 0.001, 0.3, 0.7853981633974482, 0.7853981633974483, 0.7853981633974484,
    0.79, 1.0, 1.5707963267948966, 2.0, 3.0, 3.14159, 4.0, 10.0, 100.0, 12345.678,
    1.0e10,
  ]
  let mut checked = 0
  for w in [64, 128, 300] {
    for d in values {
      for sign in [1.0, -1.0] {
        let x = Binary::from_double(d * sign, precision=53)
        for
          op in [
            BinaryTrigonometricOperation::Sin,
            BinaryTrigonometricOperation::Cos,
            BinaryTrigonometricOperation::Tan,
          ] {
          let fresh = binary_trigonometric_bounds_series(x, op, w)
          let old = old_trigonometric_bounds_series(x, op, w)
          match (fresh, old) {
            (Some(bounds), Some(_)) => {
              // the true value lies between the MPFR results at w + 128 bits
              let reference = mpfr_enclosure(
                trigonometric_operation_name(op),
                x,
                w + 128,
              )
              assert_true(
                bounds.0.compare(reference.1) <= 0 &&
                bounds.1.compare(reference.0) >= 0,
                msg="trig contains MPFR \{x} w=\{w}",
              )
              assert_true(
                binary_series_agree(fresh, old, x, w, op),
                msg="trig \{x} w=\{w}",
              )
            }
            (None, None) => ()
            _ => fail("presence differs \{x} w=\{w}")
          }
          checked += 1
        }
      }
    }
  }
  assert_true(checked > 300)
}
