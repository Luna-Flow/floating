///|
/// Test-only copies of `binary_exp2_bounds` and `binary_log2_bounds` before
/// #378 (they recomputed `ln 2` through the full `ln` path): the new bounds
/// must contain the old ones evaluated at 128 more bits.

///|
fn old_exp2_bounds(
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
  match
    (
      binary_ln_bounds(
        BinFloat::from_int(2, precision=work_precision),
        work_precision,
      ),
      Some(
        (
          value.with_precision(
            work_precision,
            BinaryRoundingMode::RoundTowardNegative,
          ),
          value.with_precision(
            work_precision,
            BinaryRoundingMode::RoundTowardPositive,
          ),
        ),
      ),
    ) {
    (Some(log_two), Some(value_bounds)) => {
      let scaled = binary_product_bounds(
        value_bounds, log_two, downward, upward,
      )
      match
        (
          binary_exp_bounds(scaled.0, work_precision),
          binary_exp_bounds(scaled.1, work_precision),
        ) {
        (Some(lower), Some(upper)) => Some((lower.0, upper.1))
        _ => None
      }
    }
    _ => None
  }
}

///|
fn old_log2_bounds(
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
  match
    (
      binary_ln_bounds(value, work_precision),
      binary_ln_bounds(
        BinFloat::from_int(2, precision=work_precision),
        work_precision,
      ),
    ) {
    (Some(numerator), Some(denominator)) =>
      binary_quotient_bounds(numerator, denominator, downward, upward)
    _ => None
  }
}

///|
test "exp2 and log2 bounds with the cached ln 2 contain the old enclosures" {
  for w in [64, 128, 300] {
    for
      d in [1.0e-20, 0.001, 0.3, 0.75, 1.0, 1.5, 2.0, 3.7, 10.0, 77.25, 1000.5] {
      for sign in [1.0, -1.0] {
        let x = BinFloat::from_double(d * sign, precision=53)
        let fresh = binary_exp2_bounds(x, w).unwrap()
        let reference = old_exp2_bounds(x, w + 128).unwrap()
        assert_true(
          fresh.0.compare(reference.0) <= 0,
          msg="exp2 lower \{x} \{w}",
        )
        assert_true(
          fresh.1.compare(reference.1) >= 0,
          msg="exp2 upper \{x} \{w}",
        )
      }
      let y = BinFloat::from_double(d, precision=53)
      let fresh = binary_log2_bounds(y, w).unwrap()
      let reference = old_log2_bounds(y, w + 128).unwrap()
      assert_true(fresh.0.compare(reference.0) <= 0, msg="log2 lower \{y} \{w}")
      assert_true(fresh.1.compare(reference.1) >= 0, msg="log2 upper \{y} \{w}")
    }
  }
}
