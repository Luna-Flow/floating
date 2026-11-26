///|
fn issue168_flags_text(flags : DecimalFlags) -> String {
  (if flags.inexact { "x" } else { "." }) +
  (if flags.invalid_operation { "i" } else { "." }) +
  (if flags.division_by_zero { "z" } else { "." }) +
  (if flags.overflow { "o" } else { "." }) +
  (if flags.underflow { "u" } else { "." })
}

///|
fn issue168_int(text : String) -> Int32 {
  let mut value = 0
  let mut negative = false
  for ch in text {
    if ch == '-' {
      negative = true
    } else {
      value = value * 10 + (ch.to_int() - '0'.to_int())
    }
  }
  if negative {
    -value
  } else {
    value
  }
}

///|
fn issue168_context(format : String, mode : DecimalRound) -> DecimalContext {
  let (precision, e_max) = match format {
    "decimal32" => (7, 96)
    "decimal64" => (16, 384)
    _ => (34, 6144)
  }
  DecimalContext::new(precision~, e_max~).with_round(mode)
}

///|
/// Integer powers whose exact value lies below the smallest subnormal
/// `10^Etiny` (IEEE 754-2019 §4.3 (rounding-direction attributes) and §7.5 (underflow)): the delivered result is the exact value rounded in the
/// rounding direction on the subnormal grid, never zero for every direction.
/// The nearest modes give `±10^Etiny` from half of it upwards
/// (`9.9E-200^2 = 9.801E-399` and `7.1E-200^2 = 5.041E-399` in decimal64) and
/// zero below (`7.07E-200^2`, `3.2E-200^2`, `9.9E-201^2`); Ceiling, Floor, Up
/// and ZeroFiveUp round a nonzero tiny value away from zero by its sign.
/// Covers `pown_ctx`, `power_ctx` and `exp10_ctx`: the exact power-of-ten route (`10^-399`, `10^(-1E+30)`),
/// the large-exponent bound and the square-and-multiply terminal result.
/// Expected values: Python `fractions` (exact power) rounded by
/// `decimal.Context.divide` with the format's parameters; the oracle only
/// cross-checks the standard.

///|
// oracle: A
// source: 116 rows of which 108 were re-derived with Python fractions (the exact power) rounded by decimal.Context.divide with the parameters of decimal32, decimal64 and decimal128 and each of the eight modes (library-ran: no): all 108 agree; the 8 rows with exponents beyond 10^7 were not re-run; IEEE Std 754-2019 4.3 and 7.5: a value below the smallest subnormal rounds on the subnormal grid in the direction, never to zero in every direction
// shares: issue168_context builds the context with DecimalContext::new and with_round and issue168_int reads the exponent; Decimal::from_string reads the operands; pown_ctx, pow_ctx and exp10_ctx are the code under test; issue168_flags_text prints
test "decimal integer powers below Etiny round in the rounding direction (#168)" {
  let rows : Array[
    (String, String, String, DecimalRound, String, String, String),
  ] = [
    ("pown", "9.9E-200", "2", HalfEven, "decimal64", "1E-398", "x...u"),
    ("pown", "9.9E-200", "2", HalfUp, "decimal64", "1E-398", "x...u"),
    ("pown", "9.9E-200", "2", HalfDown, "decimal64", "1E-398", "x...u"),
    ("pown", "9.9E-200", "2", Down, "decimal64", "0E-398", "x...u"),
    ("pown", "9.9E-200", "2", Ceiling, "decimal64", "1E-398", "x...u"),
    ("pown", "9.9E-200", "2", Floor, "decimal64", "0E-398", "x...u"),
    ("pown", "9.9E-200", "2", Up, "decimal64", "1E-398", "x...u"),
    ("pown", "9.9E-200", "2", ZeroFiveUp, "decimal64", "1E-398", "x...u"),
    ("pown", "9.9E-201", "2", HalfEven, "decimal64", "0E-398", "x...u"),
    ("pown", "9.9E-201", "2", HalfUp, "decimal64", "0E-398", "x...u"),
    ("pown", "9.9E-201", "2", HalfDown, "decimal64", "0E-398", "x...u"),
    ("pown", "9.9E-201", "2", Down, "decimal64", "0E-398", "x...u"),
    ("pown", "9.9E-201", "2", Ceiling, "decimal64", "1E-398", "x...u"),
    ("pown", "9.9E-201", "2", Floor, "decimal64", "0E-398", "x...u"),
    ("pown", "9.9E-201", "2", Up, "decimal64", "1E-398", "x...u"),
    ("pown", "9.9E-201", "2", ZeroFiveUp, "decimal64", "1E-398", "x...u"),
    ("pown", "3.2E-200", "2", HalfEven, "decimal64", "0E-398", "x...u"),
    ("pown", "3.2E-200", "2", HalfUp, "decimal64", "0E-398", "x...u"),
    ("pown", "3.2E-200", "2", HalfDown, "decimal64", "0E-398", "x...u"),
    ("pown", "3.2E-200", "2", Down, "decimal64", "0E-398", "x...u"),
    ("pown", "3.2E-200", "2", Ceiling, "decimal64", "1E-398", "x...u"),
    ("pown", "3.2E-200", "2", Floor, "decimal64", "0E-398", "x...u"),
    ("pown", "3.2E-200", "2", Up, "decimal64", "1E-398", "x...u"),
    ("pown", "3.2E-200", "2", ZeroFiveUp, "decimal64", "1E-398", "x...u"),
    ("pown", "7.1E-200", "2", HalfEven, "decimal64", "1E-398", "x...u"),
    ("pown", "7.1E-200", "2", HalfUp, "decimal64", "1E-398", "x...u"),
    ("pown", "7.1E-200", "2", HalfDown, "decimal64", "1E-398", "x...u"),
    ("pown", "7.1E-200", "2", Down, "decimal64", "0E-398", "x...u"),
    ("pown", "7.1E-200", "2", Ceiling, "decimal64", "1E-398", "x...u"),
    ("pown", "7.1E-200", "2", Floor, "decimal64", "0E-398", "x...u"),
    ("pown", "7.1E-200", "2", Up, "decimal64", "1E-398", "x...u"),
    ("pown", "7.1E-200", "2", ZeroFiveUp, "decimal64", "1E-398", "x...u"),
    ("pown", "7.07E-200", "2", HalfEven, "decimal64", "0E-398", "x...u"),
    ("pown", "7.07E-200", "2", HalfUp, "decimal64", "0E-398", "x...u"),
    ("pown", "7.07E-200", "2", HalfDown, "decimal64", "0E-398", "x...u"),
    ("pown", "7.07E-200", "2", Down, "decimal64", "0E-398", "x...u"),
    ("pown", "7.07E-200", "2", Ceiling, "decimal64", "1E-398", "x...u"),
    ("pown", "7.07E-200", "2", Floor, "decimal64", "0E-398", "x...u"),
    ("pown", "7.07E-200", "2", Up, "decimal64", "1E-398", "x...u"),
    ("pown", "7.07E-200", "2", ZeroFiveUp, "decimal64", "1E-398", "x...u"),
    ("pown", "-0.1", "401", HalfEven, "decimal64", "-0E-398", "x...u"),
    ("pown", "-0.1", "401", HalfUp, "decimal64", "-0E-398", "x...u"),
    ("pown", "-0.1", "401", HalfDown, "decimal64", "-0E-398", "x...u"),
    ("pown", "-0.1", "401", Down, "decimal64", "-0E-398", "x...u"),
    ("pown", "-0.1", "401", Ceiling, "decimal64", "-0E-398", "x...u"),
    ("pown", "-0.1", "401", Floor, "decimal64", "-1E-398", "x...u"),
    ("pown", "-0.1", "401", Up, "decimal64", "-1E-398", "x...u"),
    ("pown", "-0.1", "401", ZeroFiveUp, "decimal64", "-1E-398", "x...u"),
    ("pown", "0.1", "1001", HalfEven, "decimal64", "0E-398", "x...u"),
    ("pown", "0.1", "1001", HalfUp, "decimal64", "0E-398", "x...u"),
    ("pown", "0.1", "1001", HalfDown, "decimal64", "0E-398", "x...u"),
    ("pown", "0.1", "1001", Down, "decimal64", "0E-398", "x...u"),
    ("pown", "0.1", "1001", Ceiling, "decimal64", "1E-398", "x...u"),
    ("pown", "0.1", "1001", Floor, "decimal64", "0E-398", "x...u"),
    ("pown", "0.1", "1001", Up, "decimal64", "1E-398", "x...u"),
    ("pown", "0.1", "1001", ZeroFiveUp, "decimal64", "1E-398", "x...u"),
    ("pown", "-1E-10", "41", HalfEven, "decimal64", "-0E-398", "x...u"),
    ("pown", "-1E-10", "41", HalfUp, "decimal64", "-0E-398", "x...u"),
    ("pown", "-1E-10", "41", HalfDown, "decimal64", "-0E-398", "x...u"),
    ("pown", "-1E-10", "41", Down, "decimal64", "-0E-398", "x...u"),
    ("pown", "-1E-10", "41", Ceiling, "decimal64", "-0E-398", "x...u"),
    ("pown", "-1E-10", "41", Floor, "decimal64", "-1E-398", "x...u"),
    ("pown", "-1E-10", "41", Up, "decimal64", "-1E-398", "x...u"),
    ("pown", "-1E-10", "41", ZeroFiveUp, "decimal64", "-1E-398", "x...u"),
    ("power", "0.1", "400", HalfEven, "decimal64", "0E-398", "x...u"),
    ("power", "0.1", "400", HalfUp, "decimal64", "0E-398", "x...u"),
    ("power", "0.1", "400", HalfDown, "decimal64", "0E-398", "x...u"),
    ("power", "0.1", "400", Down, "decimal64", "0E-398", "x...u"),
    ("power", "0.1", "400", Ceiling, "decimal64", "1E-398", "x...u"),
    ("power", "0.1", "400", Floor, "decimal64", "0E-398", "x...u"),
    ("power", "0.1", "400", Up, "decimal64", "1E-398", "x...u"),
    ("power", "0.1", "400", ZeroFiveUp, "decimal64", "1E-398", "x...u"),
    ("power", "1E-200", "2", HalfEven, "decimal64", "0E-398", "x...u"),
    ("power", "1E-200", "2", HalfUp, "decimal64", "0E-398", "x...u"),
    ("power", "1E-200", "2", HalfDown, "decimal64", "0E-398", "x...u"),
    ("power", "1E-200", "2", Down, "decimal64", "0E-398", "x...u"),
    ("power", "1E-200", "2", Ceiling, "decimal64", "1E-398", "x...u"),
    ("power", "1E-200", "2", Floor, "decimal64", "0E-398", "x...u"),
    ("power", "1E-200", "2", Up, "decimal64", "1E-398", "x...u"),
    ("power", "1E-200", "2", ZeroFiveUp, "decimal64", "1E-398", "x...u"),
    ("power", "-0.1", "401", HalfEven, "decimal64", "-0E-398", "x...u"),
    ("power", "-0.1", "401", HalfUp, "decimal64", "-0E-398", "x...u"),
    ("power", "-0.1", "401", HalfDown, "decimal64", "-0E-398", "x...u"),
    ("power", "-0.1", "401", Down, "decimal64", "-0E-398", "x...u"),
    ("power", "-0.1", "401", Ceiling, "decimal64", "-0E-398", "x...u"),
    ("power", "-0.1", "401", Floor, "decimal64", "-1E-398", "x...u"),
    ("power", "-0.1", "401", Up, "decimal64", "-1E-398", "x...u"),
    ("power", "-0.1", "401", ZeroFiveUp, "decimal64", "-1E-398", "x...u"),
    ("power", "10", "-399", HalfEven, "decimal64", "0E-398", "x...u"),
    ("power", "10", "-399", HalfUp, "decimal64", "0E-398", "x...u"),
    ("power", "10", "-399", HalfDown, "decimal64", "0E-398", "x...u"),
    ("power", "10", "-399", Down, "decimal64", "0E-398", "x...u"),
    ("power", "10", "-399", Ceiling, "decimal64", "1E-398", "x...u"),
    ("power", "10", "-399", Floor, "decimal64", "0E-398", "x...u"),
    ("power", "10", "-399", Up, "decimal64", "1E-398", "x...u"),
    ("power", "10", "-399", ZeroFiveUp, "decimal64", "1E-398", "x...u"),
    ("power", "-10", "-399", HalfEven, "decimal64", "-0E-398", "x...u"),
    ("power", "-10", "-399", HalfUp, "decimal64", "-0E-398", "x...u"),
    ("power", "-10", "-399", HalfDown, "decimal64", "-0E-398", "x...u"),
    ("power", "-10", "-399", Down, "decimal64", "-0E-398", "x...u"),
    ("power", "-10", "-399", Ceiling, "decimal64", "-0E-398", "x...u"),
    ("power", "-10", "-399", Floor, "decimal64", "-1E-398", "x...u"),
    ("power", "-10", "-399", Up, "decimal64", "-1E-398", "x...u"),
    ("power", "-10", "-399", ZeroFiveUp, "decimal64", "-1E-398", "x...u"),
    ("power", "10", "-1E+30", HalfEven, "decimal64", "0E-398", "x...u"),
    ("power", "10", "-1E+30", HalfUp, "decimal64", "0E-398", "x...u"),
    ("power", "10", "-1E+30", HalfDown, "decimal64", "0E-398", "x...u"),
    ("power", "10", "-1E+30", Down, "decimal64", "0E-398", "x...u"),
    ("power", "10", "-1E+30", Ceiling, "decimal64", "1E-398", "x...u"),
    ("power", "10", "-1E+30", Floor, "decimal64", "0E-398", "x...u"),
    ("power", "10", "-1E+30", Up, "decimal64", "1E-398", "x...u"),
    ("power", "10", "-1E+30", ZeroFiveUp, "decimal64", "1E-398", "x...u"),
    ("exp10", "-400", "", HalfEven, "decimal64", "0E-398", "x...u"),
    ("exp10", "-400", "", HalfUp, "decimal64", "0E-398", "x...u"),
    ("exp10", "-400", "", HalfDown, "decimal64", "0E-398", "x...u"),
    ("exp10", "-400", "", Down, "decimal64", "0E-398", "x...u"),
    ("exp10", "-400", "", Ceiling, "decimal64", "1E-398", "x...u"),
    ("exp10", "-400", "", Floor, "decimal64", "0E-398", "x...u"),
    ("exp10", "-400", "", Up, "decimal64", "1E-398", "x...u"),
    ("exp10", "-400", "", ZeroFiveUp, "decimal64", "1E-398", "x...u"),
    ("exp10", "-399", "", HalfEven, "decimal64", "0E-398", "x...u"),
    ("exp10", "-399", "", HalfUp, "decimal64", "0E-398", "x...u"),
    ("exp10", "-399", "", HalfDown, "decimal64", "0E-398", "x...u"),
    ("exp10", "-399", "", Down, "decimal64", "0E-398", "x...u"),
    ("exp10", "-399", "", Ceiling, "decimal64", "1E-398", "x...u"),
    ("exp10", "-399", "", Floor, "decimal64", "0E-398", "x...u"),
    ("exp10", "-399", "", Up, "decimal64", "1E-398", "x...u"),
    ("exp10", "-399", "", ZeroFiveUp, "decimal64", "1E-398", "x...u"),
    ("pown", "-0.3", "7001", HalfEven, "decimal32", "-0E-101", "x...u"),
    ("pown", "-0.3", "7001", Ceiling, "decimal32", "-0E-101", "x...u"),
    ("pown", "-0.3", "7001", Floor, "decimal32", "-1E-101", "x...u"),
    ("pown", "-0.3", "7001", Up, "decimal32", "-1E-101", "x...u"),
    (
      "pown",
      "-0.3",
      "7001",
      HalfEven,
      "decimal128",
      "-2.117894352864269461773836445056140E-3661",
      "x....",
    ),
    (
      "pown",
      "-0.3",
      "7001",
      Ceiling,
      "decimal128",
      "-2.117894352864269461773836445056139E-3661",
      "x....",
    ),
    (
      "pown",
      "-0.3",
      "7001",
      Floor,
      "decimal128",
      "-2.117894352864269461773836445056140E-3661",
      "x....",
    ),
    (
      "pown",
      "-0.3",
      "7001",
      Up,
      "decimal128",
      "-2.117894352864269461773836445056140E-3661",
      "x....",
    ),
  ]
  for row in rows {
    let (op, operand, count, mode, format, expected, expected_flags) = row
    let context = issue168_context(format, mode)
    let base = Decimal::from_string(operand).unwrap()
    let (value, flags) = match op {
      "pown" => base.pown_ctx(issue168_int(count), context)
      "power" => base.pow_ctx(Decimal::from_string(count).unwrap(), context)
      _ => base.exp10_ctx(context)
    }
    assert_eq(
      (op, operand, count, value.to_string(), issue168_flags_text(flags)),
      (op, operand, count, expected, expected_flags),
    )
  }
}
