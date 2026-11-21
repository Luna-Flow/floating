///|
/// A quotient inside the working range whose exponent difference is above `Int`
/// (the dividend at the top of the stored range, a divisor with a negative
/// exponent) aborted: the preferred exponent wrapped. Oracle (level A): Python
/// `decimal` (libmpdec), `Context(prec=P, rounding=ROUND_HALF_EVEN,
/// Emax=2147483646, Emin=-2147483645 + P - 1, clamp=0)`, operands read with
/// `create_decimal` (rounded to P digits as `from_string(text, precision=P)`);
/// written out.
test "plain division with an exponent difference above Int" {
  let rows = [
    (3, "1E+2147483646", "-2.50", "-4E+2147483645"),
    (16, "1E+2147483646", "-2.50", "-4E+2147483645"),
    (
      16, "1E+2147483646", "123456789.123456789", "8.100000065610000E+2147483637",
    ),
    (
      16, "9.99E+2147483646", "123456789.123456789", "8.091900065544390E+2147483638",
    ),
    (
      16, "5E+2147483645", "123456789.123456789", "4.050000032805000E+2147483637",
    ),
    (
      16, "-7E+2147483644", "123456789.123456789", "-5.670000045927000E+2147483636",
    ),
    (34, "1E+2147483646", "-2.50", "-4E+2147483645"),
    (
      34, "1E+2147483646", "123456789.123456789", "8.100000065610000605151005498774150E+2147483637",
    ),
    (
      34, "9.99E+2147483646", "123456789.123456789", "8.091900065544390604545854493275376E+2147483638",
    ),
    (
      34, "5E+2147483645", "123456789.123456789", "4.050000032805000302575502749387075E+2147483637",
    ),
    (
      34, "1E+2147483640", "123456789.123456789", "8.100000065610000605151005498774150E+2147483631",
    ),
    (
      34, "25E+2147483640", "123456789.123456789", "2.025000016402500151287751374693538E+2147483633",
    ),
    (
      34, "-7E+2147483644", "123456789.123456789", "-5.670000045927000423605703849141905E+2147483636",
    ),
  ]
  for row in rows {
    let (precision, a_text, b_text, expected) = row
    let a = Decimal::from_string(a_text, precision~).unwrap()
    let b = Decimal::from_string(b_text, precision~).unwrap()
    let label = "p=\{precision} \{a_text} / \{b_text}"
    assert_eq((label, (a / b).to_string()), (label, expected))
  }
}
