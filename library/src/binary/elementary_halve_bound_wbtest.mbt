///|
test "halving the bounds of pi by the exponent equals the product by 1/2" {
  for work in [64, 65, 100, 128, 150, 192, 225, 609, 1536, 4160] {
    let pi = binary_pi_bounds(work).unwrap()
    let downward = binary_working_context(work, rounding=RoundTowardNegative)
    let upward = binary_working_context(work, rounding=RoundTowardPositive)
    let half = Binary::make_coeff(Coeff::one(), -1, work)
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
  let half = Binary::make_coeff(Coeff::one(), -1, work)
  // a value of another precision, a value near the bottom of the exponent range,
  // zero: all through the product
  let values = [
    Binary::from_int(3, precision=53),
    Binary::make_coeff(Coeff::from_uint64(5UL), -1073741820, work),
    Binary::zero(precision=work),
  ]
  for value in values {
    let a = binary_halve_bound(value, work, downward)
    let b = value.mul_ctx(half, downward).0
    assert_eq(a.compare(b), 0)
    assert_eq(a.precision(), b.precision())
  }
}

///|
/// The series path with the old two-ended reduced bounds (reference).
fn binary_trigonometric_bounds_series_reference(
  value : Binary,
  operation : BinaryTrigonometricOperation,
  work_precision : Int32,
) -> (Binary, Binary)? {
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
    binary_halve_bound(pi.0, work_precision, downward),
    binary_halve_bound(pi.1, work_precision, upward),
  )
  let quarter_pi = (
    binary_halve_bound(half_pi.0, work_precision, downward),
    binary_halve_bound(half_pi.1, work_precision, upward),
  )
  let reduction = binary_trigonometric_reduction(value, half_pi, work_precision)
  guard reduction is Some(((lower, upper), quadrant)) else { return None }
  guard lower.compare(quarter_pi.0.neg()) >= 0 &&
    upper.compare(quarter_pi.1) <= 0 else {
    return None
  }
  binary_reduced_trigonometric_bounds_two_ended(
    lower, upper, quadrant, operation, work_precision,
  )
}

///|
test "midpoint form of the reduced bounds: contained in the two-ended bounds widened by the interval, and containing the exact value" {
  let mut seed = 31UL
  let mut checked = 0
  let mut widened = 0
  for p in [53, 64, 128, 200, 512] {
    for top in [-3, -1, 0, 1, 2, 5, 40, 200, 300, 1000] {
      for
        operation in [
          BinaryTrigonometricOperation::Sin,
          BinaryTrigonometricOperation::Cos,
          BinaryTrigonometricOperation::Tan,
        ] {
        seed += 1UL
        let value = burst_test_value(p, top, seed % 2UL == 0UL, seed)
        let work = p + Int32::max(0, top) + 96
        let new = binary_trigonometric_bounds_series(value, operation, work)
        let old = binary_trigonometric_bounds_series_reference(
          value, operation, work,
        )
        let exact = binary_trigonometric_bounds_series_reference(
          value,
          operation,
          work + 256,
        )
        match (new, old, exact) {
          (Some(a), Some(b), Some(e)) => {
            // both contain the value at 256 bits more
            assert_true(a.0.compare(e.0) <= 0 && e.1.compare(a.1) <= 0)
            assert_true(b.0.compare(e.0) <= 0 && e.1.compare(b.1) <= 0)
            // new inside old widened by the slack: the width `w` of the reduced
            // interval (twice, for the two sums) plus a few units of the work
            // precision; tan is checked only for containment (the quotient
            // amplifies the width by its conditioning)
            if operation != BinaryTrigonometricOperation::Tan {
              let pi = binary_pi_bounds(work).unwrap()
              let down = binary_working_context(
                work,
                rounding=RoundTowardNegative,
              )
              let up = binary_working_context(
                work,
                rounding=RoundTowardPositive,
              )
              let half_pi = (
                binary_halve_bound(pi.0, work, down),
                binary_halve_bound(pi.1, work, up),
              )
              let ((lower, upper), _) = binary_trigonometric_reduction(
                value, half_pi, work,
              ).unwrap()
              let width = upper.sub(lower)
              let slack = width
                .add(width)
                .add(Binary::make_coeff(Coeff::one(), -(work - 24), 1))
              assert_true(a.0.compare(b.0.sub(slack)) >= 0)
              assert_true(a.1.compare(b.1.add(slack)) <= 0)
            }
            if a.0.compare(b.0) < 0 || a.1.compare(b.1) > 0 {
              widened += 1
            }
            checked += 1
          }
          (None, None, _) => ()
          _ => ()
        }
      }
    }
  }
  assert_true(checked > 60)
  ignore(widened)
}

///|
test "tan of the midpoint form declines exactly where the two-ended form does" {
  let mut seed = 777UL
  let mut compared = 0
  for p in [53, 128, 512] {
    for top in [-2, 0, 1, 2, 3, 10, 60] {
      for _ in 0..<12 {
        seed += 1UL
        let value = burst_test_value(p, top, seed % 2UL == 0UL, seed)
        let work = p + Int32::max(0, top) + 96
        let a = binary_trigonometric_bounds_series(
          value,
          BinaryTrigonometricOperation::Tan,
          work,
        )
        let b = binary_trigonometric_bounds_series_reference(
          value,
          BinaryTrigonometricOperation::Tan,
          work,
        )
        assert_eq(a is None, b is None)
        compared += 1
      }
    }
  }
  assert_true(compared > 200)
}

///|
test "huge argument: the ends are rounded to the series precision first, both forms contain the value" {
  // An argument with an exponent of a few thousand: the reduction needs
  // `work` bits, the series only `work - top` (at least 64).
  let mut seed = 9091UL
  for p in [53, 128] {
    for top in [3000, 5000] {
      for
        operation in [
          BinaryTrigonometricOperation::Sin,
          BinaryTrigonometricOperation::Cos,
          BinaryTrigonometricOperation::Tan,
        ] {
        seed += 1UL
        let value = burst_test_value(p, top, false, seed)
        let work = p + top + 96
        let a = binary_trigonometric_bounds_series(value, operation, work)
        let b = binary_trigonometric_bounds_series_reference(
          value, operation, work,
        )
        let exact = binary_trigonometric_bounds_series_reference(
          value,
          operation,
          work + 256,
        )
        match (a, b, exact) {
          (Some(x), Some(y), Some(e)) => {
            assert_true(x.0.compare(e.0) <= 0 && e.1.compare(x.1) <= 0)
            assert_true(y.0.compare(e.0) <= 0 && e.1.compare(y.1) <= 0)
          }
          (None, None, _) => ()
          _ => fail("forms disagree on declining")
        }
      }
    }
  }
}

///|
/// The midpoint form of the reduced bounds against an older enclosure of the same
/// function: both decline or answer, a point interval gives the same bits, and for
/// sine and cosine of a wider interval the new bounds lie within the old ones
/// widened by twice the width plus a few units of the work precision.
fn binary_reduced_agree(
  new : (Binary, Binary)?,
  old : (Binary, Binary)?,
  lower : Binary,
  upper : Binary,
  work : Int32,
  operation : BinaryTrigonometricOperation,
) -> Bool {
  match (new, old) {
    (None, None) => true
    (Some(a), Some(b)) =>
      if lower.compare(upper) == 0 {
        a.0.identical(b.0) && a.1.identical(b.1)
      } else if operation == BinaryTrigonometricOperation::Tan {
        true
      } else {
        let width = upper.sub(lower)
        let slack = width
          .add(width)
          .add(Binary::make_coeff(Coeff::one(), -(work - 24), 1))
        a.0.compare(b.0.sub(slack)) >= 0 && a.1.compare(b.1.add(slack)) <= 0
      }
    _ => false
  }
}

///|
/// The same for the whole series path of `value`: the width of the reduced
/// interval is recomputed from the reduction.
fn binary_series_agree(
  new : (Binary, Binary)?,
  old : (Binary, Binary)?,
  value : Binary,
  work : Int32,
  operation : BinaryTrigonometricOperation,
) -> Bool {
  match (new, old) {
    (None, None) => true
    (Some(a), Some(b)) => {
      let pi = binary_pi_bounds(work).unwrap()
      let down = binary_working_context(work, rounding=RoundTowardNegative)
      let up = binary_working_context(work, rounding=RoundTowardPositive)
      let half_pi = (
        binary_halve_bound(pi.0, work, down),
        binary_halve_bound(pi.1, work, up),
      )
      match binary_trigonometric_reduction(value, half_pi, work) {
        Some(((lower, upper), _)) =>
          binary_reduced_agree(Some(a), Some(b), lower, upper, work, operation)
        None => false
      }
    }
    _ => false
  }
}
