///|
/// `power(x, 0)` for a finite nonzero `x` is the integer `1` with exponent 0
/// and no conditions in every context (issue 405). GDA 1.70, power: "If the
/// right-hand operand is a zero, the result will be 1 and exact." decNumber
/// returns it with an early exit that never reaches the final `decCopyFit` and
/// `decFinish` (`decNumberPower`, "x**0 = 1"), so a clamped context does not fold
/// it down; `decFinalize` applies the fold-down only for an exponent above
/// `e_max - precision + 1`, and the IEEE interchange encoders fold by
/// themselves at 90, 369 and 6111 (decimal32, decimal64, decimal128), far
/// above the exponent 0 of `1`. The result differs from a folded one only in a
/// clamped context with `e_max < precision - 1`, which no IEEE format has.
/// `1 ** n` is not covered (a known open point of the issue).

///|
let issue405_modes : Array[(String, DecimalRoundingMode, GdaRoundingMode)] = [
  ("half_even", HalfEven, GdaRoundingMode::HalfEven),
  ("half_up", HalfUp, GdaRoundingMode::HalfUp),
  ("half_down", HalfDown, GdaRoundingMode::HalfDown),
  ("down", Down, GdaRoundingMode::Down),
  ("up", Up, GdaRoundingMode::Up),
  ("ceiling", Ceiling, GdaRoundingMode::Ceiling),
  ("floor", Floor, GdaRoundingMode::Floor),
  ("05up", ZeroFiveUp, GdaRoundingMode::ZeroFiveUp),
]

///|
/// (name, precision, e_min, e_max, clamp, extended)
let issue405_contexts : Array[(String, Int32, Int32, Int32, Bool, Bool)] = [
  ("clamped e_max < precision - 1", 5, -10, 0, true, true),
  ("clamped, e_max 1, precision 3", 3, -5, 1, true, true),
  ("not clamped", 5, -10, 0, false, true),
  ("decimal32", 7, -95, 96, true, true),
  ("decimal64", 16, -383, 384, true, true),
  ("decimal128", 34, -6143, 6144, true, true),
  ("subset, clamped", 5, -10, 0, true, false),
]

///|
let issue405_bases : Array[String] = [
  "9.99", "10", "1E+2", "0.1", "1", "1.0", "-3", "1E-5", "7E+3", "-1E+2",
]

///|
let issue405_exponents : Array[String] = ["0", "-0", "0E+5", "0.0", "0E-3"]

///|
fn issue405_flags_text(flags : DecimalFlags) -> String {
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
fn issue405_gda_flags_text(flags : GdaFlags) -> String {
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
fn issue405_value_text(value : Decimal) -> String {
  if value.is_infinite() {
    if value.is_negative() {
      "-Infinity"
    } else {
      "Infinity"
    }
  } else {
    value.to_string()
  }
}

///|
fn issue405_rows(
  base : String,
  exponent : String,
) -> Array[(String, String, String)] {
  let rows : Array[(String, String, String)] = []
  for context_entry in issue405_contexts {
    let (name, precision, e_min, e_max, clamp, extended) = context_entry
    for mode in issue405_modes {
      let ctx = DecimalContext::new(
        precision~,
        decimal_rounding=mode.1,
        e_min~,
        e_max~,
        clamp~,
        extended~,
      ).unwrap()
      let gda = GdaContext::new(
        precision~,
        rounding=mode.2,
        e_min~,
        e_max~,
        clamp~,
        extended~,
      ).unwrap()
      let x = Decimal::from_string(base).unwrap()
      let y = Decimal::from_string(exponent).unwrap()
      let (value, flags) = x.power_ctx(y, ctx)
      let outcome = power(x, y, gda)
      let label = "\{name} \{mode.0} power \{base} \{exponent}"
      rows.push((label, issue405_value_text(value), issue405_flags_text(flags)))
      rows.push(
        (
          label + " (GdaContext)",
          issue405_value_text(outcome.value()),
          issue405_gda_flags_text(outcome.raised()),
        ),
      )
    }
  }
  rows
}

///|
test "power of a finite nonzero base to a zero exponent is exactly 1 in every context (issue 405)" {
  for base in issue405_bases {
    for exponent in issue405_exponents {
      for row in issue405_rows(base, exponent) {
        assert_eq(row, (row.0, "1", "........"))
      }
    }
  }
}

///|
test "power of infinity to a zero exponent is 1 and 0 to 0 keeps its rule (issue 405)" {
  // Inf ** 0 is the integer 1 as well (decNumberPower, "[-]Inf**0 => 1").
  for base in ["Infinity", "-Infinity"] {
    for row in issue405_rows(base, "0") {
      assert_eq(row, (row.0, "1", "........"))
    }
  }
  // 0 ** 0 is an Invalid operation in an extended context and 1 in a subset one.
  let extended = DecimalContext::new(
    precision=5,
    e_min=-10,
    e_max=0,
    clamp=true,
  ).unwrap()
  let (value, flags) = Decimal::zero().power_ctx(Decimal::zero(), extended)
  assert_true(value.is_nan())
  assert_true(flags.invalid_operation)
  let subset = DecimalContext::new(
    precision=5,
    e_min=-10,
    e_max=0,
    clamp=true,
    extended=false,
  ).unwrap()
  let (one, flags) = Decimal::zero().power_ctx(Decimal::zero(), subset)
  assert_eq(issue405_value_text(one), "1")
  assert_eq(issue405_flags_text(flags), "........")
}

///|
test "power to a non-zero exponent in a clamped context still folds down (issue 405)" {
  // The neighbour: 2 ** 1 is 2.0000 with Clamped, 1 ** 1 stays 1 (known open point).
  let ctx = DecimalContext::new(precision=5, e_min=-10, e_max=0, clamp=true).unwrap()
  let (two, flags) = Decimal::from_string("2")
    .unwrap()
    .power_ctx(Decimal::from_string("1").unwrap(), ctx)
  assert_eq(two.to_string(), "2.0000")
  assert_true(flags.clamped)
  let (one, flags) = Decimal::from_string("1")
    .unwrap()
    .power_ctx(Decimal::from_string("1").unwrap(), ctx)
  assert_eq(one.to_string(), "1")
  assert_false(flags.clamped)
}
