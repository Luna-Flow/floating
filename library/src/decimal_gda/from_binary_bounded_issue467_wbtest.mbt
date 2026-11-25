// Issue 467: the plain `Decimal::from_binary` formed the whole expansion
// `c * 5^k` (or `c << e2`) before it rounded to `precision` digits, so its cost
// grew with the binary exponent. The bounded form rounds the surrogate digits of
// `Binary::to_decimal_string_ctx` once; the result must be the one of the
// expansion: same coefficient, exponent, sign and precision field.

///|
/// The exact expansion, as `from_binary` computed it before the bounded form.
fn old_from_binary(x : @binary.Binary, precision : Int32) -> Decimal {
  let coefficient = BigInt::from_octets(x.coefficient().to_bytes_be())
  let signed = if x.is_sign_minus() { -coefficient } else { coefficient }
  if x.exponent2() >= 0 {
    decimal_from_integer_parts(signed << x.exponent2(), 0, precision)
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
    )
  }
}

///|
fn same_decimal(a : Decimal, b : Decimal) -> Bool {
  a.coefficient() == b.coefficient() &&
  a.exponent10() == b.exponent10() &&
  a.is_signed() == b.is_signed() &&
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
// oracle: E
// source: old_from_binary: the exact expansion c * 5^k or c << e2 through BigInt, then decimal_from_integer_parts
// shares: decimal_from_integer_parts (the rounding of the integer) and the coefficient comparison
// underneath: level A: the rows of from_binary_rows_wbtest.mbt (CPython decimal) check Decimal::from_binary_raw, which takes the exact-expansion route for small exponents, and the bounded form for a subset of the bases and shifts of this block: 8 of its 15 bases (1, 3, 5, 7, 10, 255, 12345, the mantissa of 0.1) and 12 of its 22 shifts (-6000, -3000, -2049, -1100, -1025, -1024, 1024, 1025, 1100, 2049, 3000, 6000), half even, one precision of 1 to 400 per pair; the other bases and shifts of the block have only the level E comparison
test "issue 467: the bounded form gives the result of the exact expansion" {
  for x in binary_rows() {
    for precision in [1, 2, 3, 5, 9, 17, 34, 100, 400] {
      let expected = old_from_binary(x, precision)
      inspect(
        same_decimal(
          decimal_from_binary_surrogate(
            x,
            precision,
            DecimalRoundingMode::HalfEven,
          ),
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
// oracle: A, S
// source: written out from CPython `decimal`: 3 * 2^e at 34 digits half even for e = -100000000, -1000000, 1000000, 100000000, 1000000000, computed at 120 and at 200 digits (both agree) as `Decimal(3) * Decimal(2) ** e`; the sign and the digit count are properties (S)
// shares: Decimal::to_string (prints the result)
test "issue 467: the cost does not depend on the binary exponent" {
  let wide = @binary.BinaryContext::new(precision=53)
  let three = @binary.Binary::from_int(3, precision=53)
  // Before the bounded form these took minutes (quadratic in the exponent).
  let rows : Array[(Int32, String)] = [
    (-100000000, "8.141850716753078023412762027748650E-30103000"),
    (-1000000, "3.030102177594090674109591841039864E-301030"),
    (1000000, "2.970196868788769475209377084890571E+301030"),
    (100000000, "1.105399781094137628962727717295267E+30103000"),
    (1000000000, "1.383892800350720817934835766311195E+301029996"),
  ]
  for row in rows {
    let (exponent, text) = row
    let x = three.scaleb_ctx(@binary.Binary::from_int(exponent), wide).0
    let value = Decimal::from_binary(x, precision=34)
    assert_eq(value.to_string(), text)
    inspect(value.coefficient().to_string().length() <= 34, content="true")
    inspect(value.is_signed(), content="false")
  }
}
