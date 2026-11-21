///|
/// Test-only copy of `binary_hyperbolic_bounds` before #378 (two exp kernel
/// calls, eight-candidate tanh); the new enclosures must contain the old one
/// evaluated at 128 more bits.
fn old_hyperbolic_bounds(
  value : Binary,
  operation : BinaryHyperbolicOperation,
  work_precision : Int32,
) -> (Binary, Binary)? {
  match
    (
      binary_exp_bounds(value, work_precision),
      binary_exp_bounds(value.neg(), work_precision),
    ) {
    (Some(positive_exp), Some(negative_exp)) => {
      let downward = BinaryContext::new(
        precision=work_precision,
        rounding=RoundTowardNegative,
      )
      let upward = BinaryContext::new(
        precision=work_precision,
        rounding=RoundTowardPositive,
      )
      let half = Binary::make(BinCoeff::one(), -1, work_precision)
      let sinh = (
        positive_exp.0.sub_ctx(negative_exp.1, downward).0.mul_ctx(
          half, downward,
        ).0,
        positive_exp.1.sub_ctx(negative_exp.0, upward).0.mul_ctx(half, upward).0,
      )
      let cosh = (
        positive_exp.0.add_ctx(negative_exp.0, downward).0.mul_ctx(
          half, downward,
        ).0,
        positive_exp.1.add_ctx(negative_exp.1, upward).0.mul_ctx(half, upward).0,
      )
      match operation {
        BinaryHyperbolicOperation::Sinh => Some(sinh)
        BinaryHyperbolicOperation::Cosh => Some(cosh)
        BinaryHyperbolicOperation::Tanh => {
          let lower_candidates = [
            sinh.0.div_ctx(cosh.0, downward).0,
            sinh.0.div_ctx(cosh.1, downward).0,
            sinh.1.div_ctx(cosh.0, downward).0,
            sinh.1.div_ctx(cosh.1, downward).0,
          ]
          let upper_candidates = [
            sinh.0.div_ctx(cosh.0, upward).0,
            sinh.0.div_ctx(cosh.1, upward).0,
            sinh.1.div_ctx(cosh.0, upward).0,
            sinh.1.div_ctx(cosh.1, upward).0,
          ]
          let mut lower = lower_candidates[0]
          let mut upper = upper_candidates[0]
          for candidate in lower_candidates[1:] {
            if candidate.compare(lower) < 0 {
              lower = candidate
            }
          }
          for candidate in upper_candidates[1:] {
            if candidate.compare(upper) > 0 {
              upper = candidate
            }
          }
          Some((lower, upper))
        }
      }
    }
    _ => None
  }
}

///|
test "hyperbolic bounds contain the high-precision old enclosure" {
  let values = [
    1.0e-30, 0.001, 0.3, 0.9, 1.0, 2.5, 7.0, 31.0, 100.5, 700.0, 5000.0,
  ]
  for w in [64, 128, 256] {
    for d in values {
      for sign in [1.0, -1.0] {
        let x = Binary::from_double(d * sign, precision=53)
        for
          op in [
            BinaryHyperbolicOperation::Sinh,
            BinaryHyperbolicOperation::Cosh,
            BinaryHyperbolicOperation::Tanh,
          ] {
          let fresh = binary_hyperbolic_bounds(x, op, w).unwrap()
          let reference = old_hyperbolic_bounds(x, op, w + 128).unwrap()
          assert_true(
            fresh.0.compare(reference.0) <= 0,
            msg="lower \{x} w=\{w}",
          )
          assert_true(
            fresh.1.compare(reference.1) >= 0,
            msg="upper \{x} w=\{w}",
          )
        }
      }
    }
  }
}
