///|
fn issue168_flags_text(flags : DecimalFlags) -> String {
  (if flags.inexact { "x" } else { "." }) +
  (if flags.rounded { "r" } else { "." }) +
  (if flags.invalid_operation { "i" } else { "." }) +
  (if flags.division_by_zero { "z" } else { "." }) +
  (if flags.overflow { "o" } else { "." }) +
  (if flags.underflow { "u" } else { "." }) +
  (if flags.subnormal { "s" } else { "." }) +
  (if flags.clamped { "c" } else { "." })
}

///|
fn issue168_context(
  format : String,
  mode : DecimalRoundingMode,
) -> DecimalContext {
  let (precision, e_min, e_max) = match format {
    "decimal32" => (7, -95, 96)
    "decimal64" => (16, -383, 384)
    _ => (34, -6143, 6144)
  }
  DecimalContext::new(
    precision~,
    decimal_rounding=mode,
    e_min~,
    e_max~,
    clamp=true,
  ).unwrap()
}

///|
/// Integer powers whose exact value lies below the smallest subnormal
/// `10^Etiny` (General Decimal Arithmetic 1.70, *Rounding* and *Exceptional conditions* (Underflow, Subnormal)): the delivered result is the exact value rounded in the
/// rounding direction on the subnormal grid, never zero for every direction.
/// The nearest modes give `±10^Etiny` from half of it upwards
/// (`9.9E-200^2 = 9.801E-399` and `7.1E-200^2 = 5.041E-399` in decimal64) and
/// zero below (`7.07E-200^2`, `3.2E-200^2`, `9.9E-201^2`); Ceiling, Floor, Up
/// and ZeroFiveUp round a nonzero tiny value away from zero by its sign.
/// Covers `power_ctx`: the exact power-of-ten route (`10^-399`, `10^(-1E+30)`),
/// the large-exponent bound and the square-and-multiply terminal result.
/// Expected values: Python `fractions` (exact power) rounded by
/// `decimal.Context.divide` with the format's parameters; the oracle only
/// cross-checks the standard.
test "decimal integer powers below Etiny round in the rounding direction (#168)" {
  let rows : Array[
    (String, String, String, DecimalRoundingMode, String, String, String),
  ] = [
    ("power", "0.1", "400", HalfEven, "decimal64", "0E-398", "xr...usc"),
    ("power", "0.1", "400", HalfUp, "decimal64", "0E-398", "xr...usc"),
    ("power", "0.1", "400", HalfDown, "decimal64", "0E-398", "xr...usc"),
    ("power", "0.1", "400", Down, "decimal64", "0E-398", "xr...usc"),
    ("power", "0.1", "400", Ceiling, "decimal64", "1E-398", "xr...us."),
    ("power", "0.1", "400", Floor, "decimal64", "0E-398", "xr...usc"),
    ("power", "0.1", "400", Up, "decimal64", "1E-398", "xr...us."),
    ("power", "0.1", "400", ZeroFiveUp, "decimal64", "1E-398", "xr...us."),
    ("power", "1E-200", "2", HalfEven, "decimal64", "0E-398", "xr...usc"),
    ("power", "1E-200", "2", HalfUp, "decimal64", "0E-398", "xr...usc"),
    ("power", "1E-200", "2", HalfDown, "decimal64", "0E-398", "xr...usc"),
    ("power", "1E-200", "2", Down, "decimal64", "0E-398", "xr...usc"),
    ("power", "1E-200", "2", Ceiling, "decimal64", "1E-398", "xr...us."),
    ("power", "1E-200", "2", Floor, "decimal64", "0E-398", "xr...usc"),
    ("power", "1E-200", "2", Up, "decimal64", "1E-398", "xr...us."),
    ("power", "1E-200", "2", ZeroFiveUp, "decimal64", "1E-398", "xr...us."),
    ("power", "-0.1", "401", HalfEven, "decimal64", "-0E-398", "xr...usc"),
    ("power", "-0.1", "401", HalfUp, "decimal64", "-0E-398", "xr...usc"),
    ("power", "-0.1", "401", HalfDown, "decimal64", "-0E-398", "xr...usc"),
    ("power", "-0.1", "401", Down, "decimal64", "-0E-398", "xr...usc"),
    ("power", "-0.1", "401", Ceiling, "decimal64", "-0E-398", "xr...usc"),
    ("power", "-0.1", "401", Floor, "decimal64", "-1E-398", "xr...us."),
    ("power", "-0.1", "401", Up, "decimal64", "-1E-398", "xr...us."),
    ("power", "-0.1", "401", ZeroFiveUp, "decimal64", "-1E-398", "xr...us."),
    ("power", "10", "-399", HalfEven, "decimal64", "0E-398", "xr...usc"),
    ("power", "10", "-399", HalfUp, "decimal64", "0E-398", "xr...usc"),
    ("power", "10", "-399", HalfDown, "decimal64", "0E-398", "xr...usc"),
    ("power", "10", "-399", Down, "decimal64", "0E-398", "xr...usc"),
    ("power", "10", "-399", Ceiling, "decimal64", "1E-398", "xr...us."),
    ("power", "10", "-399", Floor, "decimal64", "0E-398", "xr...usc"),
    ("power", "10", "-399", Up, "decimal64", "1E-398", "xr...us."),
    ("power", "10", "-399", ZeroFiveUp, "decimal64", "1E-398", "xr...us."),
    ("power", "-10", "-399", HalfEven, "decimal64", "-0E-398", "xr...usc"),
    ("power", "-10", "-399", HalfUp, "decimal64", "-0E-398", "xr...usc"),
    ("power", "-10", "-399", HalfDown, "decimal64", "-0E-398", "xr...usc"),
    ("power", "-10", "-399", Down, "decimal64", "-0E-398", "xr...usc"),
    ("power", "-10", "-399", Ceiling, "decimal64", "-0E-398", "xr...usc"),
    ("power", "-10", "-399", Floor, "decimal64", "-1E-398", "xr...us."),
    ("power", "-10", "-399", Up, "decimal64", "-1E-398", "xr...us."),
    ("power", "-10", "-399", ZeroFiveUp, "decimal64", "-1E-398", "xr...us."),
    ("power", "10", "-1E+30", HalfEven, "decimal64", "0E-398", "xr...usc"),
    ("power", "10", "-1E+30", HalfUp, "decimal64", "0E-398", "xr...usc"),
    ("power", "10", "-1E+30", HalfDown, "decimal64", "0E-398", "xr...usc"),
    ("power", "10", "-1E+30", Down, "decimal64", "0E-398", "xr...usc"),
    ("power", "10", "-1E+30", Ceiling, "decimal64", "1E-398", "xr...us."),
    ("power", "10", "-1E+30", Floor, "decimal64", "0E-398", "xr...usc"),
    ("power", "10", "-1E+30", Up, "decimal64", "1E-398", "xr...us."),
    ("power", "10", "-1E+30", ZeroFiveUp, "decimal64", "1E-398", "xr...us."),
    ("power", "-0.3", "7001", HalfEven, "decimal32", "-0E-101", "xr...usc"),
    ("power", "-0.3", "7001", Ceiling, "decimal32", "-0E-101", "xr...usc"),
    ("power", "-0.3", "7001", Floor, "decimal32", "-1E-101", "xr...us."),
    ("power", "-0.3", "7001", Up, "decimal32", "-1E-101", "xr...us."),
    (
      "power",
      "-0.3",
      "7001",
      HalfEven,
      "decimal128",
      "-2.117894352864269461773836445056140E-3661",
      "xr......",
    ),
    (
      "power",
      "-0.3",
      "7001",
      Ceiling,
      "decimal128",
      "-2.117894352864269461773836445056139E-3661",
      "xr......",
    ),
    (
      "power",
      "-0.3",
      "7001",
      Floor,
      "decimal128",
      "-2.117894352864269461773836445056140E-3661",
      "xr......",
    ),
    (
      "power",
      "-0.3",
      "7001",
      Up,
      "decimal128",
      "-2.117894352864269461773836445056140E-3661",
      "xr......",
    ),
  ]
  for row in rows {
    let (op, operand, count, mode, format, expected, expected_flags) = row
    let context = issue168_context(format, mode)
    let base = Decimal::from_string(operand).unwrap()
    guard op == "power" else { fail("unexpected operation \{op}") }
    let (value, flags) = base.power_ctx(
      Decimal::from_string(count).unwrap(),
      context,
    )
    assert_eq(
      (op, operand, count, value.to_string(), issue168_flags_text(flags)),
      (op, operand, count, expected, expected_flags),
    )
  }
}
