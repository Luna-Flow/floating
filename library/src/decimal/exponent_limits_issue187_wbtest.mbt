///|
fn issue187_flags(flags : DecimalFlags) -> String {
  (if flags.inexact { "x" } else { "." }) +
  (if flags.invalid_operation { "i" } else { "." }) +
  (if flags.division_by_zero { "z" } else { "." }) +
  (if flags.overflow { "o" } else { "." }) +
  (if flags.underflow { "u" } else { "." })
}

///|
fn issue187_context(
  precision : Int32,
  _clamp : Bool,
  mode : DecimalRound,
) -> DecimalContext {
  DecimalContext::new(precision~, e_max=999_999_999).with_round(mode)
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
    (String, Array[String], Int32, Bool, DecimalRound, String, String),
  ] = [
    ("sqrt", ["5E-2147483648"], 34, false, HalfEven, "0E-1000000031", "x...u"),
    ("sqrt", ["5E-2147483647"], 34, false, HalfEven, "0E-1000000031", "x...u"),
    ("sqrt", ["10E-2147483648"], 7, true, HalfEven, "0E-1000000004", "x...u"),
    ("sqrt", ["0E-2147483648"], 7, true, HalfEven, "0E-1000000004", "....."),
    ("sqrt", ["0E-2147483648"], 34, false, HalfEven, "0E-1000000031", "....."),
    ("sqrt", ["4E-2000000062"], 34, false, HalfEven, "2E-1000000031", "....."),
    ("sqrt", ["5E2147483647"], 34, false, HalfEven, "inf", "x..o."),
    (
      "fma",
      ["-15E-1999999996", "0E-1999999996", "-9E999999998"],
      34,
      true,
      HalfEven,
      "-9.000000000000000000000000000000000E+999999998",
      ".....",
    ),
    (
      "fma",
      ["7E0", "1E0", "-0E-2147483648"],
      34,
      true,
      HalfEven,
      "7.000000000000000000000000000000000",
      ".....",
    ),
    (
      "add",
      ["-0E-2147483648", "1E0"],
      34,
      true,
      HalfEven,
      "1.000000000000000000000000000000000",
      ".....",
    ),
    (
      "fma",
      ["7", "1", "0E-2147483648"],
      34,
      false,
      HalfEven,
      "7.000000000000000000000000000000000",
      ".....",
    ),
    (
      "sub",
      ["-7E999999999", "-0E-1999999996"],
      7,
      false,
      HalfDown,
      "-7.000000E+999999999",
      ".....",
    ),
    (
      "fma",
      ["5E2147483647", "-9999999999999999999999999999999999E0", "0E0"],
      34,
      false,
      HalfEven,
      "-inf",
      "x..o.",
    ),
    (
      "mul",
      ["5E2147483647", "-9999999999999999999999999999999999E0"],
      34,
      false,
      HalfEven,
      "-inf",
      "x..o.",
    ),
    (
      "fma",
      ["9E-2147483648", "9E-2147483648", "-9E-2147483648"],
      34,
      false,
      HalfEven,
      "-0E-1000000031",
      "x...u",
    ),
    (
      "fma",
      [
        "-123456789E-34", "-9999999999999999999999999999999999E-2147483647", "-25E-2147483648",
      ],
      34,
      false,
      Down,
      "0E-1000000031",
      "x...u",
    ),
    ("fma", ["10E0", "1E-1", "1E0"], 2, false, HalfEven, "2.0", "....."),
    ("fma", ["10E0", "1E-1", "-9E0"], 1, false, HalfEven, "-8", "....."),
    ("add", ["10E100", "99E2147483646"], 1, false, Ceiling, "inf", "x..o."),
    ("add", ["-10E100", "-99E2147483646"], 1, false, Floor, "-inf", "x..o."),
    (
      "add",
      ["99E2147483646", "99E2147483646"],
      2,
      false,
      HalfEven,
      "inf",
      "x..o.",
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
      _ => fail("unexpected operation \{op}")
    }
    assert_eq(
      (op, operands, value.to_string(), issue187_flags(flags)),
      (op, operands, expected, expected_flags),
    )
  }
}

///|
/// `remainder` with an exponent operand beyond the Int range: the exact
/// result is tiny and rounds to zero at the least exponent, with no abort.
test "remainder with an exponent operand beyond Int rounds to the least exponent (#187)" {
  // IEEE 754-2019 remainder (nearest quotient, exact): 7 - 9E-2147483648 * n is
  // -2E-2147483648 (7 * 10^2147483648 mod 18 = 16, quotient odd, 16 - 9 = 7 and
  // 9 - 7 = 2), which is tiny and rounds to -0 at Etiny.
  let (near, near_flags) = Decimal::from_string("7")
    .unwrap()
    .remainder_ctx(
      Decimal::from_string("9E-2147483648").unwrap(),
      issue187_context(34, false, DecimalRound::HalfEven),
    )
  assert_eq(
    (near.to_string(), issue187_flags(near_flags)),
    ("-0E-1000000031", "x...u"),
  )
}
