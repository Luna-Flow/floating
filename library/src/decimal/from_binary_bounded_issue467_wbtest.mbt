// Issue 467: the plain `Decimal::from_binary` formed the whole expansion
// `c * 5^k` (or `c << e2`) before it rounded to `precision` digits, so its cost
// grew with the binary exponent. The bounded form rounds the surrogate digits of
// `Binary::to_decimal_string_ctx` once; the result must be the one of the
// expansion: same coefficient, exponent, sign and precision field.

///|
/// The exact expansion, as `from_binary` computed it before the bounded form.
fn old_from_binary(
  x : @binary.Binary,
  precision : Int32,
  mode~ : DecimalRound = DecimalRound::HalfEven,
) -> Decimal {
  let coefficient = BigInt::from_octets(x.coefficient().to_bytes_be())
  let signed = if x.is_sign_minus() { -coefficient } else { coefficient }
  if x.exponent2() >= 0 {
    decimal_from_integer_parts(signed << x.exponent2(), 0, precision, mode~)
  } else {
    let k = -x.exponent2()
    let mut magnitude = coeff_from_bigint(abs_bigint(signed * pow5(k)))
    let mut exponent = -k
    while exponent < 0 {
      let (quotient, remainder) = dec_coeff_div_rem_by_unit_repr(magnitude, 10)
      if remainder != 0 {
        break
      }
      magnitude = quotient
      exponent = exponent + 1
    }
    decimal_from_integer_parts(
      if x.is_sign_minus() {
        -coeff_bigint(magnitude)
      } else {
        coeff_bigint(magnitude)
      },
      exponent,
      precision,
      mode~,
    )
  }
}

///|
fn same_decimal(a : Decimal, b : Decimal) -> Bool {
  a.coefficient() == b.coefficient() &&
  a.exponent10() == b.exponent10() &&
  a.is_sign_minus() == b.is_sign_minus() &&
  a.precision() == b.precision() &&
  a.is_zero() == b.is_zero()
}

///|
fn binary_rows() -> Array[@binary.Binary] {
  let wide = @binary.BinaryContext::new(precision=53)
  let bases : Array[@binary.Binary] = [
    @binary.Binary::from_int(1, precision=53),
    @binary.Binary::from_int(3, precision=53),
    @binary.Binary::from_int(5, precision=53),
    @binary.Binary::from_int(7, precision=53),
    @binary.Binary::from_int(10, precision=53),
    @binary.Binary::from_int(100, precision=53),
    @binary.Binary::from_int(255, precision=53),
    @binary.Binary::from_int(12345, precision=53),
    @binary.Binary::from_double(4503599627370497.0, precision=53),
    @binary.Binary::from_double(0.1, precision=53),
    @binary.Binary::from_double(1.0 / 3.0, precision=53),
    @binary.Binary::from_double(1.0e22, precision=53),
    @binary.Binary::from_double(123456789.123, precision=53),
    @binary.Binary::from_double(0.5, precision=53),
    @binary.Binary::from_double(9007199254740991.0, precision=53),
  ]
  let shifts : Array[Int32] = [
    -6000, -5000, -3000, -2049, -1100, -1025, -1024, -1000, -100, -60, -1, 0, 1,
    60, 100, 1000, 1024, 1025, 1100, 2049, 3000, 5000,
  ]
  let rows = []
  for base in bases {
    for shift in shifts {
      let value = base.scaleb_ctx(@binary.Binary::from_int(shift), wide).0
      rows.push(value)
      rows.push(value.neg())
    }
  }
  rows
}

///|
test "issue 467: the bounded form gives the result of the exact expansion" {
  for x in binary_rows() {
    for precision in [1, 2, 3, 5, 9, 17, 34, 100, 400] {
      let expected = old_from_binary(x, precision)
      inspect(
        same_decimal(
          decimal_from_binary_surrogate(x, precision, DecimalRound::HalfEven),
          expected,
        ),
        content="true",
      )
      inspect(
        same_decimal(Decimal::from_binary(x, precision~), expected),
        content="true",
      )
    }
  }
}

///|
test "issue 467: the cost does not depend on the binary exponent" {
  let wide = @binary.BinaryContext::new(precision=53)
  let three = @binary.Binary::from_int(3, precision=53)
  // Before the bounded form these took minutes (quadratic in the exponent).
  for exponent in [-100000000, -1000000, 1000000, 100000000, 1000000000] {
    let x = three.scaleb_ctx(@binary.Binary::from_int(exponent), wide).0
    let value = Decimal::from_binary(x, precision=34)
    inspect(value.coefficient().to_string().length() <= 34, content="true")
    inspect(value.is_sign_minus(), content="false")
  }
}

///|
/// The rounding attribute is the one of the radix of the result: the bounded form
/// and the exact expansion agree in each of the five `DecimalRoundingMode`s, for
/// both signs, exact values and ties included (the surrogate keeps a sticky digit).
test "issue 467: from_binary rounds in every DecimalRoundingMode like the exact expansion" {
  let modes = [
    DecimalRoundingMode::RoundTiesToEven,
    DecimalRoundingMode::RoundTiesToAway,
    DecimalRoundingMode::RoundTowardZero,
    DecimalRoundingMode::RoundTowardPositive,
    DecimalRoundingMode::RoundTowardNegative,
  ]
  for x in binary_rows() {
    for precision in [1, 2, 3, 5, 9, 17, 34] {
      for mode in modes {
        let expected = old_from_binary(x, precision, mode=mode.round())
        inspect(
          same_decimal(Decimal::from_binary(x, precision~, mode~), expected),
          content="true",
        )
        inspect(
          same_decimal(
            Decimal::from_binary(x.neg(), precision~, mode~),
            old_from_binary(x.neg(), precision, mode=mode.round()),
          ),
          content="true",
        )
      }
    }
  }
  // 0.5 at one digit is a tie: even gives 0.5 exactly (one digit), so use 2.5 and 3.5
  let tie = @binary.Binary::from_double(2.5, precision=53)
  inspect(Decimal::from_binary(tie, precision=1).to_string(), content="2")
  inspect(
    Decimal::from_binary(
      tie,
      precision=1,
      mode=DecimalRoundingMode::RoundTiesToAway,
    ).to_string(),
    content="3",
  )
  inspect(
    Decimal::from_binary(
      tie,
      precision=1,
      mode=DecimalRoundingMode::RoundTowardPositive,
    ).to_string(),
    content="3",
  )
  inspect(
    Decimal::from_binary(
      tie,
      precision=1,
      mode=DecimalRoundingMode::RoundTowardZero,
    ).to_string(),
    content="2",
  )
}

///|
/// `from_binary` on operands that take the bounded (surrogate) route, with the
/// part discarded by the rounding exactly zero, one unit below half, exactly half and
/// one unit above half, an even and an odd last kept digit, both signs, all five
/// modes: the value is `T * 10^1100` with `T = D * 1000 + tail`, exact in a binary
/// float of 3000 bits (`T * 5^1100 * 2^1100`), and the exact expansion decides.
/// Only a positive binary exponent is built this way. For a negative one the
/// expansion of a dyadic value `c * 2^-n` has about `0.7 n` digits, so a precision
/// that leaves exactly one discarded digit (the 5 that ends it, the exact half)
/// is about `0.7 n`, which breaks the bound `2 p <= n` of the bounded route: an
/// exact half cannot be constructed there, and the arbitrary rows above cover the
/// negative operands of that route.
test "from_binary: the bounded route at the rounding boundaries in every mode" {
  let modes = [
    DecimalRoundingMode::RoundTiesToEven,
    DecimalRoundingMode::RoundTiesToAway,
    DecimalRoundingMode::RoundTowardZero,
    DecimalRoundingMode::RoundTowardPositive,
    DecimalRoundingMode::RoundTowardNegative,
  ]
  let five_1100 = pow5(1100)
  for
    kept in [
      ("1", 1),
      ("2", 1),
      ("12", 2),
      ("13", 2),
      ("12345", 5),
      ("12346", 5),
      ("99999999999999999", 17),
      ("1234567890123456789012345678901234", 34),
      ("1234567890123456789012345678901235", 34),
    ] {
    let (digits, precision) = kept
    for tail in [0, 499, 500, 501] {
      let t = bigint_from_text(digits) * BigInt::from_int(1000) +
        BigInt::from_int(tail)
      let coefficient = @binary.BinCoeff::from_bytes_be(
        (t * five_1100).to_octets(),
      )
      for negative in [false, true] {
        let x = @binary.Binary::make(
          coefficient,
          1100,
          3000,
          negative~,
          mode=@binary.BinaryRoundingMode::RoundTiesToEven,
        )
        assert_true(decimal_from_binary_is_bounded(x, precision))
        for mode in modes {
          let expected = old_from_binary(x, precision, mode=mode.round())
          assert_true(
            same_decimal(Decimal::from_binary(x, precision~, mode~), expected),
            msg="\{digits} tail \{tail} negative \{negative} p=\{precision}",
          )
        }
      }
    }
  }
}
