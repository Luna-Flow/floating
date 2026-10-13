///|
fn issue187_flags(flags : DecimalFlags) -> String {
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
fn issue187_context(
  precision : Int32,
  clamp : Bool,
  mode : DecimalRoundingMode,
) -> DecimalContext {
  DecimalContext::new(precision~, decimal_rounding=mode, clamp~).unwrap()
}

///|
/// Operands whose exponents are near the `Int` limits must neither abort nor
/// wrap. Expected values: Python `decimal` with `Emin = -999999999`,
/// `Emax = 999999999` and traps off, a faithful General Decimal Arithmetic
/// implementation (cross-check only; the specification is the authority).
/// Rows: operation, operands, precision, clamp, rounding mode, result, flags
/// (inexact, rounded, invalid, divide-by-zero, overflow, underflow, subnormal,
/// clamped).
test "operands with exponents near the Int limits give the specified results (#187)" {
  let rows : Array[
    (String, Array[String], Int32, Bool, DecimalRoundingMode, String, String),
  ] = [
    (
      "remainder",
      ["7", "9E-2147483648"],
      34,
      false,
      HalfEven,
      "nan",
      "..i.....",
    ),
    (
      "remainder",
      ["10E1000", "50E-2147483647"],
      2,
      false,
      HalfEven,
      "nan",
      "..i.....",
    ),
    (
      "remainder",
      ["9E2147483646", "-1E-1000000000"],
      34,
      false,
      Down,
      "nan",
      "..i.....",
    ),
    (
      "remainder",
      ["1E2147483646", "-9E-2147483648"],
      34,
      false,
      Up,
      "nan",
      "..i.....",
    ),
    (
      "remainder",
      ["7E5", "9E-2147483647"],
      34,
      false,
      Ceiling,
      "nan",
      "..i.....",
    ),
    (
      "sqrt",
      ["5E-2147483648"],
      34,
      false,
      HalfEven,
      "0E-1000000032",
      "xr...usc",
    ),
    (
      "sqrt",
      ["5E-2147483647"],
      34,
      false,
      HalfEven,
      "0E-1000000032",
      "xr...usc",
    ),
    ("sqrt", ["10E-2147483648"], 7, true, HalfEven, "0E-1000000005", "xr...usc"),
    ("sqrt", ["0E-2147483648"], 7, true, HalfEven, "0E-1000000005", ".......c"),
    (
      "sqrt",
      ["0E-2147483648"],
      34,
      false,
      HalfEven,
      "0E-1000000032",
      ".......c",
    ),
    (
      "sqrt",
      ["4E-2000000064"],
      34,
      false,
      HalfEven,
      "2E-1000000032",
      "......s.",
    ),
    ("sqrt", ["5E2147483647"], 34, false, HalfEven, "inf", "xr..o..."),
    (
      "fma",
      ["-15E-1999999996", "0E-1999999996", "-9E999999998"],
      34,
      true,
      HalfEven,
      "-9.000000000000000000000000000000000E+999999998",
      ".r......",
    ),
    (
      "fma",
      ["7E0", "1E0", "-0E-2147483648"],
      34,
      true,
      HalfEven,
      "7.000000000000000000000000000000000",
      ".r......",
    ),
    (
      "add",
      ["-0E-2147483648", "1E0"],
      34,
      true,
      HalfEven,
      "1.000000000000000000000000000000000",
      ".r......",
    ),
    (
      "fma",
      ["7", "1", "0E-2147483648"],
      34,
      false,
      HalfEven,
      "7.000000000000000000000000000000000",
      ".r......",
    ),
    (
      "sub",
      ["-7E999999999", "-0E-1999999996"],
      7,
      false,
      HalfDown,
      "-7.000000E+999999999",
      ".r......",
    ),
    (
      "fma",
      ["5E2147483647", "-9999999999999999999999999999999999E0", "0E0"],
      34,
      false,
      HalfEven,
      "-inf",
      "xr..o...",
    ),
    (
      "mul",
      ["5E2147483647", "-9999999999999999999999999999999999E0"],
      34,
      false,
      HalfEven,
      "-inf",
      "xr..o...",
    ),
    (
      "fma",
      ["9E-2147483648", "9E-2147483648", "-9E-2147483648"],
      34,
      false,
      HalfEven,
      "-0E-1000000032",
      "xr...usc",
    ),
    (
      "fma",
      [
        "-123456789E-34", "-9999999999999999999999999999999999E-2147483647", "-25E-2147483648",
      ],
      34,
      false,
      Down,
      "0E-1000000032",
      "xr...usc",
    ),
    ("fma", ["10E0", "1E-1", "1E0"], 2, false, HalfEven, "2.0", "........"),
    ("fma", ["10E0", "1E-1", "-9E0"], 1, false, HalfEven, "-8", ".r......"),
    ("add", ["10E100", "99E2147483646"], 1, false, Ceiling, "inf", "xr..o..."),
    ("add", ["-10E100", "-99E2147483646"], 1, false, Floor, "-inf", "xr..o..."),
    (
      "add",
      ["99E2147483646", "99E2147483646"],
      2,
      false,
      HalfEven,
      "inf",
      "xr..o...",
    ),
  ]
  for row in rows {
    let (op, operands, precision, clamp, mode, expected, expected_flags) = row
    let ctx = issue187_context(precision, clamp, mode)
    let base = Decimal::from_string(operands[0]).unwrap()
    let second = fn() { Decimal::from_string(operands[1]).unwrap() }
    let third = fn() { Decimal::from_string(operands[2]).unwrap() }
    let (value, flags) = match op {
      "add" => base.add_ctx(second(), ctx)
      "sub" => base.sub_ctx(second(), ctx)
      "mul" => base.mul_ctx(second(), ctx)
      "fma" => base.fma_ctx(second(), third(), ctx)
      "sqrt" => base.sqrt_ctx(ctx)
      "remainder" => base.remainder(second(), ctx)
      _ => fail("unexpected operation \{op}")
    }
    assert_eq(
      (op, operands, value.to_string(), issue187_flags(flags)),
      (op, operands, expected, expected_flags),
    )
  }
}

///|
/// `rescale` takes the target exponent as the integer value of its second
/// operand; a value that is not an integer, or that is out of range, is an
/// invalid operation instead of an abort.
test "rescale with an exponent operand beyond Int is invalid (#187)" {
  let ctx = issue187_context(34, false, DecimalRoundingMode::HalfEven)
  let cases = [
    ("9E999999999", "-5E2147483646"),
    ("1E0", "1E-2147483648"),
    ("1E-2147483648", "-9E2147483646"),
  ]
  for pair in cases {
    let (value, quantum) = pair
    let (result, flags) = Decimal::from_string(value)
      .unwrap()
      .rescale(Decimal::from_string(quantum).unwrap(), ctx)
    assert_eq(
      (value, quantum, result.to_string(), issue187_flags(flags)),
      (value, quantum, "nan", "..i....."),
    )
  }
  // IEEE 754-2019 remainder (nearest quotient, exact): 7 - 9E-2147483648 * n is
  // -2E-2147483648 (7 * 10^2147483648 mod 18 = 16, quotient odd, 16 - 9 = 7 and
  // 9 - 7 = 2), which is tiny and rounds to -0 at Etiny.
  let (near, near_flags) = Decimal::from_string("7")
    .unwrap()
    .remainder_near(
      Decimal::from_string("9E-2147483648").unwrap(),
      issue187_context(34, false, DecimalRoundingMode::HalfEven),
    )
  assert_eq(
    (near.to_string(), issue187_flags(near_flags)),
    ("-0E-1000000032", "xr...usc"),
  )
}
