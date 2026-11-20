// Issue 468: `decimal_gda`'s `Decimal::to_bin_float` allocated gigabytes for an
// exponent of 10^7 or more. Its results at large exponents are checked against
// the `decimal` package, which converts through directed bounds of `5^|e|`, a
// different algorithm: rows at 10^6, 10^7, 3 x 10^7 and near both ends of the
// binary range, both signs, every rounding mode.

///|
test "issue 468: decimal_gda to_bin_float agrees with decimal at large exponents" {
  let modes : Array[@lf_arith.RoundingMode] = [
    @lf_arith.RoundingMode::ToNearestEven,
    @lf_arith.RoundingMode::TowardZero,
    @lf_arith.RoundingMode::TowardPositive,
    @lf_arith.RoundingMode::TowardNegative,
    @lf_arith.RoundingMode::AwayFromZero,
  ]
  let coefficients : Array[BigInt] = [
    1N, 3N, 7N, 123456789N, 9999999999999999999999999999999999N,
  ]
  let exponents : Array[Int32] = [
    -330000000, -323000000, -320000000, -300000000, -30000000, -10000000, -1000000,
    1000000, 10000000, 30000000, 300000000, 320000000, 323000000, 330000000,
  ]
  for c in coefficients {
    for e in exponents {
      for negative in [false, true] {
        let signed = if negative { -c } else { c }
        let ieee = @decimal.Decimal::make(signed, e, 34)
        let gda = @decimal_gda.Decimal::make(signed, e, 34)
        for mode in modes {
          for precision in [24, 53, 113] {
            let expected = ieee.to_bin_float(precision~, mode~)
            let actual = gda.to_bin_float(precision~, mode~)
            inspect(actual.to_string() == expected.to_string(), content="true")
            inspect(
              actual.is_negative() == expected.is_negative(),
              content="true",
            )
          }
        }
      }
    }
  }
}
