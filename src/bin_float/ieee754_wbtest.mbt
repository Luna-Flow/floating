///|
fn binary16_value(bits : String) -> BinFloat {
  BinaryInterchange::from_hex(bits, BinaryInterchangeFormat::Binary16)
  .unwrap()
  .to_bin_float()
}

///|
fn binary16_bits(value : BinFloat, context : BinaryContext) -> String {
  value.to_interchange(
    BinaryInterchangeFormat::Binary16,
    rounding=context.rounding(),
    tininess=context.tininess(),
  ).0.to_hex()
}

///|
test "IEEE 754 interchange preserves observable zero and NaN state" {
  let negative_zero = binary16_value("8000")
  assert_true(negative_zero.is_zero())
  assert_true(negative_zero.is_negative_zero())
  assert_eq(binary16_bits(negative_zero, BinaryContext::binary16()), "8000")

  let signaling_nan = binary16_value("FC01")
  assert_true(signaling_nan.is_signaling_nan())
  assert_true(signaling_nan.is_negative())
  assert_eq(signaling_nan.nan_payload().to_string(), "1")

  let quiet_nan = binary16_value("7E2A")
  assert_true(quiet_nan.is_quiet_nan())
  assert_eq(quiet_nan.nan_payload().to_string(), "42")
}

///|
test "IEEE 754 exact cancellation selects the context zero sign" {
  let positive_zero = binary16_value("0000")
  let negative_zero = binary16_value("8000")
  let nearest_context = BinaryContext::binary16()
  let (nearest, nearest_flags) = positive_zero.add_ctx(
    negative_zero, nearest_context,
  )
  assert_eq(binary16_bits(nearest, nearest_context), "0000")
  assert_eq(nearest_flags.to_testfloat_bits(), 0)

  let downward_context = BinaryContext::binary16(
    rounding=BinaryRoundingMode::RoundTowardNegative,
  )
  let (downward, downward_flags) = positive_zero.add_ctx(
    negative_zero, downward_context,
  )
  assert_eq(binary16_bits(downward, downward_context), "8000")
  assert_eq(downward_flags.to_testfloat_bits(), 0)
}

///|
test "IEEE 754 special operations quiet NaNs and signal their conditions" {
  let context = BinaryContext::binary16()
  let (invalid_sum, invalid_sum_flags) = binary16_value("7C00").add_ctx(
    binary16_value("FC00"),
    context,
  )
  assert_eq(binary16_bits(invalid_sum, context), "7E00")
  assert_eq(invalid_sum_flags.to_testfloat_bits(), 0x10)

  let (quieted, quieted_flags) = binary16_value("7C01").add_ctx(
    binary16_value("3C00"),
    context,
  )
  assert_eq(binary16_bits(quieted, context), "7E01")
  assert_eq(quieted_flags.to_testfloat_bits(), 0x10)

  let (division, division_flags) = binary16_value("3C00").div_ctx(
    binary16_value("0000"),
    context,
  )
  assert_eq(binary16_bits(division, context), "7C00")
  assert_eq(division_flags.to_testfloat_bits(), 0x08)

  let (zero_division, zero_division_flags) = binary16_value("0000").div_ctx(
    binary16_value("0000"),
    context,
  )
  assert_eq(binary16_bits(zero_division, context), "7E00")
  assert_eq(zero_division_flags.to_testfloat_bits(), 0x10)

  let (negative_zero_root, negative_zero_root_flags) = binary16_value("8000").sqrt_ctx(
    context,
  )
  assert_eq(binary16_bits(negative_zero_root, context), "8000")
  assert_eq(negative_zero_root_flags.to_testfloat_bits(), 0)

  let (negative_root, negative_root_flags) = binary16_value("BC00").sqrt_ctx(
    context,
  )
  assert_eq(binary16_bits(negative_root, context), "7E00")
  assert_eq(negative_root_flags.to_testfloat_bits(), 0x10)
}

///|
test "IEEE 754 overflow obeys directed finite-result rules" {
  let max_finite = binary16_value("7BFF")
  let nearest_context = BinaryContext::binary16()
  let (nearest, nearest_flags) = max_finite.add_ctx(max_finite, nearest_context)
  assert_eq(binary16_bits(nearest, nearest_context), "7C00")
  assert_eq(nearest_flags.to_testfloat_bits(), 0x05)

  let zero_context = BinaryContext::binary16(
    rounding=BinaryRoundingMode::RoundTowardZero,
  )
  let (toward_zero, toward_zero_flags) = max_finite.add_ctx(
    max_finite, zero_context,
  )
  assert_eq(binary16_bits(toward_zero, zero_context), "7BFF")
  assert_eq(toward_zero_flags.to_testfloat_bits(), 0x05)
}

///|
test "IEEE 754 after-rounding tininess uses the precision-rounded value" {
  let minimum_normal = binary16_value("0400")
  let just_below_one = binary16_value("3BFF")
  let after_context = BinaryContext::binary16(
    tininess=TininessDetection::AfterRounding,
  )
  let (after, after_flags) = minimum_normal.mul_ctx(
    just_below_one, after_context,
  )
  assert_eq(binary16_bits(after, after_context), "0400")
  assert_eq(after_flags.to_testfloat_bits(), 0x03)

  let before_context = BinaryContext::binary16(
    tininess=TininessDetection::BeforeRounding,
  )
  let (before, before_flags) = minimum_normal.mul_ctx(
    just_below_one, before_context,
  )
  assert_eq(binary16_bits(before, before_context), "0400")
  assert_eq(before_flags.to_testfloat_bits(), 0x03)
}

///|
test "pow_int_ctx handles Int min without overflow" {
  let minimum_exponent = -2147483647 - 1
  let context = BinaryContext::binary16()
  let (one, one_flags) = BinFloat::one(precision=53).pow_int_ctx(
    minimum_exponent, context,
  )
  assert_eq(binary16_bits(one, context), "3C00")
  assert_eq(one_flags.to_testfloat_bits(), 0)
  let negative_one = BinFloat::from_int(-1, precision=53)
  let (even_power, even_flags) = negative_one.pow_int_ctx(
    minimum_exponent, context,
  )
  assert_eq(binary16_bits(even_power, context), "3C00")
  assert_eq(even_flags.to_testfloat_bits(), 0)
  let two = BinFloat::make(BinCoeff::one(), 1, 53)
  let (tiny, tiny_flags) = two.pow_int_ctx(minimum_exponent, context)
  assert_eq(binary16_bits(tiny, context), "0000")
  assert_eq(tiny_flags.to_testfloat_bits(), 0x03)
  let half = BinFloat::make(BinCoeff::one(), -1, 53)
  let (huge, huge_flags) = half.pow_int_ctx(minimum_exponent, context)
  assert_eq(binary16_bits(huge, context), "7C00")
  assert_eq(huge_flags.to_testfloat_bits(), 0x05)
  let upward_context = BinaryContext::binary16(
    rounding=BinaryRoundingMode::RoundTowardPositive,
  )
  let (upward_tiny, upward_tiny_flags) = two.pow_int_ctx(
    minimum_exponent, upward_context,
  )
  assert_eq(binary16_bits(upward_tiny, upward_context), "0001")
  assert_eq(upward_tiny_flags.to_testfloat_bits(), 0x03)
  let three_halves = BinFloat::make(BinCoeff::from_uint64(3UL), -1, 53)
  let (non_power_tiny, non_power_tiny_flags) = three_halves.pow_int_ctx(
    minimum_exponent, context,
  )
  assert_eq(binary16_bits(non_power_tiny, context), "0000")
  assert_eq(non_power_tiny_flags.to_testfloat_bits(), 0x03)
  let three_quarters = BinFloat::make(BinCoeff::from_uint64(3UL), -2, 53)
  let (non_power_huge, non_power_huge_flags) = three_quarters.pow_int_ctx(
    minimum_exponent, context,
  )
  assert_eq(binary16_bits(non_power_huge, context), "7C00")
  assert_eq(non_power_huge_flags.to_testfloat_bits(), 0x05)
}

///|
test "from_int preserves exact and rounded construction semantics" {
  let values = [0, 1, -1, 2, -2, 3, -3, 127, -128, 1024, 10000]
  for precision in [1, 2, 3, 8, 53] {
    for value in values {
      let negative = value < 0
      let magnitude = if negative {
        (-(value + 1)).to_uint64() + 1UL
      } else {
        value.to_uint64()
      }
      let expected = BinFloat::make(
        BinCoeff::from_uint64(magnitude),
        0,
        precision,
        negative~,
      )
      assert_eq(BinFloat::from_int(value, precision~), expected)
    }
  }
  let minimum_int = -2147483647 - 1
  assert_eq(
    BinFloat::from_int(minimum_int, precision=64),
    BinFloat::make(BinCoeff::from_uint64(2147483648UL), 0, 64, negative=true),
  )
}

///|
test "context arithmetic keeps extreme exponents classified" {
  let context = BinaryContext::binary16()
  let minimum = BinFloat::make(BinCoeff::one(), -2147483648, 53)
  let maximum = BinFloat::make(BinCoeff::one(), 2147483647, 53)
  let (tiny, tiny_flags) = minimum.round_ctx(context)
  assert_true(tiny.is_zero())
  assert_eq(tiny_flags.to_testfloat_bits(), 0x03)
  let (huge, huge_flags) = maximum.round_ctx(context)
  assert_eq(binary16_bits(huge, context), "7C00")
  assert_eq(huge_flags.to_testfloat_bits(), 0x05)
  let (sqrt_huge, sqrt_huge_flags) = maximum.sqrt_ctx(context)
  assert_eq(binary16_bits(sqrt_huge, context), "7C00")
  assert_eq(sqrt_huge_flags.to_testfloat_bits(), 0x05)
  let (quotient, quotient_flags) = maximum.div_ctx(minimum, context)
  assert_eq(binary16_bits(quotient, context), "7C00")
  assert_eq(quotient_flags.to_testfloat_bits(), 0x05)
}

///|
test "finite normalization never wraps extreme exponents" {
  let maximum = BinFloat::make(BinCoeff::from_uint64(2UL), 2147483647, 53)
  assert_eq(maximum.coefficient(), BinCoeff::one())
  assert_eq(maximum.exponent2(), 2147483647)
  let minimum = BinFloat::make(BinCoeff::from_uint64(4UL), -2147483648, 53)
  assert_eq(minimum.coefficient(), BinCoeff::one())
  assert_eq(minimum.exponent2(), -2147483646)
}

///|
test "addition compresses extreme exponent gaps without losing direction" {
  let one = BinFloat::one(precision=53)
  let tiny = BinFloat::make(BinCoeff::one(), -2147483648, 53)
  let nearest_context = BinaryContext::unbounded(3)
  let (nearest_sum, nearest_sum_flags) = one.add_ctx(tiny, nearest_context)
  assert_eq(nearest_sum, BinFloat::one(precision=3))
  assert_true(nearest_sum_flags.inexact())
  let upward_context = BinaryContext::unbounded(
    3,
    rounding=BinaryRoundingMode::RoundTowardPositive,
  )
  let (upward_sum, upward_sum_flags) = one.add_ctx(tiny, upward_context)
  assert_eq(upward_sum.coefficient(), BinCoeff::from_uint64(5UL))
  assert_eq(upward_sum.exponent2(), -2)
  assert_true(upward_sum_flags.inexact())
  let downward_context = BinaryContext::unbounded(
    3,
    rounding=BinaryRoundingMode::RoundTowardNegative,
  )
  let (downward_difference, downward_difference_flags) = one.sub_ctx(
    tiny, downward_context,
  )
  assert_eq(downward_difference.coefficient(), BinCoeff::from_uint64(7UL))
  assert_eq(downward_difference.exponent2(), -3)
  assert_true(downward_difference_flags.inexact())
}

///|
test "sqrt preserves exact roots when the scaled radicand is fractional" {
  let context = BinaryContext::unbounded(11)
  let exact_input = BinFloat::make(BinCoeff::from_uint64(9UL), 100, 128)
  let (exact_root, exact_flags) = exact_input.sqrt_ctx(context)
  assert_eq(exact_root.coefficient(), BinCoeff::from_uint64(3UL))
  assert_eq(exact_root.exponent2(), 50)
  assert_eq(exact_flags.to_testfloat_bits(), 0)
  let inexact_input = BinFloat::make(BinCoeff::from_uint64(10UL), 100, 128)
  let (inexact_root, inexact_flags) = inexact_input.sqrt_ctx(context)
  assert_true(inexact_root.compare(exact_root) > 0)
  assert_true(inexact_flags.inexact())
}

///|
test "fractional sqrt splitting retains exact midpoint information" {
  for magnitude in 1..<256 {
    for denominator_shift in 1..<12 {
      let magnitude64 = magnitude.to_uint64()
      let mut expected_root = 0UL
      while ((expected_root + 1UL) * (expected_root + 1UL)) << denominator_shift <=
            magnitude64 {
        expected_root += 1UL
      }
      let (root, exact, midpoint_comparison) = binary_sqrt_split(
        BinCoeff::from_uint64(magnitude64),
        -denominator_shift,
      )
      assert_eq(root, BinCoeff::from_uint64(expected_root))
      assert_eq(
        exact,
        (expected_root * expected_root) << denominator_shift == magnitude64,
      )
      let midpoint_left = magnitude64 << 2
      let midpoint_right = (
          (expected_root * 2UL + 1UL) * (expected_root * 2UL + 1UL)
        ) <<
        denominator_shift
      let expected_comparison = if midpoint_left < midpoint_right {
        -1
      } else if midpoint_left > midpoint_right {
        1
      } else {
        0
      }
      assert_eq(midpoint_comparison, expected_comparison)
    }
  }
  let (root, exact, midpoint_comparison) = binary_sqrt_split(
    BinCoeff::one(),
    -2147483648,
  )
  assert_true(root.is_zero())
  assert_false(exact)
  assert_eq(midpoint_comparison, -1)
}
