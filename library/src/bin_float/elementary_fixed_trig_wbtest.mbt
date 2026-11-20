///|
/// The floating-point sine and cosine series as it was before the fixed-point
/// path was added (the general path, which still serves other arguments).
fn binary_sin_cos_series_reference(
  value : BinFloat,
  cosine : Bool,
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
  let negative = value.is_negative()
  let argument = if negative { value.neg() } else { value }
  let argument_lower = argument.with_precision(
    work_precision,
    RoundingMode::TowardNegative,
  )
  let argument_upper = argument.with_precision(
    work_precision,
    RoundingMode::TowardPositive,
  )
  let square_lower = argument_lower.mul_ctx(argument_lower, downward).0
  let square_upper = argument_upper.mul_ctx(argument_upper, upward).0
  let mut term_lower = if cosine {
    BinFloat::one(precision=work_precision)
  } else {
    argument_lower
  }
  let mut term_upper = if cosine {
    BinFloat::one(precision=work_precision)
  } else {
    argument_upper
  }
  let mut sum_lower = term_lower
  let mut sum_upper = term_upper
  let mut bracket_lower = term_lower
  let mut bracket_upper = term_upper
  let threshold = BinFloat::make_coeff(
    Coeff::one(),
    -(work_precision + 12),
    work_precision,
  )
  let mut index = 1
  while index < 20000 {
    if cosine {
      term_lower = term_lower.mul_ctx(square_lower, downward).0.div_ctx(
          BinFloat::from_int(
            (2 * index - 1) * (2 * index),
            precision=work_precision,
          ),
          downward,
        ).0
      term_upper = term_upper.mul_ctx(square_upper, upward).0.div_ctx(
          BinFloat::from_int(
            (2 * index - 1) * (2 * index),
            precision=work_precision,
          ),
          upward,
        ).0
    } else {
      term_lower = term_lower.mul_ctx(square_lower, downward).0.div_ctx(
          BinFloat::from_int(
            2 * index * (2 * index + 1),
            precision=work_precision,
          ),
          downward,
        ).0
      term_upper = term_upper.mul_ctx(square_upper, upward).0.div_ctx(
          BinFloat::from_int(
            2 * index * (2 * index + 1),
            precision=work_precision,
          ),
          upward,
        ).0
    }
    if index % 2 == 1 {
      sum_lower = sum_lower.sub_ctx(term_upper, downward).0
      sum_upper = sum_upper.sub_ctx(term_lower, upward).0
      bracket_lower = sum_lower
    } else {
      sum_lower = sum_lower.add_ctx(term_lower, downward).0
      sum_upper = sum_upper.add_ctx(term_upper, upward).0
      bracket_upper = sum_upper
    }
    if index % 2 == 1 && term_upper.compare(threshold) < 0 {
      if cosine || !negative {
        return Some((bracket_lower, bracket_upper))
      }
      return Some((bracket_upper.neg(), bracket_lower.neg()))
    }
    index += 1
  }
  None
}

///|
fn binary_sin_cos_fixed_test_values() -> Array[BinFloat] {
  let values : Array[BinFloat] = []
  let mut state = 0xD1B54A32D192ED03UL
  for index in 0..<50 {
    state = state * 6364136223846793005UL + 1442695040888963407UL
    let bits = 2 + index % 52
    let mantissa = Coeff::from_uint64((state >> 11) | 1UL)
      .shift_right(64 - bits)
      .shift_left(1)
      .add(Coeff::one())
    // magnitudes from about 2^-40 up to 1, both signs
    let exponent = -(bits + 1) - index * 3 % 40
    values.push(
      BinFloat::make_coeff(mantissa, exponent, 53, negative=index % 2 == 0),
    )
  }
  values.push(BinFloat::make_coeff(Coeff::one(), -1, 53))
  values.push(BinFloat::make_coeff(Coeff::one(), -1, 53, negative=true))
  values.push(BinFloat::make_coeff(Coeff::one(), -300, 53))
  values.push(BinFloat::make_coeff(Coeff::one(), 0, 53)) // exactly 1
  values.push(BinFloat::make_coeff(Coeff::one(), 0, 53, negative=true))
  values.push(BinFloat::from_double(0.7853981633974483, precision=53))
  values.push(BinFloat::from_double(-0.7853981633974483, precision=53))
  values.push(BinFloat::from_double(0.9999999999999999, precision=53))
  values
}

///|
test "fixed-point sine and cosine enclosures contain a tighter series enclosure" {
  for work in [20, 53, 64, 117, 181, 300] {
    for value in binary_sin_cos_fixed_test_values() {
      for cosine in [false, true] {
        let fixed = binary_sin_cos_fixed_series(value, cosine, work)
        // Covered unless the cosine argument has bits below the fixed-point
        // unit (then the general series runs) or the sine argument is so
        // small that its guard bits would exceed four times the precision.
        let covered = value.coefficient_.bit_length() <= work &&
          (
            (cosine && work + 20 + value.exponent2() >= 0) ||
            (
              !cosine &&
              -(value.exponent2() + value.coefficient_.bit_length() - 1) <=
              4 * work + 64
            )
          )
        if covered {
          assert_true(fixed is Some(_))
        }
        guard fixed is Some((fixed_lower, fixed_upper)) else { continue }
        assert_true(fixed_lower.compare(fixed_upper) <= 0)
        guard binary_sin_cos_series_reference(value, cosine, work * 2 + 64)
          is Some((tight_lower, tight_upper)) else {
          continue
        }
        assert_true(fixed_lower.compare(tight_lower) <= 0)
        assert_true(fixed_upper.compare(tight_upper) >= 0)
        guard binary_sin_cos_series_reference(value, cosine, work)
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
          fixed_width.compare(series_width.mul(BinFloat::from_int(16))) <= 0,
        )
      }
    }
  }
}

///|
test "fixed-point sine and cosine decline arguments they do not cover" {
  let work = 100
  assert_true(
    binary_sin_cos_fixed_series(BinFloat::zero(), false, work) is None,
  )
  assert_true(binary_sin_cos_fixed_series(BinFloat::nan(), true, work) is None)
  assert_true(
    binary_sin_cos_fixed_series(BinFloat::from_int(2), false, work) is None,
  )
  assert_true(
    binary_sin_cos_fixed_series(
      BinFloat::from_double(1.5, precision=53),
      true,
      work,
    )
    is None,
  )
  let wide = BinFloat::make_coeff(
    Coeff::one().shift_left(150).add(Coeff::one()),
    -152,
    160,
  )
  assert_true(binary_sin_cos_fixed_series(wide, false, work) is None)
  assert_true(binary_sin_cos_series(wide, false, work) is Some(_))
}

///|
test "sine and cosine agree with their identities after the fixed-point path" {
  let context = BinaryContext::unbounded(100)
  for value in binary_sin_cos_fixed_test_values() {
    let (sine, _) = value.sin_ctx(context)
    let (cosine, _) = value.cos_ctx(context)
    let norm = sine.mul(sine).add(cosine.mul(cosine))
    assert_true(
      norm.sub(BinFloat::one()).abs() <
      BinFloat::make_coeff(Coeff::one(), -95, 100),
    )
    let (odd, _) = value.neg().sin_ctx(context)
    assert_eq(odd, sine.neg())
    let (even, _) = value.neg().cos_ctx(context)
    assert_eq(even, cosine)
  }
}
