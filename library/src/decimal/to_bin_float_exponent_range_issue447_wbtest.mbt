// Issue 447: `Decimal::to_bin_float` panicked for very negative exponents
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
    (1N, -2147483648),
    (9999999999999999999999999999999999N, -2147483648),
    (1N, -2147483647),
    (1N, -536870904),
    (12345N, -536870904),
    (1N, -400000000),
    (1N, -330000000),
    (1N, 330000000),
    (1N, 400000000),
    (7N, 536870904),
    (1N, 2147483647),
    (9999999999999999999999999999999999N, 2147483614),
  ]
}

///|
test "issue 447: to_bin_float at both ends of the exponent range, every rounding mode" {
  for mode in out_of_range_modes() {
    for pair in out_of_range_values() {
      let (coefficient, exponent) = pair
      for negative in [false, true] {
        let signed = if negative { -coefficient } else { coefficient }
        let value = Decimal::make(signed, exponent, 34)
        let actual = value.to_bin_float(precision=53, mode~)
        let expected = oracle_to_bin_float(signed, exponent, 53, mode)
        inspect(actual.to_string() == expected.to_string(), content="true")
        inspect(actual.is_negative() == negative, content="true")
      }
    }
  }
}

///|
test "issue 447: the reported cases do not panic" {
  let tiny = Decimal::make(1N, -2147483648, 34).to_bin_float()
  inspect(tiny.is_zero(), content="true")
  let huge = Decimal::make(1N, 2147483647, 34).to_bin_float()
  inspect(@def.is_infinite(huge), content="true")
  let directed_up = Decimal::make(1N, -2147483648, 34).to_bin_float(
    mode=RoundingMode::TowardPositive,
  )
  inspect(directed_up.is_zero(), content="false")
  inspect(directed_up.is_negative(), content="false")
}

///|
/// The same conversion through `to_bin_float_ctx`, which decides the out-of-range
/// cases from the exponent.
fn oracle_to_bin_float(
  coefficient : BigInt,
  exponent : Int32,
  precision : Int32,
  mode : RoundingMode,
) -> @bin_float.BinFloat {
  let value = Decimal::make(coefficient, exponent, 34)
  value.to_bin_float_ctx(
    @bin_float.BinaryContext::new(
      precision~,
      rounding=bin_mode(mode, value.negative),
    ),
  ).0
}
