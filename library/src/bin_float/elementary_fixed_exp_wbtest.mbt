///|
/// The floating-point series enclosure of `exp` as it was before the
/// fixed-point path was added (the general path, which still serves arguments
/// that are not exact at the working precision).
fn binary_exp_bounds_series_reference(
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
fn binary_exp_fixed_test_values() -> Array[BinFloat] {
  let values : Array[BinFloat] = []
  let mut state = 0x2545F4914F6CDD1DUL
  for index in 0..<60 {
    state = state * 6364136223846793005UL + 1442695040888963407UL
    let bits = 20 + index % 90
    let mantissa = Coeff::from_uint64((state >> 11) | 1UL)
      .shift_right(64 - Int32::min(bits, 53))
      .add(Coeff::one())
    // magnitudes from 2^-30 up to 2^9, both signs
    let exponent = -Int32::min(bits, 53) - 30 + index * 7 % 40
    values.push(
      BinFloat::make_coeff(
        mantissa,
        exponent,
        Int32::max(Int32::min(bits, 53), 2),
        negative=index % 3 == 0,
      ),
    )
  }
  values.push(BinFloat::make_coeff(Coeff::one(), -3, 53)) // exactly 1/8
  values.push(BinFloat::make_coeff(Coeff::one(), -3, 53, negative=true))
  values.push(BinFloat::make_coeff(Coeff::one(), -60000, 53)) // tiny
  values.push(BinFloat::make_coeff(Coeff::one(), 9, 53)) // 512
  values.push(BinFloat::make_coeff(Coeff::one(), -1, 53, negative=true))
  values
}

///|
test "fixed-point exp enclosure contains the series enclosure's true value" {
  for work in [20, 53, 64, 117, 181, 300] {
    for value in binary_exp_fixed_test_values() {
      let fixed = binary_exp_bounds_fixed(value, work)
      // arguments exact at the working precision always take the fixed path
      if value.coefficient_.bit_length() <= work {
        assert_true(fixed is Some(_))
      }
      guard fixed is Some((fixed_lower, fixed_upper)) else { continue }
      assert_true(fixed_lower.compare(fixed_upper) <= 0)
      // A far tighter series enclosure of the same exponential brackets the
      // true value, so it must lie inside the fixed-point enclosure.
      let tight_precision = work * 2 + 64
      guard binary_exp_bounds_series_reference(value, tight_precision)
        is Some((tight_lower, tight_upper)) else {
        continue
      }
      assert_true(fixed_lower.compare(tight_lower) <= 0)
      assert_true(fixed_upper.compare(tight_upper) >= 0)
      // and the enclosure is not looser than a few times the series one
      guard binary_exp_bounds_series_reference(value, work)
        is Some((series_lower, series_upper)) else {
        continue
      }
      let fixed_width = fixed_upper.sub_ctx(
          fixed_lower,
          BinaryContext::new(precision=work + 32, rounding=RoundTowardPositive),
        ).0
      let series_width = series_upper.sub_ctx(
          series_lower,
          BinaryContext::new(precision=work + 32, rounding=RoundTowardPositive),
        ).0
      assert_true(
        fixed_width.compare(series_width.mul(BinFloat::from_int(8))) <= 0,
      )
    }
  }
}

///|
test "fixed-point exp path gives the same correctly rounded results" {
  let contexts = [
    BinaryContext::binary64(),
    BinaryContext::new(precision=24),
    BinaryContext::new(precision=100),
    BinaryContext::new(precision=53, rounding=RoundTowardZero),
    BinaryContext::new(precision=53, rounding=RoundTowardPositive),
  ]
  for context in contexts {
    for value in binary_exp_fixed_test_values() {
      let value = value.with_precision(
        context.precision,
        BinaryRoundingMode::RoundTiesToEven,
      )
      let mut work = context.precision + 64
      let mut expected : (BinFloat, BinaryFlags)? = None
      let mut attempt = 0
      while attempt < 12 && expected is None {
        match binary_exp_bounds_series_reference(value, work) {
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
test "fixed-point exp path declines arguments it does not cover" {
  assert_true(binary_exp_bounds_fixed(BinFloat::zero(), 100) is None)
  assert_true(binary_exp_bounds_fixed(BinFloat::nan(), 100) is None)
  assert_true(
    binary_exp_bounds_fixed(BinFloat::inf(Sign::Positive, precision=53), 100)
    is None,
  )
  // not exact at the working precision: the general path runs
  let wide = BinFloat::make_coeff(
    Coeff::one().shift_left(150).add(Coeff::one()),
    -151,
    160,
  )
  assert_true(binary_exp_bounds_fixed(wide, 100) is None)
  assert_true(binary_exp_bounds(wide, 100) is Some(_))
}
