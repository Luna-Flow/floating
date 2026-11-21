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
test "issue 447: to_binary at both ends of the exponent range, every rounding mode" {
  for mode in out_of_range_modes() {
    for pair in out_of_range_values() {
      let (coefficient, exponent) = pair
      for negative in [false, true] {
        let signed = if negative { -coefficient } else { coefficient }
        let value = Decimal::make(signed, exponent, 34)
        let actual = value.to_binary(
          precision=53,
          mode=bin_mode(mode, negative),
        )
        let expected = oracle_to_binary(signed, exponent, 53, mode)
        inspect(actual.to_string() == expected.to_string(), content="true")
        inspect(actual.is_negative() == negative, content="true")
      }
    }
  }
}

///|
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
  inspect(directed_up.is_negative(), content="false")
}

///|
/// The same conversion through the exact decimal parser of `binary`, which
/// decides the out-of-range cases from the exponent.
fn oracle_to_binary(
  coefficient : BigInt,
  exponent : Int32,
  precision : Int32,
  mode : RoundingMode,
) -> @binary.Binary {
  let text = coefficient.to_string() + "E" + exponent.to_string()
  @binary.Binary::from_string_ctx(
    text,
    @binary.BinaryContext::new(
      precision~,
      rounding=bin_mode(mode, coefficient < BigInt::from_int(0)),
    ),
  ).unwrap().0
}
