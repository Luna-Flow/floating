///|
fn issue211_flags(flags : DecimalFlags) -> String {
  (if flags.inexact { "x" } else { "." }) +
  (if flags.rounded { "r" } else { "." }) +
  (if flags.overflow { "o" } else { "." }) +
  (if flags.underflow { "u" } else { "." }) +
  (if flags.subnormal { "s" } else { "." }) +
  (if flags.clamped { "c" } else { "." })
}

///|
/// General Decimal Arithmetic 1.70, *power*: an unrounded integer power has
/// the exponent that repeated multiplication gives (a negative power uses the
/// reciprocal). Expected values: Python `decimal` with the same parameters
/// (cross-check only; the specification is the authority). Context: precision
/// 16, `e_min = -383`, `e_max = 384`, `clamp`.
test "decimal_gda integer powers keep the repeated-multiplication exponent (#211)" {
  let ctx = DecimalContext::new(precision=16, e_min=-383, e_max=384, clamp=true).unwrap()
  let rows : Array[(String, String, String, String)] = [
    ("1.00", "2", "1.0000", "......"),
    ("1.00", "1", "1.00", "......"),
    ("1.00", "0", "1", "......"),
    ("1.00", "-2", "1", "......"),
    ("-1.0", "3", "-1.000", "......"),
    ("-1.0", "2", "1.00", "......"),
    ("-1.00", "5", "-1.0000000000", "......"),
    ("1E+5", "2", "1E+10", "......"),
    ("-1E+5", "5", "-1E+25", "......"),
    ("1E+10", "-3", "1E-30", "......"),
    ("1E-10", "-3", "1E+30", "......"),
    ("1E+2", "-2", "0.0001", "......"),
    ("1E-2", "3", "0.000001", "......"),
    ("0.50", "3", "0.125000", "......"),
    ("2.0", "2", "4.00", "......"),
    ("100", "2", "10000", "......"),
    ("10", "3", "1000", "......"),
    ("1.0000000000", "3", "1.000000000000000", ".r...."),
  ]
  for row in rows {
    let (operand, count, expected, expected_flags) = row
    let (value, flags) = Decimal::from_string(operand)
      .unwrap()
      .power_ctx(Decimal::from_string(count).unwrap(), ctx)
    assert_eq(
      (operand, count, value.to_string(), issue211_flags(flags)),
      (operand, count, expected, expected_flags),
    )
  }
}
