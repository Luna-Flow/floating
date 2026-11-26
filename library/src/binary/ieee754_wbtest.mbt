///|
fn binary16_value(bits : String) -> Binary {
  BinaryInterchange::from_hex(bits, BinaryInterchangeFormat::Binary16)
  .unwrap()
  .to_binary()
}

///|
fn binary16_bits(value : Binary, context : BinaryContext) -> String {
  value.to_interchange(
    BinaryInterchangeFormat::Binary16,
    rounding=context.rounding(),
    tininess=context.tininess(),
  ).0.to_hex()
}

///|
// oracle: A
// source: written out from the binary16 encoding of IEEE Std 754-2019 3.4 (1 sign bit, 5 exponent bits, 10 trailing significand bits; the leading trailing-significand bit 0x200 is the quiet bit, 6.2.1): 8000 is -0, FC01 is a negative signaling NaN with payload 1, 7E2A is a quiet NaN with payload 0x2A = 42
// shares: binary16_value and binary16_bits encode the operands and decode the results with BinaryInterchange (the codec is also under test; the operand encodings and the result encodings are written by hand, so a symmetric codec error shows as a mismatch)
test "IEEE 754 interchange preserves observable zero and NaN state" {
  let negative_zero = binary16_value("8000")
  assert_true(negative_zero.is_zero())
  assert_true(negative_zero.is_negative_zero())
  assert_eq(binary16_bits(negative_zero, BinaryContext::binary16()), "8000")

  let signaling_nan = binary16_value("FC01")
  assert_true(signaling_nan.is_signaling_nan())
  assert_true(signaling_nan.is_sign_minus())
  assert_eq(signaling_nan.nan_payload_coeff().to_string(), "1")

  let quiet_nan = binary16_value("7E2A")
  assert_true(quiet_nan.is_quiet_nan())
  assert_eq(quiet_nan.nan_payload_coeff().to_string(), "42")
}

///|
// oracle: A
// source: written out from IEEE Std 754-2019 6.3: x + (-x) and (+0) + (-0) are +0 in every rounding direction except round toward negative, where they are -0, with no flag
// shares: binary16_value and binary16_bits encode the operands and decode the results with BinaryInterchange (the codec is also under test; the operand encodings and the result encodings are written by hand, so a symmetric codec error shows as a mismatch); add_ctx is the code under test
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
// oracle: A
// source: written out from IEEE Std 754-2019 6.2, 7.2, 7.3 and 5.4.1 in binary16 (flag bits of TestFloat: invalid 0x10, divide by zero 0x08, overflow 0x04, inexact 0x01): inf + (-inf) is the quiet NaN 7E00 with invalid, a signaling NaN 7C01 plus 1 is quieted to 7E01 with invalid, 1/0 is +inf with divide by zero, 0/0 is invalid, sqrt(-0) = -0 without exception, sqrt(-1) is invalid
// shares: binary16_value and binary16_bits encode the operands and decode the results with BinaryInterchange (the codec is also under test; the operand encodings and the result encodings are written by hand, so a symmetric codec error shows as a mismatch); to_testfloat_bits maps the flags to the bits named above; add_ctx, div_ctx and sqrt_ctx are the code under test
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
// oracle: A
// source: written out from IEEE Std 754-2019 7.4: the largest finite binary16 value 7BFF plus itself overflows to +inf in round to nearest and to the largest finite value 7BFF toward zero, both with overflow and inexact (0x05)
// shares: binary16_value and binary16_bits encode the operands and decode the results with BinaryInterchange (the codec is also under test; the operand encodings and the result encodings are written by hand, so a symmetric codec error shows as a mismatch); add_ctx is the code under test
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
// oracle: A
// source: written out from IEEE Std 754-2019 7.5: the binary16 product 2^-14 * (1 - 2^-11) = 2^-14 - 2^-25 is below the smallest normal number (tiny before rounding) and, rounded with an unbounded exponent range to 11 bits, is still 2^-14 - 2^-25 (exactly representable), so it is tiny after rounding too; the result rounds to the smallest normal 0400 (a tie to even between 2^-14 - 2^-24 and 2^-14) with underflow and inexact (0x03) under both detection rules
// shares: binary16_value and binary16_bits encode the operands and decode the results with BinaryInterchange (the codec is also under test; the operand encodings and the result encodings are written by hand, so a symmetric codec error shows as a mismatch); mul_ctx is the code under test
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
// oracle: A
// source: written out from the mathematics and IEEE Std 754-2019 7.4, 7.5 and 9.2.1: 1^n = 1 and (-1)^n = 1 for even n = -2^31, with no flag; 2^(-2^31) underflows (0 with 0x03 in nearest, the smallest subnormal 0001 toward positive infinity), (1/2)^(-2^31) = 2^(2^31) overflows to +inf (0x05), (3/2)^(-2^31) underflows to 0 and (3/4)^(-2^31) overflows to +inf in binary16
// shares: binary16_value and binary16_bits encode the operands and decode the results with BinaryInterchange (the codec is also under test; the operand encodings and the result encodings are written by hand, so a symmetric codec error shows as a mismatch); pown_ctx is the code under test
test "pown_ctx handles Int min without overflow" {
  let minimum_exponent = -2147483647 - 1
  let context = BinaryContext::binary16()
  let (one, one_flags) = Binary::one(precision=53).pown_ctx(
    minimum_exponent, context,
  )
  assert_eq(binary16_bits(one, context), "3C00")
  assert_eq(one_flags.to_testfloat_bits(), 0)
  let negative_one = Binary::from_int(-1, precision=53)
  let (even_power, even_flags) = negative_one.pown_ctx(
    minimum_exponent, context,
  )
  assert_eq(binary16_bits(even_power, context), "3C00")
  assert_eq(even_flags.to_testfloat_bits(), 0)
  let two = Binary::make_coeff(Coeff::one(), 1, 53)
  let (tiny, tiny_flags) = two.pown_ctx(minimum_exponent, context)
  assert_eq(binary16_bits(tiny, context), "0000")
  assert_eq(tiny_flags.to_testfloat_bits(), 0x03)
  let half = Binary::make_coeff(Coeff::one(), -1, 53)
  let (huge, huge_flags) = half.pown_ctx(minimum_exponent, context)
  assert_eq(binary16_bits(huge, context), "7C00")
  assert_eq(huge_flags.to_testfloat_bits(), 0x05)
  let upward_context = BinaryContext::binary16(
    rounding=BinaryRoundingMode::RoundTowardPositive,
  )
  let (upward_tiny, upward_tiny_flags) = two.pown_ctx(
    minimum_exponent, upward_context,
  )
  assert_eq(binary16_bits(upward_tiny, upward_context), "0001")
  assert_eq(upward_tiny_flags.to_testfloat_bits(), 0x03)
  let three_halves = Binary::make_coeff(Coeff::from_uint64(3UL), -1, 53)
  let (non_power_tiny, non_power_tiny_flags) = three_halves.pown_ctx(
    minimum_exponent, context,
  )
  assert_eq(binary16_bits(non_power_tiny, context), "0000")
  assert_eq(non_power_tiny_flags.to_testfloat_bits(), 0x03)
  let three_quarters = Binary::make_coeff(Coeff::from_uint64(3UL), -2, 53)
  let (non_power_huge, non_power_huge_flags) = three_quarters.pown_ctx(
    minimum_exponent, context,
  )
  assert_eq(binary16_bits(non_power_huge, context), "7C00")
  assert_eq(non_power_huge_flags.to_testfloat_bits(), 0x05)
}

///|
// oracle: S
// source: Binary::make_coeff of the magnitude, the sibling constructor, on 11 integers at five precisions and on Int32 minimum; the claim is that from_int builds what make_coeff builds
// shares: Binary::make_coeff and Coeff::from_uint64 on both sides
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
      let expected = Binary::make_coeff(
        Coeff::from_uint64(magnitude),
        0,
        precision,
        negative~,
      )
      assert_identical(Binary::from_int(value, precision~), expected)
    }
  }
  let minimum_int = -2147483647 - 1
  assert_identical(
    Binary::from_int(minimum_int, precision=64),
    Binary::make_coeff(Coeff::from_uint64(2147483648UL), 0, 64, negative=true),
  )
}

///|
// oracle: A
// source: written out from IEEE Std 754-2019 7.4 and 7.5: the smallest and the largest representable values of the library, 2^(e_min - 52) and 2^e_max, converted to binary16 underflow to 0 and overflow to +inf; the square root of 2^e_max, which is still far above the binary16 range, and the quotient 2^e_max / 2^(e_min - 52) overflow too (0x05); the outcome holds for any library limits far beyond the binary16 range
// shares: binary_value_e_min and binary_value_e_max build the operands only; apply_ctx, sqrt_ctx and div_ctx are the code under test; binary16_value and binary16_bits encode the operands and decode the results with BinaryInterchange (the codec is also under test; the operand encodings and the result encodings are written by hand, so a symmetric codec error shows as a mismatch)
test "context arithmetic keeps extreme exponents classified" {
  let context = BinaryContext::binary16()
  let minimum = Binary::make_coeff(Coeff::one(), binary_value_e_min - 52, 53)
  let maximum = Binary::make_coeff(Coeff::one(), binary_value_e_max, 53)
  let (tiny, tiny_flags) = minimum.apply_ctx(context)
  assert_true(tiny.is_zero())
  assert_eq(tiny_flags.to_testfloat_bits(), 0x03)
  let (huge, huge_flags) = maximum.apply_ctx(context)
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
// oracle: A, S
// source: A: the value identities 2 * 2^(e_max - 1) = 2^e_max and 4 * 2^(e_min - 54) = 2^(e_min - 52) and the classification of values beyond the range (infinity above, zero below); S: the canonical form (coefficient 1, exponent e_max) and the limits e_max and e_min are the library's own conventions, repeated in the expectations
// shares: Binary::make_coeff is the code under test; binary_value_e_min and binary_value_e_max are the library's constants; the coefficient_, exponent2 and classify accessors read the result
test "finite normalization never wraps extreme exponents" {
  let maximum = Binary::make_coeff(
    Coeff::from_uint64(2UL),
    binary_value_e_max - 1,
    53,
  )
  assert_eq(maximum.coefficient_(), Coeff::one())
  assert_eq(maximum.exponent2(), binary_value_e_max)
  let minimum = Binary::make_coeff(
    Coeff::from_uint64(4UL),
    binary_value_e_min - 54,
    53,
  )
  assert_eq(minimum.coefficient_(), Coeff::one())
  assert_eq(minimum.exponent2(), binary_value_e_min - 52)
  // Beyond the implementation range the value is classified, not wrapped.
  let over = Binary::make_coeff(Coeff::from_uint64(2UL), 2147483647, 53)
  assert_eq(over.classify(), FpClass::Infinity)
  let under = Binary::make_coeff(Coeff::from_uint64(4UL), -2147483648, 53)
  assert_true(under.is_zero())
}

///|
// oracle: A
// source: written out: at precision 3 the neighbours of 1 are 7/8 below and 5/4 above, so 1 + 2^(e_min - 52) rounds to 1 (inexact) in nearest, to 5/4 toward positive infinity and 1 - 2^(e_min - 52) rounds to 7/8 toward negative infinity, all inexact
// shares: binary_value_e_min is only the position of the tiny operand; add_ctx and sub_ctx are the code under test; the coefficient_ and exponent2 accessors print the results
test "addition compresses extreme exponent gaps without losing direction" {
  let one = Binary::one(precision=53)
  let tiny = Binary::make_coeff(Coeff::one(), binary_value_e_min - 52, 53)
  let nearest_context = BinaryContext::new(precision=3)
  let (nearest_sum, nearest_sum_flags) = one.add_ctx(tiny, nearest_context)
  assert_identical(nearest_sum, Binary::one(precision=3))
  assert_true(nearest_sum_flags.inexact())
  let upward_context = BinaryContext::new(
    precision=3,
    rounding=BinaryRoundingMode::RoundTowardPositive,
  )
  let (upward_sum, upward_sum_flags) = one.add_ctx(tiny, upward_context)
  assert_eq(upward_sum.coefficient_(), Coeff::from_uint64(5UL))
  assert_eq(upward_sum.exponent2(), -2)
  assert_true(upward_sum_flags.inexact())
  let downward_context = BinaryContext::new(
    precision=3,
    rounding=BinaryRoundingMode::RoundTowardNegative,
  )
  let (downward_difference, downward_difference_flags) = one.sub_ctx(
    tiny, downward_context,
  )
  assert_eq(downward_difference.coefficient_(), Coeff::from_uint64(7UL))
  assert_eq(downward_difference.exponent2(), -3)
  assert_true(downward_difference_flags.inexact())
}

///|
// oracle: A
// source: written out from the mathematics: sqrt(9 * 2^100) = 3 * 2^50 exactly (no flag) and sqrt(10 * 2^100) is irrational, above 3 * 2^50 and inexact at 11 bits
// shares: Binary::make_coeff builds the operands; sqrt_ctx is the code under test; compare and the flag accessors read the result
test "sqrt preserves exact roots when the scaled radicand is fractional" {
  let context = BinaryContext::new(precision=11)
  let exact_input = Binary::make_coeff(Coeff::from_uint64(9UL), 100, 128)
  let (exact_root, exact_flags) = exact_input.sqrt_ctx(context)
  assert_eq(exact_root.coefficient_(), Coeff::from_uint64(3UL))
  assert_eq(exact_root.exponent2(), 50)
  assert_eq(exact_flags.to_testfloat_bits(), 0)
  let inexact_input = Binary::make_coeff(Coeff::from_uint64(10UL), 100, 128)
  let (inexact_root, inexact_flags) = inexact_input.sqrt_ctx(context)
  assert_true(inexact_root.compare(exact_root) > 0)
  assert_true(inexact_flags.inexact())
}

///|
// oracle: B
// source: an integer model written in the test with the language's UInt64 arithmetic only: the floor of the root of m * 2^-s by a search over r with (r + 1)^2 2^s <= m, exactness by r^2 2^s = m, and the comparison of 4 m with (2 r + 1)^2 2^s for the midpoint, for m from 1 to 255 and s from 1 to 11, plus the extreme shift -2147483648 for the value 1
// shares: Coeff::from_uint64 and Coeff equality on both sides; binary_sqrt_split is the code under test
// primitives: Coeff::from_uint64 and the Coeff equality (level A through the coefficient oracle of library/src/internal/binary_kernel: coeff_regression and the CPython digests of tools/kernel_oracle.py); the expected values use the UInt64 operators of the language only
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
        Coeff::from_uint64(magnitude64),
        -denominator_shift,
      )
      assert_eq(root, Coeff::from_uint64(expected_root))
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
    Coeff::one(),
    -2147483648,
  )
  assert_true(root.is_zero())
  assert_false(exact)
  assert_eq(midpoint_comparison, -1)
}
