///|
// `to_binary` and the lower and upper bounds of `decimal_to_certified_ball`
// (#378): one division with a shift of `precision + 3 + ceil(log2 10^scale)`
// bits instead of two with `precision + 4 scale + 2`. The reference below is
// the previous implementation; the results must be bit for bit the same in every
// rounding mode, for positive and negative exponents, around the power caches
// (4096), for coefficients of the three decimal formats, and for the bounds
// built from one conversion.

///|
fn to_binary_reference(
  value : Decimal,
  precision : Int32,
  mode : @binary.BinaryRoundingMode,
) -> @binary.Binary {
  if value.exponent10 >= 0 {
    let magnitude = coeff_bigint(value.coefficient) * pow5(value.exponent10)
    return @binary.Binary::make(
      @binary.BinCoeff::from_bytes_be(magnitude.to_octets()),
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
  @binary.Binary::make(
    @binary.BinCoeff::from_bytes_be(q.to_octets()),
    -binary_shift,
    precision,
    negative=value.sign() == Sign::Negative,
    mode~,
  )
}

///|
fn to_binary_same(a : @binary.Binary, b : @binary.Binary) -> Bool {
  a.compare(b) == 0 &&
  a.is_sign_minus() == b.is_sign_minus() &&
  a.precision() == b.precision() &&
  a.exponent2() == b.exponent2() &&
  a.coefficient() == b.coefficient()
}

///|
test "to_binary equals the previous implementation in every mode" {
  let coefficients = [
    "1", "3", "7", "9999999", "1234567", "9007199254740993", "5000000000000000",
    "1000000000000000000000000000000001", "9999999999999999999999999999999999", "1000000000000000000000000000000000",
    "4503599627370497",
  ]
  let exponents = [
    0, 1, 2, 5, 22, 23, -1, -2, -5, -22, -23, -100, -383, -1000, -4095, -4096, -4097,
    -6176, 100, 4096, 4097, 6144,
  ]
  let precisions = [1, 2, 24, 53, 64, 113, 128, 200, 600]
  let modes = [
    @binary.BinaryRoundingMode::RoundTiesToEven,
    @binary.BinaryRoundingMode::RoundTiesToAway,
    @binary.BinaryRoundingMode::RoundTowardZero,
    @binary.BinaryRoundingMode::RoundTowardNegative,
    @binary.BinaryRoundingMode::RoundTowardPositive,
  ]
  let mut checked = 0
  for c in coefficients {
    for e in exponents {
      for negative in [false, true] {
        let text = (if negative { "-" } else { "" }) + c + "E" + e.to_string()
        let value = Decimal::from_string(text, precision=40).unwrap()
        for p in precisions {
          for mode in modes {
            let got = value.to_binary(precision=p, mode~)
            let want = to_binary_reference(value, p, mode)
            if !to_binary_same(got, want) {
              fail("\{text} p=\{p}: differs from the reference")
            }
            checked += 1
          }
        }
      }
    }
  }
  // A few huge exponents (the reference costs a 10^scale of millions of bits).
  for
    text in [
      "7E-20000", "-9999999999999999999999999999999999E-60000", "3E-150000",
    ] {
    let value = Decimal::from_string(text, precision=40).unwrap()
    for p in [53, 128] {
      for mode in modes {
        let got = value.to_binary(precision=p, mode~)
        let want = to_binary_reference(value, p, mode)
        if !to_binary_same(got, want) {
          fail("\{text} p=\{p}: differs from the reference")
        }
        checked += 1
      }
    }
  }
  assert_true(checked > 15000)
}

///|
test "decimal_to_certified_ball bounds are the two directed conversions" {
  for
    text in [
      "0.1", "-0.1", "3E-1000", "-7.5E-5000", "1.5E+3000", "123456789E-9", "9999999999999999999999999999999999E-6176",
      "-3E-30000", "5E+10", "0.0003",
    ] {
    let value = Decimal::from_string(text, precision=40).unwrap()
    for p in [53, 128, 200, 640] {
      let ball = decimal_to_certified_ball(value, p)
      let lower = value.to_binary(
        precision=p,
        mode=@binary.BinaryRoundingMode::RoundTowardNegative,
      )
      let upper = value.to_binary(
        precision=p,
        mode=@binary.BinaryRoundingMode::RoundTowardPositive,
      )
      assert_true(to_binary_same(ball.lower_bound(), lower), msg="\{text} \{p}")
      assert_true(to_binary_same(ball.upper_bound(), upper), msg="\{text} \{p}")
    }
  }
}

///|
/// The rounding attribute of a row's mode name for a value of the given sign:
/// the generated rows keep the names of the retired `@arithmetic` modes, and
/// `AwayFromZero` is the direction of the sign.
fn to_binary_mode(name : String, negative : Bool) -> @binary.BinaryRoundingMode {
  match name {
    "ToNearestEven" => @binary.BinaryRoundingMode::RoundTiesToEven
    "TowardZero" => @binary.BinaryRoundingMode::RoundTowardZero
    "AwayFromZero" =>
      if negative {
        @binary.BinaryRoundingMode::RoundTowardNegative
      } else {
        @binary.BinaryRoundingMode::RoundTowardPositive
      }
    "TowardNegative" => @binary.BinaryRoundingMode::RoundTowardNegative
    "TowardPositive" => @binary.BinaryRoundingMode::RoundTowardPositive
    _ => abort("unknown mode " + name)
  }
}

///|
test "to_binary at large exponents equals exact integer arithmetic (not the old code)" {
  // Expected values: tools/generate_decimal_to_bin_rows.py (Python integers):
  // exponents about +-2e5 and +-2e6, +-4096 and 4097 around the switch to
  // bounds of 5^e, every direction and sign, and values exactly representable
  // or exactly halfway between two numbers (the round-to-odd sticky bit; the
  // bounds of 5^e straddle them, so the exact conversion decides).
  let rows = to_binary_rows()
  for row in rows {
    let (text, precision, mode, coefficient, exponent) = row
    let value = Decimal::from_string(
      text,
      precision=Int32::max(40, text.length()),
    ).unwrap()
    let got = value.to_binary(
      precision~,
      mode=to_binary_mode(mode, value.sign() == Sign::Negative),
    )
    let expected_value = bigint_from_text(coefficient)
    let negative = expected_value < BigInt::from_int(0)
    let magnitude = abs_bigint(expected_value)
    let expected = @binary.Binary::make(
      @binary.BinCoeff::from_bytes_be(magnitude.to_octets()),
      exponent,
      magnitude.bit_length() + 2,
      negative~,
      mode=@binary.BinaryRoundingMode::RoundTiesToEven,
    )
    assert_true(
      got.compare(expected) == 0 && got.is_sign_minus() == negative,
      msg="\{text[:Int32::min(40, text.length())].to_owned()} p=\{precision} \{mode}",
    )
  }
  assert_true(rows.length() > 500)
}
