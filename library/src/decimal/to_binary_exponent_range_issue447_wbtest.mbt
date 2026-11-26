// Issue 447: `Decimal::to_binary` panicked for very negative exponents
// (Int32 negation of -2^31, `precision + scale * 4 + 2` overflowing) and formed
// unbounded powers. A value outside the binary implementation range is decided
// from its adjusted exponent in Int64: overflow or underflow as the rounding
// direction says, at a cost that does not depend on the exponent.

///|
fn out_of_range_modes() -> Array[@binary.BinaryRoundingMode] {
  [
    @binary.BinaryRoundingMode::RoundTiesToEven,
    @binary.BinaryRoundingMode::RoundTiesToAway,
    @binary.BinaryRoundingMode::RoundTowardZero,
    @binary.BinaryRoundingMode::RoundTowardPositive,
    @binary.BinaryRoundingMode::RoundTowardNegative,
  ]
}

///|
fn out_of_range_values() -> Array[(BigInt, Int32)] {
  [
    (1N, -2147483645),
    (9999999999999999999999999999999999N, -2147483645),
    (1N, -2147483644),
    (1N, -536870904),
    (12345N, -536870904),
    (1N, -400000000),
    (1N, -330000000),
    (1N, 330000000),
    (1N, 400000000),
    (7N, 536870904),
    (1N, 2147483646),
    (9999999999999999999999999999999999N, 2147483613),
  ]
}

///|
/// The result of an out-of-range conversion at 53 bits, from the rule of IEEE 754-2019
/// 4.3 and 7.4: a value above the largest finite number (`(2^53 - 1) * 2^1073741771`,
/// leading bit exponent `emax = 1073741823`) is infinite in the two nearest modes and
/// toward the infinity of its sign, the largest finite number in the others; a value
/// below the least positive one (`2^-1073741874 = 2^(emin - p + 1)`, `emin = 1 - emax`)
/// and below half of it is zero in the nearest modes and toward zero, and the least
/// number toward the infinity of its sign.
fn out_of_range_expected(
  overflow : Bool,
  negative : Bool,
  mode : @binary.BinaryRoundingMode,
) -> @binary.Binary {
  let toward_value = match mode {
    @binary.BinaryRoundingMode::RoundTowardPositive => !negative
    @binary.BinaryRoundingMode::RoundTowardNegative => negative
    _ => false
  }
  let nearest = match mode {
    @binary.BinaryRoundingMode::RoundTiesToEven
    | @binary.BinaryRoundingMode::RoundTiesToAway => true
    _ => false
  }
  if overflow {
    if nearest || toward_value {
      @binary.Binary::inf(negative~)
    } else {
      @binary.Binary::make(
        @binary.BinCoeff::from_bytes_be(9007199254740991N.to_octets()),
        1073741771,
        53,
        negative~,
        mode=@binary.BinaryRoundingMode::RoundTiesToEven,
      )
    }
  } else if toward_value {
    @binary.Binary::make(
      @binary.BinCoeff::from_bytes_be(1N.to_octets()),
      -1073741874,
      53,
      negative~,
      mode=@binary.BinaryRoundingMode::RoundTiesToEven,
    )
  } else if negative {
    @binary.Binary::negative_zero(precision=53)
  } else {
    @binary.Binary::zero(precision=53)
  }
}

///|
// oracle: A, S
// source: written out from the range of the binary format at 53 bits (emax 1073741823, least positive number 2^-1073741874, largest finite (2^53 - 1) * 2^1073741771) and IEEE 754-2019 4.3 and 7.4: every one of the twelve values has a decimal exponent whose power of ten is beyond 2^+-1.07e9 (10^330000000 is about 2^1.0963e9, the nearest to the range is 10^-330000000, about 2^-1.0963e9), so the result depends only on the sign, the side and the rounding direction; the earlier oracle was to_binary_ctx, which shares the code under test (the numbers 1073741823 and 2^-1073741874 are this library's binary range, the rules are IEEE)
// shares: Binary::make, BinCoeff::from_bytes_be, Binary::inf and zero (they build the expected number), Decimal::make (it builds the operand), Binary::compare and is_sign_minus
test "issue 447: to_binary at both ends of the exponent range, every rounding mode" {
  for index, mode in out_of_range_modes() {
    for pair in out_of_range_values() {
      let (coefficient, exponent) = pair
      for negative in [false, true] {
        let signed = if negative { -coefficient } else { coefficient }
        let value = Decimal::make(signed, exponent, 34)
        let actual = value.to_binary(precision=53, mode~)
        let expected = out_of_range_expected(exponent > 0, negative, mode)
        let label = (coefficient.to_string(), exponent, negative, index)
        assert_eq((label, actual.to_string()), (label, expected.to_string()))
        assert_eq((label, actual.is_sign_minus()), (label, negative))
      }
    }
  }
}

///|
// oracle: A
// source: written out: 10^-2147483645 is far below the smallest binary number and converts to 0 in nearest, 10^2147483646 converts to infinity, and the tiny value rounded toward positive infinity is a nonzero positive number (IEEE Std 754-2019 4.3, 7.4, 7.5); the block is a regression test for a panic
// shares: Decimal::make builds the operands; to_binary is the code under test; @def.is_infinite, is_zero and is_sign_minus read the result
test "issue 447: the reported cases do not panic" {
  let tiny = Decimal::make(1N, -2147483645, 34).to_binary(precision=53)
  inspect(tiny.is_zero(), content="true")
  let huge = Decimal::make(1N, 2147483646, 34).to_binary(precision=53)
  inspect(@def.is_infinite(huge), content="true")
  let directed_up = Decimal::make(1N, -2147483645, 34).to_binary(
    precision=53,
    mode=@binary.BinaryRoundingMode::RoundTowardPositive,
  )
  inspect(directed_up.is_zero(), content="false")
  inspect(directed_up.is_sign_minus(), content="false")
}
