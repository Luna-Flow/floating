///|
/// The floating-point series enclosure of `ln` on `[1, 2]` as it was before the
/// fixed-point path was added (the general path, which still serves other
/// arguments).
fn binary_ln_unit_series_reference(
  value : BinFloat,
  work_precision : Int32,
) -> (BinFloat, BinFloat)? {
  let downward = BinaryContext::unbounded(
    work_precision,
    rounding=RoundTowardNegative,
  )
  let upward = BinaryContext::unbounded(
    work_precision,
    rounding=RoundTowardPositive,
  )
  let one = BinFloat::one(precision=work_precision)
  let two = BinFloat::from_int(2, precision=work_precision)
  let lower_value = value.with_precision(
    work_precision,
    RoundingMode::TowardNegative,
  )
  let upper_value = value.with_precision(
    work_precision,
    RoundingMode::TowardPositive,
  )
  guard lower_value.compare(one) >= 0 && upper_value.compare(two) <= 0 else {
    return None
  }
  let z_lower = lower_value.sub_ctx(one, downward).0.div_ctx(
      upper_value.add_ctx(one, upward).0,
      downward,
    ).0
  let z_upper = upper_value.sub_ctx(one, upward).0.div_ctx(
      lower_value.add_ctx(one, downward).0,
      upward,
    ).0
  let square_lower = z_lower.mul_ctx(z_lower, downward).0
  let square_upper = z_upper.mul_ctx(z_upper, upward).0
  let mut term_lower = z_lower
  let mut term_upper = z_upper
  let mut sum_lower = BinFloat::zero(precision=work_precision)
  let mut sum_upper = sum_lower
  let mut denominator = 1
  let threshold = BinFloat::make(
    BinCoeff::one(),
    -(work_precision + 8),
    work_precision,
  )
  while denominator < 20000 {
    let denominator_value = BinFloat::from_int(
      denominator,
      precision=work_precision,
    )
    let piece_lower = term_lower.div_ctx(denominator_value, downward).0
    let piece_upper = term_upper.div_ctx(denominator_value, upward).0
    sum_lower = sum_lower.add_ctx(piece_lower, downward).0
    sum_upper = sum_upper.add_ctx(piece_upper, upward).0
    denominator += 2
    term_lower = term_lower.mul_ctx(square_lower, downward).0
    term_upper = term_upper.mul_ctx(square_upper, upward).0
    if term_upper.compare(threshold) < 0 {
      let first_omitted = term_upper.div_ctx(
          BinFloat::from_int(denominator, precision=work_precision),
          upward,
        ).0
      let geometric_denominator = one.sub_ctx(square_upper, downward).0
      let tail = first_omitted.div_ctx(geometric_denominator, upward).0.mul_ctx(
          two, upward,
        ).0
      let lower = sum_lower.mul_ctx(two, downward).0
      let upper = sum_upper.mul_ctx(two, upward).0
      return Some((lower, upper.add_ctx(tail, upward).0))
    }
  }
  None
}

///|
/// `binary_ln_bounds` on top of the reference series.
fn binary_ln_bounds_series_reference(
  value : BinFloat,
  work_precision : Int32,
) -> (BinFloat, BinFloat)? {
  guard value.classify() == FpClass::Finite && value.sign() == Sign::Positive else {
    return None
  }
  let coefficient_bits = value.coefficient().bit_length()
  let normalized = BinFloat::make(
    value.coefficient(),
    -(coefficient_bits - 1),
    Int32::max(work_precision, coefficient_bits),
  )
  match
    (
      binary_ln_unit_series_reference(normalized, work_precision),
      binary_ln_unit_series_reference(
        BinFloat::from_int(2, precision=work_precision),
        work_precision,
      ),
    ) {
    (Some(unit), Some(ln2)) => {
      let downward = BinaryContext::unbounded(
        work_precision,
        rounding=RoundTowardNegative,
      )
      let upward = BinaryContext::unbounded(
        work_precision,
        rounding=RoundTowardPositive,
      )
      let exponent = value.exponent2() + coefficient_bits - 1
      let exponent_value = BinFloat::from_int(
        exponent,
        precision=work_precision,
      )
      if exponent >= 0 {
        Some(
          (
            unit.0.add_ctx(ln2.0.mul_ctx(exponent_value, downward).0, downward).0,
            unit.1.add_ctx(ln2.1.mul_ctx(exponent_value, upward).0, upward).0,
          ),
        )
      } else {
        let magnitude = exponent_value.neg()
        Some(
          (
            unit.0.sub_ctx(ln2.1.mul_ctx(magnitude, upward).0, downward).0,
            unit.1.sub_ctx(ln2.0.mul_ctx(magnitude, downward).0, upward).0,
          ),
        )
      }
    }
    _ => None
  }
}

///|
fn binary_ln_fixed_test_values() -> Array[BinFloat] {
  let values : Array[BinFloat] = []
  let mut state = 0x9E3779B97F4A7C15UL
  for index in 0..<60 {
    state = state * 6364136223846793005UL + 1442695040888963407UL
    let bits = Int32::max(2, 2 + index % 52)
    let mantissa = BinCoeff::from_uint64((state >> 11) | 1UL)
      .shift_right(64 - bits)
      .shift_left(1)
      .add(BinCoeff::one())
    values.push(BinFloat::make(mantissa, -(bits + 1) - index * 5 % 30 + 20, 53))
  }
  let near_one = [
    BinCoeff::one().shift_left(40).add(BinCoeff::one()), // 1 + 2^-40
    BinCoeff::one().shift_left(200).add(BinCoeff::one()), // 1 + 2^-200
    BinCoeff::one().shift_left(53).sub_checked(BinCoeff::one()).unwrap(), // 1 - 2^-53
  ]
  values.push(BinFloat::make(near_one[0], -40, 64))
  values.push(BinFloat::make(near_one[1], -200, 256))
  values.push(BinFloat::make(near_one[2], -53, 53))
  values.push(BinFloat::from_int(2))
  values.push(BinFloat::from_int(3))
  values.push(BinFloat::make(BinCoeff::one(), -1, 53))
  values.push(BinFloat::make(BinCoeff::one(), 40, 53))
  values.push(BinFloat::make(BinCoeff::one(), -70, 53))
  values.push(BinFloat::from_double(0.9999999, precision=53))
  values.push(BinFloat::from_double(1.0000001, precision=53))
  values
}

///|
fn binary_ln_fixed_same_class(left : BinFloat, right : BinFloat) -> Bool {
  left == right && left.precision() == right.precision()
}

///|
test "fixed-point ln enclosure contains a tighter series enclosure and is not looser" {
  for work in [20, 53, 64, 117, 181, 300] {
    for value in binary_ln_fixed_test_values() {
      let unit = if value.compare(BinFloat::one()) > 0 &&
        value.compare(BinFloat::from_int(2)) <= 0 {
        value
      } else {
        BinFloat::make(
          value.coefficient(),
          -(value.coefficient().bit_length() - 1),
          Int32::max(value.coefficient().bit_length(), 2),
        )
      }
      let fixed = binary_ln_unit_fixed_bounds(unit, work)
      if unit.compare(BinFloat::one()) > 0 &&
        unit.coefficient().bit_length() <= work &&
        unit.exponent2() > -4 * work {
        assert_true(fixed is Some(_))
      }
      guard fixed is Some((fixed_lower, fixed_upper)) else { continue }
      assert_true(fixed_lower.compare(fixed_upper) <= 0)
      guard binary_ln_unit_series_reference(unit, work * 2 + 64)
        is Some((tight_lower, tight_upper)) else {
        continue
      }
      assert_true(fixed_lower.compare(tight_lower) <= 0)
      assert_true(fixed_upper.compare(tight_upper) >= 0)
      guard binary_ln_unit_series_reference(unit, work)
        is Some((series_lower, series_upper)) else {
        continue
      }
      let context = BinaryContext::unbounded(
        work + 32,
        rounding=RoundTowardPositive,
      )
      let fixed_width = fixed_upper.sub_ctx(fixed_lower, context).0
      let series_width = series_upper.sub_ctx(series_lower, context).0
      assert_true(
        fixed_width.compare(series_width.mul(BinFloat::from_int(8))) <= 0,
      )
    }
  }
}

///|
test "fixed-point ln path gives the same correctly rounded results" {
  let contexts = [
    BinaryContext::binary64(),
    BinaryContext::unbounded(24),
    BinaryContext::unbounded(100),
    BinaryContext::unbounded(53, rounding=RoundTowardZero),
    BinaryContext::unbounded(53, rounding=RoundTowardNegative),
  ]
  for context in contexts {
    for value in binary_ln_fixed_test_values() {
      if value.compare(BinFloat::one()) == 0 {
        continue
      }
      let mut work = context.precision + 64
      let mut expected : (BinFloat, BinaryFlags)? = None
      let mut attempt = 0
      while attempt < 12 && expected is None {
        match binary_ln_bounds_series_reference(value, work) {
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
          let (actual, actual_flags) = value.ln_ctx(context)
          assert_true(binary_ln_fixed_same_class(actual, result))
          assert_eq(actual_flags, flags)
        }
        None => ()
      }
    }
  }
}

///|
test "fixed-point ln path declines arguments it does not cover" {
  let work = 100
  assert_true(binary_ln_unit_fixed_bounds(BinFloat::one(), work) is None)
  assert_true(binary_ln_unit_fixed_bounds(BinFloat::from_int(3), work) is None)
  assert_true(
    binary_ln_unit_fixed_bounds(BinFloat::from_int(-1).abs().neg(), work)
    is None,
  )
  assert_true(binary_ln_unit_fixed_bounds(BinFloat::zero(), work) is None)
  assert_true(binary_ln_unit_fixed_bounds(BinFloat::nan(), work) is None)
  // not exact at the working precision
  let wide = BinFloat::make(
    BinCoeff::one().shift_left(150).add(BinCoeff::one()),
    -150,
    160,
  )
  assert_true(binary_ln_unit_fixed_bounds(wide, work) is None)
  // the general path still answers
  assert_true(binary_ln_unit_bounds(wide, work) is Some(_))
  assert_true(binary_ln_unit_bounds(BinFloat::one(), work) is Some(_))
}
