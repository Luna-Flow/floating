///|
/// Test-only copies of the four-candidate `binary_product_bounds` and
/// `binary_quotient_bounds` before #378: the sign-aware versions must return
/// bit-identical bounds for every sign pattern.

///|
fn old_product_bounds(
  left : (BinFloat, BinFloat),
  right : (BinFloat, BinFloat),
  downward : BinaryContext,
  upward : BinaryContext,
) -> (BinFloat, BinFloat) {
  let lower_candidates = [
    left.0.mul_ctx(right.0, downward).0,
    left.0.mul_ctx(right.1, downward).0,
    left.1.mul_ctx(right.0, downward).0,
    left.1.mul_ctx(right.1, downward).0,
  ]
  let upper_candidates = [
    left.0.mul_ctx(right.0, upward).0,
    left.0.mul_ctx(right.1, upward).0,
    left.1.mul_ctx(right.0, upward).0,
    left.1.mul_ctx(right.1, upward).0,
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
  (lower, upper)
}

///|
fn old_quotient_bounds(
  numerator : (BinFloat, BinFloat),
  denominator : (BinFloat, BinFloat),
  downward : BinaryContext,
  upward : BinaryContext,
) -> (BinFloat, BinFloat)? {
  guard denominator.0.compare(BinFloat::zero()) > 0 else { return None }
  let lower_candidates = [
    numerator.0.div_ctx(denominator.0, downward).0,
    numerator.0.div_ctx(denominator.1, downward).0,
    numerator.1.div_ctx(denominator.0, downward).0,
    numerator.1.div_ctx(denominator.1, downward).0,
  ]
  let upper_candidates = [
    numerator.0.div_ctx(denominator.0, upward).0,
    numerator.0.div_ctx(denominator.1, upward).0,
    numerator.1.div_ctx(denominator.0, upward).0,
    numerator.1.div_ctx(denominator.1, upward).0,
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

///|
test "sign-aware product and quotient bounds equal the four-candidate versions" {
  let values = [
    -1.0e10, -77.0, -3.5, -1.0, -0.25, -1.0e-9, -0.0, 0.0, 1.0e-9, 0.25, 1.0, 3.5,
    77.0, 1.0e10,
  ]
  let mut checked = 0
  for precision in [24, 53, 130] {
    let downward = BinaryContext::new(precision~, rounding=RoundTowardNegative)
    let upward = BinaryContext::new(precision~, rounding=RoundTowardPositive)
    for a0 in values {
      for a1 in values {
        if a0 <= a1 {
          for b0 in values {
            for b1 in values {
              if b0 <= b1 {
                let left = (
                  BinFloat::from_double(a0, precision=53),
                  BinFloat::from_double(a1, precision=53),
                )
                let right = (
                  BinFloat::from_double(b0, precision=53),
                  BinFloat::from_double(b1, precision=53),
                )
                let fresh = binary_product_bounds(left, right, downward, upward)
                let old = old_product_bounds(left, right, downward, upward)
                assert_true(
                  fresh.0 == old.0 && fresh.1 == old.1,
                  msg="product \{a0} \{a1} \{b0} \{b1}",
                )
                let fq = binary_quotient_bounds(left, right, downward, upward)
                let oq = old_quotient_bounds(left, right, downward, upward)
                match (fq, oq) {
                  (Some(f), Some(o)) =>
                    assert_true(
                      f.0 == o.0 && f.1 == o.1,
                      msg="quotient \{a0} \{a1} \{b0} \{b1}",
                    )
                  (None, None) => ()
                  _ => fail("quotient presence differs")
                }
                checked += 1
              }
            }
          }
        }
      }
    }
  }
  assert_true(checked > 1000)
}
