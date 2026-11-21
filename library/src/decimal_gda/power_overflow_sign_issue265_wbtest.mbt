///|
fn issue265_flags_text(flags : DecimalFlags) -> String {
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
fn issue265_gda_flags_text(flags : GdaFlags) -> String {
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
fn issue265_mode_name(mode : DecimalRoundingMode) -> String {
  match mode {
    HalfEven => "half_even"
    HalfUp => "half_up"
    HalfDown => "half_down"
    Down => "down"
    Ceiling => "ceiling"
    Floor => "floor"
    Up => "up"
    ZeroFiveUp => "05up"
  }
}

///|
fn issue265_gda_mode(mode : DecimalRoundingMode) -> GdaRoundingMode {
  match mode {
    HalfEven => GdaRoundingMode::HalfEven
    HalfUp => GdaRoundingMode::HalfUp
    HalfDown => GdaRoundingMode::HalfDown
    Down => GdaRoundingMode::Down
    Ceiling => GdaRoundingMode::Ceiling
    Floor => GdaRoundingMode::Floor
    Up => GdaRoundingMode::Up
    ZeroFiveUp => GdaRoundingMode::ZeroFiveUp
  }
}

///|
/// Runs one row through `Decimal::*_ctx` and through the `GdaContext` adapter
/// of the same operation, returning `(value, flags)` text for each path.
fn issue265_run(
  op : String,
  args : Array[String],
  precision : Int32,
  e_min : Int32,
  e_max : Int32,
  clamp : Bool,
  extended : Bool,
  mode : DecimalRoundingMode,
) -> ((String, String), (String, String)) {
  let ctx = DecimalContext::new(
    precision~,
    decimal_rounding=mode,
    e_min~,
    e_max~,
    clamp~,
    extended~,
  )
  let gda = gda_context_unchecked(
    precision~,
    rounding=issue265_gda_mode(mode),
    e_min~,
    e_max~,
    clamp~,
    extended~,
  )
  let x = Decimal::from_string(args[0]).unwrap()
  let y = if args.length() > 1 {
    Decimal::from_string(args[1]).unwrap()
  } else {
    x
  }
  let z = if args.length() > 2 {
    Decimal::from_string(args[2]).unwrap()
  } else {
    x
  }
  let (value, flags) = match op {
    "add" => x.add_ctx(y, ctx)
    "subtract" => x.sub_ctx(y, ctx)
    "multiply" => x.mul_ctx(y, ctx)
    "divide" => x.div_ctx(y, ctx)
    "fma" => x.fma_ctx(y, z, ctx)
    "power" => x.power_ctx(y, ctx)
    "plus" => x.plus_ctx(ctx)
    _ => abort("unexpected operation \{op}")
  }
  let outcome = match op {
    "add" => add(x, y, gda)
    "subtract" => subtract(x, y, gda)
    "multiply" => multiply(x, y, gda)
    "divide" => divide(x, y, gda)
    "fma" => fma(x, y, z, gda)
    "power" => power(x, y, gda)
    "plus" => plus(x, gda)
    _ => abort("unexpected operation \{op}")
  }
  (
    (issue265_value_text(value), issue265_flags_text(flags)),
    (
      issue265_value_text(outcome.value()),
      issue265_gda_flags_text(outcome.raised()),
    ),
  )
}

///|
fn issue265_value_text(value : Decimal) -> String {
  if value.is_infinite() {
    if value.is_signed() {
      "-Infinity"
    } else {
      "Infinity"
    }
  } else {
    value.to_string()
  }
}

///|
fn issue265_check(
  rows : Array[
    (
      String,
      Array[String],
      Int32,
      Int32,
      Int32,
      Bool,
      DecimalRoundingMode,
      String,
      String,
    ),
  ],
  extended~ : Bool = true,
) -> Unit raise {
  for row in rows {
    let (
      op,
      args,
      precision,
      e_min,
      e_max,
      clamp,
      mode,
      expected,
      expected_flags,
    ) = row
    let args_text = args.join(" ")
    let id = "\{op} \{args_text} p=\{precision} emin=\{e_min} emax=\{e_max} clamp=\{clamp} \{issue265_mode_name(mode)}"
    let (by_ctx, by_gda) = issue265_run(
      op, args, precision, e_min, e_max, clamp, extended, mode,
    )
    assert_eq((id, by_ctx), (id, (expected, expected_flags)))
    assert_eq((id, by_gda), (id, (expected, expected_flags)))
  }
}

///|
/// GDA 1.70, *power* gives the result sign 1 only for an odd integral exponent and
/// a negative base; an overflowing reciprocal must not carry the base's sign into
/// the result. Expected values: Python `decimal` (libmpdec 4.0.0) as oracle, checked
/// against the clause by hand; the oracle is not the specification.
// oracle: A
// source: CPython decimal rows checked against GDA power sign rule; 102/102 re-run, 0 disagree
// shares: nothing
test "power overflows with the sign of the power, not of the reciprocal (#265)" {
  let rows : Array[
    (
      String,
      Array[String],
      Int32,
      Int32,
      Int32,
      Bool,
      DecimalRoundingMode,
      String,
      String,
    ),
  ] = [
    // GDA 1.70, power: "The sign of the result will be 1 only if the right-hand side has an
    // integral value and is odd (and is not infinite) and also the sign of the left-hand
    // side is 1. In all other cases, the sign of the result will be 0." A negative base
    // with an even negative exponent overflows to +Infinity (or the largest finite
    // number in the directed modes, GDA 1.70, Overflow), not to -Infinity.
    (
      "power",
      ["-7E-2", "-8"],
      1,
      -5,
      0,
      false,
      HalfEven,
      "Infinity",
      "xr..o...",
    ),
    ("power", ["-7E-2", "-8"], 1, -5, 0, false, HalfUp, "Infinity", "xr..o..."),
    (
      "power",
      ["-7E-2", "-8"],
      1,
      -5,
      0,
      false,
      HalfDown,
      "Infinity",
      "xr..o...",
    ),
    ("power", ["-7E-2", "-8"], 1, -5, 0, false, Down, "9", "xr..o..."),
    ("power", ["-7E-2", "-8"], 1, -5, 0, false, Ceiling, "Infinity", "xr..o..."),
    ("power", ["-7E-2", "-8"], 1, -5, 0, false, Floor, "9", "xr..o..."),
    ("power", ["-7E-2", "-8"], 1, -5, 0, false, Up, "Infinity", "xr..o..."),
    ("power", ["-7E-2", "-8"], 1, -5, 0, false, ZeroFiveUp, "9", "xr..o..."),
    (
      "power",
      ["-7E-2", "-2"],
      1,
      -5,
      0,
      false,
      HalfEven,
      "Infinity",
      "xr..o...",
    ),
    ("power", ["-7E-2", "-2"], 1, -5, 0, false, HalfUp, "Infinity", "xr..o..."),
    (
      "power",
      ["-7E-2", "-2"],
      1,
      -5,
      0,
      false,
      HalfDown,
      "Infinity",
      "xr..o...",
    ),
    ("power", ["-7E-2", "-2"], 1, -5, 0, false, Down, "9", "xr..o..."),
    ("power", ["-7E-2", "-2"], 1, -5, 0, false, Ceiling, "Infinity", "xr..o..."),
    ("power", ["-7E-2", "-2"], 1, -5, 0, false, Floor, "9", "xr..o..."),
    ("power", ["-7E-2", "-2"], 1, -5, 0, false, Up, "Infinity", "xr..o..."),
    ("power", ["-7E-2", "-2"], 1, -5, 0, false, ZeroFiveUp, "9", "xr..o..."),
    ("power", ["-7E-2", "-8"], 1, 0, 0, true, HalfEven, "Infinity", "xr..o..."),
    ("power", ["-7E-2", "-8"], 1, 0, 0, true, HalfUp, "Infinity", "xr..o..."),
    ("power", ["-7E-2", "-8"], 1, 0, 0, true, HalfDown, "Infinity", "xr..o..."),
    ("power", ["-7E-2", "-8"], 1, 0, 0, true, Down, "9", "xr..o..."),
    ("power", ["-7E-2", "-8"], 1, 0, 0, true, Ceiling, "Infinity", "xr..o..."),
    ("power", ["-7E-2", "-8"], 1, 0, 0, true, Floor, "9", "xr..o..."),
    ("power", ["-7E-2", "-8"], 1, 0, 0, true, Up, "Infinity", "xr..o..."),
    ("power", ["-7E-2", "-8"], 1, 0, 0, true, ZeroFiveUp, "9", "xr..o..."),
    (
      "power",
      ["-7E-2", "-8.0"],
      1,
      -5,
      0,
      false,
      HalfEven,
      "Infinity",
      "xr..o...",
    ),
    (
      "power",
      ["-7E-2", "-8.0"],
      1,
      -5,
      0,
      false,
      Ceiling,
      "Infinity",
      "xr..o...",
    ),
    ("power", ["-7E-2", "-8.0"], 1, -5, 0, false, Floor, "9", "xr..o..."),
    (
      "power",
      ["-7E-2", "-8"],
      3,
      -4,
      2,
      false,
      HalfEven,
      "Infinity",
      "xr..o...",
    ),
    ("power", ["-7E-2", "-8"], 3, -4, 2, false, Down, "999", "xr..o..."),
    ("power", ["-7E-2", "-8"], 3, -4, 2, false, Ceiling, "Infinity", "xr..o..."),
    ("power", ["-7E-2", "-8"], 3, -4, 2, false, Floor, "999", "xr..o..."),
    (
      "power",
      ["-1E-20", "-6"],
      7,
      -95,
      96,
      true,
      HalfEven,
      "Infinity",
      "xr..o...",
    ),
    (
      "power",
      ["-1E-20", "-6"],
      7,
      -95,
      96,
      true,
      HalfUp,
      "Infinity",
      "xr..o...",
    ),
    (
      "power",
      ["-1E-20", "-6"],
      7,
      -95,
      96,
      true,
      HalfDown,
      "Infinity",
      "xr..o...",
    ),
    (
      "power",
      ["-1E-20", "-6"],
      7,
      -95,
      96,
      true,
      Down,
      "9.999999E+96",
      "xr..o...",
    ),
    (
      "power",
      ["-1E-20", "-6"],
      7,
      -95,
      96,
      true,
      Ceiling,
      "Infinity",
      "xr..o...",
    ),
    (
      "power",
      ["-1E-20", "-6"],
      7,
      -95,
      96,
      true,
      Floor,
      "9.999999E+96",
      "xr..o...",
    ),
    ("power", ["-1E-20", "-6"], 7, -95, 96, true, Up, "Infinity", "xr..o..."),
    (
      "power",
      ["-1E-20", "-6"],
      7,
      -95,
      96,
      true,
      ZeroFiveUp,
      "9.999999E+96",
      "xr..o...",
    ),
    (
      "power",
      ["-1E-20", "-1E+1"],
      7,
      -95,
      96,
      true,
      HalfEven,
      "Infinity",
      "xr..o...",
    ),
    (
      "power",
      ["-1E-20", "-1E+1"],
      7,
      -95,
      96,
      true,
      Floor,
      "9.999999E+96",
      "xr..o...",
    ),
    // An odd negative exponent keeps the sign of a negative base: the overflow is
    // -Infinity (or -Nmax). A positive base never gives a negative result.
    (
      "power",
      ["-7E-2", "-7"],
      1,
      -5,
      0,
      false,
      HalfEven,
      "-Infinity",
      "xr..o...",
    ),
    ("power", ["-7E-2", "-7"], 1, -5, 0, false, HalfUp, "-Infinity", "xr..o..."),
    (
      "power",
      ["-7E-2", "-7"],
      1,
      -5,
      0,
      false,
      HalfDown,
      "-Infinity",
      "xr..o...",
    ),
    ("power", ["-7E-2", "-7"], 1, -5, 0, false, Down, "-9", "xr..o..."),
    ("power", ["-7E-2", "-7"], 1, -5, 0, false, Ceiling, "-9", "xr..o..."),
    ("power", ["-7E-2", "-7"], 1, -5, 0, false, Floor, "-Infinity", "xr..o..."),
    ("power", ["-7E-2", "-7"], 1, -5, 0, false, Up, "-Infinity", "xr..o..."),
    ("power", ["-7E-2", "-7"], 1, -5, 0, false, ZeroFiveUp, "-9", "xr..o..."),
    ("power", ["-7E-2", "-9"], 1, 0, 0, true, HalfEven, "-Infinity", "xr..o..."),
    ("power", ["-7E-2", "-9"], 1, 0, 0, true, HalfUp, "-Infinity", "xr..o..."),
    ("power", ["-7E-2", "-9"], 1, 0, 0, true, HalfDown, "-Infinity", "xr..o..."),
    ("power", ["-7E-2", "-9"], 1, 0, 0, true, Down, "-9", "xr..o..."),
    ("power", ["-7E-2", "-9"], 1, 0, 0, true, Ceiling, "-9", "xr..o..."),
    ("power", ["-7E-2", "-9"], 1, 0, 0, true, Floor, "-Infinity", "xr..o..."),
    ("power", ["-7E-2", "-9"], 1, 0, 0, true, Up, "-Infinity", "xr..o..."),
    ("power", ["-7E-2", "-9"], 1, 0, 0, true, ZeroFiveUp, "-9", "xr..o..."),
    (
      "power",
      ["-1E-20", "-5"],
      7,
      -95,
      96,
      true,
      HalfEven,
      "-Infinity",
      "xr..o...",
    ),
    (
      "power",
      ["-1E-20", "-5"],
      7,
      -95,
      96,
      true,
      HalfUp,
      "-Infinity",
      "xr..o...",
    ),
    (
      "power",
      ["-1E-20", "-5"],
      7,
      -95,
      96,
      true,
      HalfDown,
      "-Infinity",
      "xr..o...",
    ),
    (
      "power",
      ["-1E-20", "-5"],
      7,
      -95,
      96,
      true,
      Down,
      "-9.999999E+96",
      "xr..o...",
    ),
    (
      "power",
      ["-1E-20", "-5"],
      7,
      -95,
      96,
      true,
      Ceiling,
      "-9.999999E+96",
      "xr..o...",
    ),
    (
      "power",
      ["-1E-20", "-5"],
      7,
      -95,
      96,
      true,
      Floor,
      "-Infinity",
      "xr..o...",
    ),
    ("power", ["-1E-20", "-5"], 7, -95, 96, true, Up, "-Infinity", "xr..o..."),
    (
      "power",
      ["-1E-20", "-5"],
      7,
      -95,
      96,
      true,
      ZeroFiveUp,
      "-9.999999E+96",
      "xr..o...",
    ),
    ("power", ["7E-2", "-8"], 1, -5, 0, false, HalfEven, "Infinity", "xr..o..."),
    ("power", ["7E-2", "-8"], 1, -5, 0, false, HalfUp, "Infinity", "xr..o..."),
    ("power", ["7E-2", "-8"], 1, -5, 0, false, HalfDown, "Infinity", "xr..o..."),
    ("power", ["7E-2", "-8"], 1, -5, 0, false, Down, "9", "xr..o..."),
    ("power", ["7E-2", "-8"], 1, -5, 0, false, Ceiling, "Infinity", "xr..o..."),
    ("power", ["7E-2", "-8"], 1, -5, 0, false, Floor, "9", "xr..o..."),
    ("power", ["7E-2", "-8"], 1, -5, 0, false, Up, "Infinity", "xr..o..."),
    ("power", ["7E-2", "-8"], 1, -5, 0, false, ZeroFiveUp, "9", "xr..o..."),
    ("power", ["7E-2", "-7"], 1, -5, 0, false, HalfEven, "Infinity", "xr..o..."),
    ("power", ["7E-2", "-7"], 1, -5, 0, false, HalfUp, "Infinity", "xr..o..."),
    ("power", ["7E-2", "-7"], 1, -5, 0, false, HalfDown, "Infinity", "xr..o..."),
    ("power", ["7E-2", "-7"], 1, -5, 0, false, Down, "9", "xr..o..."),
    ("power", ["7E-2", "-7"], 1, -5, 0, false, Ceiling, "Infinity", "xr..o..."),
    ("power", ["7E-2", "-7"], 1, -5, 0, false, Floor, "9", "xr..o..."),
    ("power", ["7E-2", "-7"], 1, -5, 0, false, Up, "Infinity", "xr..o..."),
    ("power", ["7E-2", "-7"], 1, -5, 0, false, ZeroFiveUp, "9", "xr..o..."),
    // Positive exponents and underflow: the zero or tiny result carries the sign of the
    // power (GDA 1.70, power; Underflow: "with the sign of the intermediate result").
    // Nearest modes and Down only: the directed-away modes are covered by
    // power_underflow_rounding_issue168_wbtest.mbt.
    ("power", ["-7E-2", "8"], 1, -5, 0, false, HalfEven, "0.00000", "xr...usc"),
    ("power", ["-7E-2", "8"], 1, -5, 0, false, HalfUp, "0.00000", "xr...usc"),
    ("power", ["-7E-2", "8"], 1, -5, 0, false, HalfDown, "0.00000", "xr...usc"),
    ("power", ["-7E-2", "8"], 1, -5, 0, false, Down, "0.00000", "xr...usc"),
    ("power", ["-7E-2", "9"], 1, -5, 0, false, HalfEven, "-0.00000", "xr...usc"),
    ("power", ["-7E-2", "9"], 1, -5, 0, false, HalfUp, "-0.00000", "xr...usc"),
    ("power", ["-7E-2", "9"], 1, -5, 0, false, HalfDown, "-0.00000", "xr...usc"),
    ("power", ["-7E-2", "9"], 1, -5, 0, false, Down, "-0.00000", "xr...usc"),
    (
      "power",
      ["-1E+20", "5"],
      7,
      -95,
      96,
      true,
      HalfEven,
      "-Infinity",
      "xr..o...",
    ),
    (
      "power",
      ["-1E+20", "5"],
      7,
      -95,
      96,
      true,
      HalfUp,
      "-Infinity",
      "xr..o...",
    ),
    (
      "power",
      ["-1E+20", "5"],
      7,
      -95,
      96,
      true,
      HalfDown,
      "-Infinity",
      "xr..o...",
    ),
    (
      "power",
      ["-1E+20", "5"],
      7,
      -95,
      96,
      true,
      Down,
      "-9.999999E+96",
      "xr..o...",
    ),
    (
      "power",
      ["-1E+20", "6"],
      7,
      -95,
      96,
      true,
      HalfEven,
      "Infinity",
      "xr..o...",
    ),
    ("power", ["-1E+20", "6"], 7, -95, 96, true, HalfUp, "Infinity", "xr..o..."),
    (
      "power",
      ["-1E+20", "6"],
      7,
      -95,
      96,
      true,
      HalfDown,
      "Infinity",
      "xr..o...",
    ),
    (
      "power",
      ["-1E+20", "6"],
      7,
      -95,
      96,
      true,
      Down,
      "9.999999E+96",
      "xr..o...",
    ),
    // Zero base: "If the left-hand operand is a zero, the result will be exact and will be
    // infinite if the right-hand side is negative or 0 if the right-hand side is positive";
    // the sign is 1 for an odd power of -0 (GDA 1.70, Division by zero, power).
    ("power", ["-0", "-2"], 5, -95, 96, false, HalfEven, "Infinity", "........"),
    (
      "power",
      ["-0", "-3"],
      5,
      -95,
      96,
      false,
      HalfEven,
      "-Infinity",
      "........",
    ),
    ("power", ["0", "-3"], 5, -95, 96, false, HalfEven, "Infinity", "........"),
    ("power", ["-0", "2"], 5, -95, 96, false, HalfEven, "0", "........"),
    ("power", ["-0", "3"], 5, -95, 96, false, HalfEven, "-0", "........"),
  ]
  issue265_check(rows)
}
