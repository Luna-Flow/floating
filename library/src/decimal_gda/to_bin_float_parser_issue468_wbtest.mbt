// Issue 468: `to_bin_float` formed `5^e` or `10^scale` for every exponent. From
// the exponent magnitude `decimal_parser_conversion_exponent` it converts
// through `BinFloat::from_string_ctx`; the result must be the one of the
// expansion, bit for bit (coefficient, exponent, sign), in every rounding mode.

///|
/// The expansion, as `to_bin_float` computed it before the parser path.
fn old_to_bin_float(
  value : Decimal,
  precision : Int32,
  mode : RoundingMode,
) -> @bin_float.BinFloat {
  if value.exponent10 >= 0 {
    let magnitude = coeff_bigint(value.coefficient) * pow5(value.exponent10)
    return @bin_float.BinFloat::make(
      @bin_float.BinCoeff::from_bytes_be(magnitude.to_octets()),
      value.exponent10,
      precision,
      negative=value.negative,
      mode~,
    )
  }
  let scale = -value.exponent10
  let binary_shift = precision + scale * 4 + 2
  let numerator = abs_bigint(coeff_bigint(value.coefficient)) << binary_shift
  let denominator = pow10(scale)
  let truncated = numerator / denominator
  let q = if (numerator % denominator).is_zero() {
    truncated
  } else {
    truncated | bigint_one()
  }
  @bin_float.BinFloat::make(
    @bin_float.BinCoeff::from_bytes_be(q.to_octets()),
    -binary_shift,
    precision,
    negative=value.sign() == Sign::Negative,
    mode~,
  )
}

///|
fn same_bin_float(a : @bin_float.BinFloat, b : @bin_float.BinFloat) -> Bool {
  a.to_string() == b.to_string() &&
  a.coefficient() == b.coefficient() &&
  a.exponent2() == b.exponent2() &&
  a.is_negative() == b.is_negative() &&
  a.is_zero() == b.is_zero() &&
  a.precision() == b.precision()
}

///|
fn parser_rows() -> Array[Decimal] {
  let coefficients : Array[BigInt] = [
    1N, 3N, 5N, 7N, 10N, 12345N, 99999999N, 123456789012345678901234567890123N, 9999999999999999999999999999999999N,
    4503599627370497N, 9007199254740993N,
  ]
  let exponents : Array[Int32] = [
    -20000, -9000, -5000, -4097, -4096, -4095, -1000, 1000, 4095, 4096, 4097, 5000,
    9000, 20000,
  ]
  let rows = []
  for c in coefficients {
    for e in exponents {
      rows.push(Decimal::make(c, e, 34))
      rows.push(Decimal::make(-c, e, 34))
    }
  }
  // Exactly representable values: 5^k * 10^-k = 2^-k, and 2^k * 5^k * 10^-k.
  for k in [4096, 4100, 5000] {
    rows.push(Decimal::make(pow5(k), -k, k * 3))
    rows.push(Decimal::make(BigInt::from_int(1) << k, 0, k * 3).neg())
  }
  rows
}

///|
test "issue 468: the parser path gives the result of the expansion in every mode" {
  let modes : Array[RoundingMode] = [
    RoundingMode::ToNearestEven,
    RoundingMode::TowardZero,
    RoundingMode::TowardPositive,
    RoundingMode::TowardNegative,
    RoundingMode::AwayFromZero,
  ]
  for value in parser_rows() {
    for mode in modes {
      for precision in [1, 2, 24, 53, 113, 300] {
        inspect(
          same_bin_float(
            value.to_bin_float(
              precision~,
              mode=@bin_float.BinaryRoundingMode::from_arithmetic(mode),
            ),
            old_to_bin_float(value, precision, mode),
          ),
          content="true",
        )
      }
    }
  }
}
