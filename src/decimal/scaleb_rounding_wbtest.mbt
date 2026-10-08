///|
fn scaleb_case(value : String, count : String, ctx : DecimalContext) -> String {
  let (result, flags) = Decimal::from_string(value)
    .unwrap()
    .scaleb_ctx(Decimal::from_string(count).unwrap(), ctx)
  let mut text = result.to_string()
  if flags.inexact {
    text = text + " inexact"
  }
  if flags.overflow {
    text = text + " overflow"
  }
  if flags.subnormal {
    text = text + " subnormal"
  }
  if flags.clamped {
    text = text + " clamped"
  }
  text
}

///|
/// Overflow follows the rounding direction (IEEE 754-2019 7.4, #52): toward
/// zero gives the largest finite number, not an infinity.
test "decimal scaleb overflow honours the rounding direction" {
  let c64 = DecimalContext::decimal64()
  assert_eq(
    scaleb_case("9E+384", "1", c64.with_rounding(TowardZero)),
    "9.999999999999999E+384 inexact overflow",
  )
  assert_eq(
    scaleb_case("-9.99", "385", c64.with_rounding(TowardPositive)),
    "-9.999999999999999E+384 inexact overflow",
  )
  assert_eq(scaleb_case("9E+384", "1", c64), "inf inexact overflow")
}

///|
/// scaleb rounds and clamps its result like every other context operation
/// (#95): zero exponents are clamped into range, and a coefficient longer than
/// the precision is rounded once to the precision.
test "decimal scaleb rounds and clamps like other context results" {
  let c64 = DecimalContext::decimal64()
  assert_eq(scaleb_case("0", "700", c64), "0E+369 clamped")
  assert_eq(scaleb_case("-0E-390", "-700", c64), "-0E-398 clamped")
  assert_eq(
    scaleb_case("12345678901234567890", "0", c64),
    "1.234567890123457E+19 inexact",
  )
  assert_eq(
    scaleb_case("12345678901234567890", "-400", c64),
    "1.234567890123457E-381 inexact",
  )
  assert_eq(scaleb_case("123", "-400", c64), "1E-398 inexact subnormal")
  assert_eq(
    scaleb_case("1.000000000000000", "-383", c64),
    "1.000000000000000E-383",
  )
}
