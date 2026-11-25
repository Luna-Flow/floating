// Issue 447: `Decimal::to_binary` panicked for very negative exponents
// (Int32 negation of -2^31, `precision + scale * 4 + 2` overflowing) and formed
// unbounded powers. A value outside the binary implementation range is decided
// from its adjusted exponent in Int64: overflow or underflow as the rounding
// direction says, at a cost that does not depend on the exponent.

///|
fn out_of_range_modes() -> Array[RoundingMode] {
  [
    RoundingMode::ToNearestEven,
    RoundingMode::TowardZero,
    RoundingMode::TowardPositive,
    RoundingMode::TowardNegative,
    RoundingMode::AwayFromZero,
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
// oracle: A
// source: written out from the rounding directions of IEEE 754-2019 4.3 and the exceptions of 7.4 and 7.5: every value of `out_of_range_values` has |exponent| of at least 330,000,000, so 10^e is above 2^1,073,741,823 or below the smallest subnormal 2^-1,073,741,874 (10^330000000 is about 2^1.096e9); an overflowing value gives infinity, or the largest finite number when the direction points toward zero; an underflowing value gives zero, or the smallest subnormal when the direction points away from zero; the sign is that of the operand
// shares: nothing
test "issue 447: to_binary at both ends of the exponent range, every rounding mode" {
  for mode in out_of_range_modes() {
    for pair in out_of_range_values() {
      let (coefficient, exponent) = pair
      let tiny = exponent < 0
      for negative in [false, true] {
        let signed = if negative { -coefficient } else { coefficient }
        let value = Decimal::make(signed, exponent, 34)
        let actual = value.to_binary(
          precision=53,
          mode=bin_mode(mode, negative),
        )
        // class: "zero", "min" (smallest subnormal), "max" (largest finite), "inf"
        let expected = match mode {
          RoundingMode::ToNearestEven => if tiny { "zero" } else { "inf" }
          RoundingMode::TowardZero => if tiny { "zero" } else { "max" }
          RoundingMode::TowardPositive =>
            if tiny {
              if negative {
                "zero"
              } else {
                "min"
              }
            } else if negative {
              "max"
            } else {
              "inf"
            }
          RoundingMode::TowardNegative =>
            if tiny {
              if negative {
                "min"
              } else {
                "zero"
              }
            } else if negative {
              "inf"
            } else {
              "max"
            }
          RoundingMode::AwayFromZero => if tiny { "min" } else { "inf" }
        }
        let got = if actual.is_zero() {
          "zero"
        } else if @def.is_infinite(actual) {
          "inf"
        } else if actual.exponent2() < 0 {
          "min"
        } else {
          "max"
        }
        assert_eq(
          (coefficient, exponent, negative, got),
          (coefficient, exponent, negative, expected),
        )
        assert_eq(actual.is_sign_minus(), negative)
      }
    }
  }
}

///|
// oracle: A
// source: written out: 1E-2147483645 is below the smallest subnormal, so rounding to nearest gives zero and rounding toward positive gives a nonzero positive number (IEEE 754-2019 4.3, 7.5); 1E+2147483646 is above the largest finite number, so rounding to nearest gives infinity (4.3, 7.4); the cases are the ones that panicked in issue 447
// shares: nothing
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
