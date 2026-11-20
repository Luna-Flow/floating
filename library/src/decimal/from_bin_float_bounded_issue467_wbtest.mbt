// Issue 467: the plain `Decimal::from_bin_float` formed the whole expansion
// `c * 5^k` (or `c << e2`) before it rounded to `precision` digits, so its cost
// grew with the binary exponent. The bounded form rounds the surrogate digits of
// `BinFloat::to_decimal_string_ctx` once; the result must be the one of the
// expansion: same coefficient, exponent, sign and precision field.

///|
/// The exact expansion, as `from_bin_float` computed it before the bounded form.
fn old_from_bin_float(x : @bin_float.BinFloat, precision : Int32) -> Decimal {
  let coefficient = BigInt::from_octets(x.coefficient().to_bytes_be())
  let signed = if x.is_negative() { -coefficient } else { coefficient }
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
      if x.is_negative() {
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
  a.is_negative() == b.is_negative() &&
  a.precision() == b.precision() &&
  a.is_zero() == b.is_zero()
}

///|
fn bin_float_rows() -> Array[@bin_float.BinFloat] {
  let wide = @bin_float.BinaryContext::unbounded(53)
  let bases : Array[@bin_float.BinFloat] = [
    @bin_float.BinFloat::from_int(1, precision=53),
    @bin_float.BinFloat::from_int(3, precision=53),
    @bin_float.BinFloat::from_int(5, precision=53),
    @bin_float.BinFloat::from_int(7, precision=53),
    @bin_float.BinFloat::from_int(10, precision=53),
    @bin_float.BinFloat::from_int(100, precision=53),
    @bin_float.BinFloat::from_int(255, precision=53),
    @bin_float.BinFloat::from_int(12345, precision=53),
    @bin_float.BinFloat::from_double(4503599627370497.0, precision=53),
    @bin_float.BinFloat::from_double(0.1, precision=53),
    @bin_float.BinFloat::from_double(1.0 / 3.0, precision=53),
    @bin_float.BinFloat::from_double(1.0e22, precision=53),
    @bin_float.BinFloat::from_double(123456789.123, precision=53),
    @bin_float.BinFloat::from_double(0.5, precision=53),
    @bin_float.BinFloat::from_double(9007199254740991.0, precision=53),
  ]
  let shifts : Array[Int32] = [
    -6000, -5000, -3000, -2049, -1100, -1025, -1024, -1000, -100, -60, -1, 0, 1,
    60, 100, 1000, 1024, 1025, 1100, 2049, 3000, 5000,
  ]
  let rows = []
  for base in bases {
    for shift in shifts {
      let value = base.scaleb_ctx(shift, wide).0
      rows.push(value)
      rows.push(value.neg())
    }
  }
  rows
}

///|
test "issue 467: the bounded form gives the result of the exact expansion" {
  for x in bin_float_rows() {
    for precision in [1, 2, 3, 5, 9, 17, 34, 100, 400] {
      let expected = old_from_bin_float(x, precision)
      inspect(
        same_decimal(decimal_from_bin_float_surrogate(x, precision), expected),
        content="true",
      )
      inspect(
        same_decimal(Decimal::from_bin_float(x, precision~), expected),
        content="true",
      )
    }
  }
}

///|
test "issue 467: the cost does not depend on the binary exponent" {
  let wide = @bin_float.BinaryContext::unbounded(53)
  let three = @bin_float.BinFloat::from_int(3, precision=53)
  // Before the bounded form these took minutes (quadratic in the exponent).
  for exponent in [-100000000, -1000000, 1000000, 100000000, 1000000000] {
    let x = three.scaleb_ctx(exponent, wide).0
    let value = Decimal::from_bin_float(x, precision=34)
    inspect(value.coefficient().to_string().length() <= 34, content="true")
    inspect(value.is_negative(), content="false")
  }
}
