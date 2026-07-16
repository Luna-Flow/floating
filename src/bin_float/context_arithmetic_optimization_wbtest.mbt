///|
fn binary_split_shift_legacy_for_test(
  magnitude : BinCoeff,
  shift : Int,
) -> (BinCoeff, Bool, Bool) {
  if shift <= 0 {
    return (magnitude, false, false)
  }
  let quotient = magnitude.shift_right(shift)
  let remainder = magnitude.sub_checked(quotient.shift_left(shift)).unwrap()
  if remainder.is_zero() {
    (quotient, false, false)
  } else {
    let round_bit = magnitude.test_bit(shift - 1)
    let sticky = if round_bit { remainder.ctz() != shift - 1 } else { true }
    (quotient, round_bit, sticky)
  }
}

///|
fn binary_round_dyadic_legacy_for_test(
  negative : Bool,
  magnitude : BinCoeff,
  exponent2 : Int,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  if magnitude.is_zero() {
    return (
      finite_from_parts(negative, BinCoeff::zero(), 0, context.precision()),
      BinaryFlags::new(),
    )
  }
  let bits = magnitude.bit_length()
  let precision_shift = Int::max(0, bits - context.precision())
  let (precision_retained, precision_guard, precision_sticky) = binary_split_shift_legacy_for_test(
    magnitude, precision_shift,
  )
  let precision_rounded = binary_apply_round_bits(
    precision_retained,
    precision_guard,
    precision_sticky,
    negative,
    context.rounding(),
  )
  let unbounded_rounded_top = binary_exact_top(
    precision_rounded,
    binary_add_sat(exponent2, precision_shift),
  )
  let range_shift = match context.e_min() {
    Some(e_min) =>
      Int::max(
        0,
        binary_sub_sat(
          binary_sub_sat(e_min, context.precision() - 1),
          exponent2,
        ),
      )
    None => 0
  }
  let shift = Int::max(precision_shift, range_shift)
  let (retained, round_bit, sticky) = binary_split_shift_legacy_for_test(
    magnitude, shift,
  )
  binary_round_pack(
    negative,
    retained,
    round_bit,
    sticky,
    binary_add_sat(exponent2, shift),
    binary_exact_top(magnitude, exponent2),
    unbounded_rounded_top,
    context,
  )
}

///|
fn binary_round_rational_legacy_for_test(
  negative : Bool,
  numerator : BinCoeff,
  denominator : BinCoeff,
  exponent2 : Int,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  let exact_top = binary_add_sat(
    binary_floor_log2_ratio(numerator, denominator),
    exponent2,
  )
  let target_exponent = binary_target_exponent(exact_top, context)
  let scale = binary_sub_sat(exponent2, target_exponent)
  let (retained, round_bit, sticky) = binary_split_scaled_quotient(
    numerator, denominator, scale,
  )
  let unbounded_target = binary_sub_sat(exact_top, context.precision() - 1)
  let unbounded_scale = binary_sub_sat(exponent2, unbounded_target)
  let (unbounded_retained, unbounded_guard, unbounded_sticky) = binary_split_scaled_quotient(
    numerator, denominator, unbounded_scale,
  )
  let unbounded_rounded = binary_apply_round_bits(
    unbounded_retained,
    unbounded_guard,
    unbounded_sticky,
    negative,
    context.rounding(),
  )
  binary_round_pack(
    negative,
    retained,
    round_bit,
    sticky,
    target_exponent,
    exact_top,
    binary_exact_top(unbounded_rounded, unbounded_target),
    context,
  )
}

///|
fn binary_add_aligned_legacy_for_test(
  left : BinFloat,
  right : BinFloat,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  let target = Int::min(left.exponent2(), right.exponent2())
  let left_coefficient = left
    .coefficient()
    .shift_left(left.exponent2() - target)
  let right_coefficient = right
    .coefficient()
    .shift_left(right.exponent2() - target)
  if left.is_negative() == right.is_negative() {
    let (sum, normalization_shift) = bin_coeff_add_normalized_odd(
      left_coefficient, right_coefficient,
    )
    return binary_round_dyadic(
      left.is_negative(),
      sum,
      binary_add_sat(target, normalization_shift),
      context,
    )
  }
  let comparison = left_coefficient.compare(right_coefficient)
  if comparison == 0 {
    return (
      finite_from_parts(
        binary_exact_sum_zero_sign(left, right, context.rounding()),
        BinCoeff::zero(),
        0,
        context.precision(),
      ),
      BinaryFlags::new(),
    )
  }
  if comparison > 0 {
    let (difference, normalization_shift) = bin_coeff_sub_normalized_odd(
      left_coefficient, right_coefficient,
    )
    return binary_round_dyadic(
      left.is_negative(),
      difference,
      binary_add_sat(target, normalization_shift),
      context,
    )
  }
  let (difference, normalization_shift) = bin_coeff_sub_normalized_odd(
    right_coefficient, left_coefficient,
  )
  binary_round_dyadic(
    right.is_negative(),
    difference,
    binary_add_sat(target, normalization_shift),
    context,
  )
}

///|
test "optimized binary split shift matches remainder oracle" {
  for raw_value in 0..<1024 {
    let value = BinCoeff::from_uint64(raw_value.to_uint64())
    for shift in -1..<16 {
      let actual = binary_split_shift(value, shift)
      let expected = binary_split_shift_legacy_for_test(value, shift)
      assert_true(actual.0 == expected.0)
      assert_true(actual.1 == expected.1)
      assert_true(actual.2 == expected.2)
    }
  }
  let wide = BinCoeff::one()
    .shift_left(257)
    .add(BinCoeff::one().shift_left(128))
    .add(BinCoeff::one().shift_left(63))
    .add(BinCoeff::one())
  for
    value in [
      BinCoeff::zero(),
      wide,
      wide.shift_left(193),
      BinCoeff::one().shift_left(1024),
    ] {
    for shift in [1, 31, 32, 63, 64, 65, 127, 128, 129, 257, 511, 1024, 2048] {
      let actual = binary_split_shift(value, shift)
      let expected = binary_split_shift_legacy_for_test(value, shift)
      assert_true(actual.0 == expected.0)
      assert_true(actual.1 == expected.1)
      assert_true(actual.2 == expected.2)
    }
  }
}

///|
test "far exponent addition matches exact alignment around cutoff" {
  let modes = [
    BinaryRoundingMode::RoundTiesToEven,
    BinaryRoundingMode::RoundTiesToAway,
    BinaryRoundingMode::RoundTowardZero,
    BinaryRoundingMode::RoundTowardPositive,
    BinaryRoundingMode::RoundTowardNegative,
    BinaryRoundingMode::RoundAwayFromZero,
  ]
  let gaps = [1, 4, 6, 7, 8, 10, 14, 15, 31]
  let coefficient_pairs = [
    (1UL, 1UL),
    (3UL, 5UL),
    (7UL, 3UL),
    (1UL, 0x100001UL),
  ]
  for mode in modes {
    let contexts = [
      BinaryContext::unbounded(3, rounding=mode),
      BinaryContext::unbounded(7, rounding=mode),
      BinaryContext::binary16(rounding=mode),
      BinaryContext::binary16(
        rounding=mode,
        tininess=TininessDetection::BeforeRounding,
      ),
    ]
    for context in contexts {
      for gap in gaps {
        for pair in coefficient_pairs {
          for left_negative in [false, true] {
            for right_negative in [false, true] {
              let left = BinFloat::make(
                BinCoeff::from_uint64(pair.0),
                0,
                64,
                negative=left_negative,
              )
              let right = BinFloat::make(
                BinCoeff::from_uint64(pair.1),
                -gap,
                64,
                negative=right_negative,
              )
              let actual = left.add_ctx(right, context)
              let expected = binary_add_aligned_legacy_for_test(
                left, right, context,
              )
              assert_true(actual.0 == expected.0)
              assert_true(actual.1 == expected.1)
            }
          }
        }
      }
    }
  }
}

///|
test "wide exponent gaps stay on bounded coefficient paths" {
  let precision = 3
  let one = BinFloat::one(precision=53)
  let tiny = BinFloat::make(BinCoeff::one(), -1000000, 53)
  assert_true(one.compare(tiny) > 0)
  assert_true(tiny.compare(one) < 0)
  let nearest = one.add_ctx(tiny, BinaryContext::unbounded(precision))
  assert_eq(nearest.0, BinFloat::one(precision~))
  assert_true(nearest.1.inexact())
  let upward = one.add_ctx(
    tiny,
    BinaryContext::unbounded(
      precision,
      rounding=BinaryRoundingMode::RoundTowardPositive,
    ),
  )
  assert_eq(upward.0.coefficient(), BinCoeff::from_uint64(5UL))
  assert_eq(upward.0.exponent2(), -2)
  assert_true(upward.1.inexact())
}

///|
test "optimized dyadic rounding matches legacy control flow" {
  let wide = BinCoeff::one()
    .shift_left(257)
    .add(BinCoeff::one().shift_left(129))
    .add(BinCoeff::from_uint64(37UL))
  let magnitudes = [
    BinCoeff::zero(),
    BinCoeff::one(),
    BinCoeff::from_uint64(3UL),
    BinCoeff::from_uint64(0x7ffUL),
    BinCoeff::one().shift_left(64).sub_checked(BinCoeff::one()).unwrap(),
    wide,
  ]
  let modes = [
    BinaryRoundingMode::RoundTiesToEven,
    BinaryRoundingMode::RoundTiesToAway,
    BinaryRoundingMode::RoundTowardZero,
    BinaryRoundingMode::RoundTowardPositive,
    BinaryRoundingMode::RoundTowardNegative,
    BinaryRoundingMode::RoundAwayFromZero,
  ]
  for mode in modes {
    let contexts = [
      BinaryContext::unbounded(3, rounding=mode),
      BinaryContext::unbounded(53, rounding=mode),
      BinaryContext::binary16(rounding=mode),
      BinaryContext::binary16(
        rounding=mode,
        tininess=TininessDetection::BeforeRounding,
      ),
    ]
    for context in contexts {
      for negative in [false, true] {
        for magnitude in magnitudes {
          for exponent2 in [-300, -20, -1, 0, 17, 300] {
            let actual = binary_round_dyadic(
              negative, magnitude, exponent2, context,
            )
            let expected = binary_round_dyadic_legacy_for_test(
              negative, magnitude, exponent2, context,
            )
            assert_true(actual.0 == expected.0)
            assert_true(actual.1 == expected.1)
          }
        }
      }
    }
  }
}

///|
test "optimized rational rounding reuses equivalent target split" {
  let wide_numerator = BinCoeff::one()
    .shift_left(257)
    .add(BinCoeff::one().shift_left(113))
    .add(BinCoeff::from_uint64(37UL))
  let wide_denominator = BinCoeff::one()
    .shift_left(193)
    .add(BinCoeff::one().shift_left(61))
    .add(BinCoeff::from_uint64(3UL))
  let numerators = [
    BinCoeff::one(),
    BinCoeff::from_uint64(3UL),
    BinCoeff::from_uint64(0xffffUL),
    wide_numerator,
  ]
  let denominators = [
    BinCoeff::one(),
    BinCoeff::from_uint64(3UL),
    BinCoeff::from_uint64(0x101UL),
    wide_denominator,
  ]
  let modes = [
    BinaryRoundingMode::RoundTiesToEven,
    BinaryRoundingMode::RoundTiesToAway,
    BinaryRoundingMode::RoundTowardZero,
    BinaryRoundingMode::RoundTowardPositive,
    BinaryRoundingMode::RoundTowardNegative,
    BinaryRoundingMode::RoundAwayFromZero,
  ]
  for mode in modes {
    let contexts = [
      BinaryContext::unbounded(7, rounding=mode),
      BinaryContext::unbounded(53, rounding=mode),
      BinaryContext::binary16(rounding=mode),
    ]
    for context in contexts {
      for negative in [false, true] {
        for numerator in numerators {
          for denominator in denominators {
            for exponent2 in [-300, -20, 0, 17, 300] {
              let actual = binary_round_rational(
                negative, numerator, denominator, exponent2, context,
              )
              let expected = binary_round_rational_legacy_for_test(
                negative, numerator, denominator, exponent2, context,
              )
              assert_true(actual.0 == expected.0)
              assert_true(actual.1 == expected.1)
            }
          }
        }
      }
    }
  }
}

///|
test "single-track pow matches exact oracle across rounding modes" {
  let coefficients = [
    BinCoeff::from_uint64(3UL),
    BinCoeff::from_uint64(5UL),
    BinCoeff::from_uint64(0x7ffUL),
    BinCoeff::one()
    .shift_left(129)
    .add(BinCoeff::one().shift_left(65))
    .add(BinCoeff::one()),
  ]
  let modes = [
    BinaryRoundingMode::RoundTiesToEven,
    BinaryRoundingMode::RoundTiesToAway,
    BinaryRoundingMode::RoundTowardZero,
    BinaryRoundingMode::RoundTowardPositive,
    BinaryRoundingMode::RoundTowardNegative,
    BinaryRoundingMode::RoundAwayFromZero,
  ]
  let exponents = [-15, -9, -7, -3, -2, -1, 1, 2, 3, 5, 7, 9, 15]
  for mode in modes {
    let contexts = [
      BinaryContext::unbounded(7, rounding=mode),
      BinaryContext::unbounded(53, rounding=mode),
      BinaryContext::binary16(rounding=mode),
      BinaryContext::binary16(
        rounding=mode,
        tininess=TininessDetection::BeforeRounding,
      ),
    ]
    for context in contexts {
      for coefficient in coefficients {
        for exponent2 in [-40, -1, 0, 17] {
          for negative in [false, true] {
            let base = finite_from_parts(
              negative,
              coefficient,
              exponent2,
              coefficient.bit_length(),
            )
            for exponent in exponents {
              let magnitude = binary_exponent_magnitude(exponent)
              let reciprocal = exponent < 0
              let actual = binary_pow_magnitude_with_stats(
                  base, magnitude, reciprocal, context,
                ).0
              let expected = binary_pow_exact_magnitude(
                base, magnitude, reciprocal, context,
              )
              assert_true(actual.0 == expected.0)
              assert_true(actual.1 == expected.1)
            }
          }
        }
      }
    }
  }
}

///|
test "single-track pow uses leading-bit chain without ordinary fallback" {
  let base = finite_from_parts(
    false,
    BinCoeff::one()
    .shift_left(1024)
    .add(BinCoeff::one().shift_left(511))
    .add(BinCoeff::one()),
    -1024,
    1025,
  )
  let (_, stats) = binary_pow_magnitude_with_stats(
    base,
    7U,
    false,
    BinaryContext::unbounded(1024),
  )
  let summary = stats.summary()
  assert_true(summary.0 <= 4)
  assert_true(summary.1 <= 4)
  assert_eq(summary.2, 0)
  assert_true(summary.3 <= 2)
  assert_false(summary.5)
}

///|
test "single-track pow fixed-seed differential" {
  let modes = [
    BinaryRoundingMode::RoundTiesToEven,
    BinaryRoundingMode::RoundTiesToAway,
    BinaryRoundingMode::RoundTowardZero,
    BinaryRoundingMode::RoundTowardPositive,
    BinaryRoundingMode::RoundTowardNegative,
    BinaryRoundingMode::RoundAwayFromZero,
  ]
  let exponents = [-31, -17, -11, -5, -3, -1, 1, 3, 5, 7, 11, 17, 31]
  let mut state = 0x6a09_e667_f3bc_c909UL
  for index in 0..<256 {
    state = state * 6364136223846793005UL + 1442695040888963407UL
    let coefficient = BinCoeff::from_uint64((state >> 1) | 1UL)
    let base = finite_from_parts(
      (state & 1UL) != 0UL,
      coefficient,
      index % 81 - 40,
      coefficient.bit_length(),
    )
    let mode = modes[index % modes.length()]
    let context = if (index & 1) == 0 {
      BinaryContext::unbounded(index % 61 + 3, rounding=mode)
    } else {
      BinaryContext::binary16(
        rounding=mode,
        tininess=if (index & 2) == 0 {
          TininessDetection::AfterRounding
        } else {
          TininessDetection::BeforeRounding
        },
      )
    }
    let exponent = exponents[index % exponents.length()]
    let magnitude = binary_exponent_magnitude(exponent)
    let reciprocal = exponent < 0
    let actual = binary_pow_magnitude_with_stats(
        base, magnitude, reciprocal, context,
      ).0
    let expected = binary_pow_exact_magnitude(
      base, magnitude, reciprocal, context,
    )
    assert_true(actual.0 == expected.0)
    assert_true(actual.1 == expected.1)
  }
}
