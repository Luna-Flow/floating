///|
fn issue305_flags_text(flags : DecimalFlags) -> String {
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
fn issue305_gda_flags_text(flags : GdaFlags) -> String {
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
fn issue305_mode_name(mode : DecimalRoundingMode) -> String {
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
fn issue305_gda_mode(mode : DecimalRoundingMode) -> GdaRoundingMode {
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
fn issue305_run(
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
  ).unwrap()
  let gda = GdaContext::new(
    precision~,
    rounding=issue305_gda_mode(mode),
    e_min~,
    e_max~,
    clamp~,
    extended~,
  ).unwrap()
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
    (issue305_value_text(value), issue305_flags_text(flags)),
    (
      issue305_value_text(outcome.value()),
      issue305_gda_flags_text(outcome.raised()),
    ),
  )
}

///|
fn issue305_value_text(value : Decimal) -> String {
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
fn issue305_check(
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
    let id = "\{op} \{args_text} p=\{precision} emin=\{e_min} emax=\{e_max} clamp=\{clamp} \{issue305_mode_name(mode)}"
    let (by_ctx, by_gda) = issue305_run(
      op, args, precision, e_min, e_max, clamp, extended, mode,
    )
    assert_eq((id, by_ctx), (id, (expected, expected_flags)))
    assert_eq((id, by_gda), (id, (expected, expected_flags)))
  }
}

///|
/// An inexact result is delivered with `precision` digits, whose exponent is at most Etop, so it is
/// never folded down: `Clamped` is not signaled. Expected values: Python `decimal` (libmpdec 4.0.0)
/// as oracle, checked against the clause by hand; the oracle is not the specification.
test "an inexact integer power that rounds to a power of ten is not Clamped (#305)" {
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
    // GDA 1.70, Exceptional conditions, Clamped: "This occurs and signals clamped if the exponent of a result
    // has been altered in order to fit the constraints of a specific concrete representation ... the exponent is
    // reduced to fit and the corresponding number of zero digits are appended to the coefficient (fold-down)."
    // An inexact result has `precision` digits (GDA 1.70, Arithmetic operations: rounded "to exactly precision
    // digits"), and its exponent adj - p + 1 is at most Emax - p + 1 = Etop, so nothing is altered to fit: no
    // Clamped, although the rounding trims 1000 to 1 and the trimmed exponent is above Etop.
    // Rows .1081 and .1129 of the random differential (seed 20261118, decimal_gda-power).
    (
      "power",
      ["0.9999999", "-1"],
      4,
      -9,
      0,
      true,
      HalfEven,
      "1.000",
      "xr......",
    ),
    ("power", ["0.9999999", "-1"], 4, -9, 0, true, HalfUp, "1.000", "xr......"),
    (
      "power",
      ["0.9999999", "-1"],
      4,
      -9,
      0,
      true,
      HalfDown,
      "1.000",
      "xr......",
    ),
    ("power", ["0.9999999", "-1"], 4, -9, 0, true, Down, "1.000", "xr......"),
    ("power", ["0.9999999", "-1"], 4, -9, 0, true, Floor, "1.000", "xr......"),
    (
      "power",
      ["0.9999999", "-1"],
      4,
      -9,
      0,
      false,
      HalfEven,
      "1.000",
      "xr......",
    ),
    ("power", ["0.9999999", "-1"], 4, -9, 0, false, HalfUp, "1.000", "xr......"),
    (
      "power",
      ["0.9999999", "-1"],
      4,
      -9,
      0,
      false,
      HalfDown,
      "1.000",
      "xr......",
    ),
    (
      "power",
      ["-0.9999999", "-1"],
      4,
      -9,
      0,
      true,
      HalfEven,
      "-1.000",
      "xr......",
    ),
    (
      "power",
      ["-0.9999999", "-1"],
      4,
      -9,
      0,
      true,
      HalfUp,
      "-1.000",
      "xr......",
    ),
    (
      "power",
      ["-0.9999999", "-1"],
      4,
      -9,
      0,
      true,
      HalfDown,
      "-1.000",
      "xr......",
    ),
    (
      "power",
      ["0.9999999", "-3"],
      4,
      -9,
      0,
      true,
      HalfEven,
      "1.000",
      "xr......",
    ),
    ("power", ["0.9999999", "-3"], 4, -9, 0, true, HalfUp, "1.000", "xr......"),
    (
      "power",
      ["0.9999999", "-3"],
      4,
      -9,
      0,
      true,
      HalfDown,
      "1.000",
      "xr......",
    ),
    (
      "power",
      ["1.0000001", "-1"],
      4,
      -9,
      0,
      true,
      HalfEven,
      "1.000",
      "xr......",
    ),
    ("power", ["1.0000001", "-1"], 4, -9, 0, true, HalfUp, "1.000", "xr......"),
    (
      "power",
      ["1.0000001", "-1"],
      4,
      -9,
      0,
      true,
      HalfDown,
      "1.000",
      "xr......",
    ),
    (
      "power",
      ["000999999900000000000000000E-27", "-6"],
      4,
      -16,
      18,
      true,
      HalfEven,
      "1.000E+18",
      "xr......",
    ),
    (
      "power",
      ["000999999900000000000000000E-27", "-6"],
      4,
      -16,
      18,
      true,
      HalfUp,
      "1.000E+18",
      "xr......",
    ),
    (
      "power",
      ["000999999900000000000000000E-27", "-6"],
      4,
      -16,
      18,
      true,
      HalfDown,
      "1.000E+18",
      "xr......",
    ),
    (
      "power",
      ["099999999999999999999999999999E-29", "-001e+0"],
      6,
      -1,
      0,
      true,
      HalfEven,
      "1.00000",
      "xr......",
    ),
    (
      "power",
      ["099999999999999999999999999999E-29", "-001e+0"],
      6,
      -1,
      0,
      true,
      HalfUp,
      "1.00000",
      "xr......",
    ),
    (
      "power",
      ["099999999999999999999999999999E-29", "-001e+0"],
      6,
      -1,
      0,
      true,
      HalfDown,
      "1.00000",
      "xr......",
    ),
    (
      "power",
      ["0.99999999999", "-1"],
      7,
      -95,
      96,
      true,
      HalfEven,
      "1.000000",
      "xr......",
    ),
    (
      "power",
      ["0.99999999999", "-1"],
      7,
      -95,
      96,
      true,
      HalfUp,
      "1.000000",
      "xr......",
    ),
    (
      "power",
      ["0.99999999999", "-1"],
      7,
      -95,
      96,
      true,
      HalfDown,
      "1.000000",
      "xr......",
    ),
    // Clamped still occurs when the exponent of an exact result is above Etop (not touched): (-1E+1)^1 at
    // precision 3, Emax 1 under clamp (Etop -1) is -10.0 Clamped; an exact 10^3 at precision 2 only
    // drops a zero (1.0E+3 Rounded) and is not altered to fit.
    ("power", ["-1E+1", "1"], 3, -3, 1, true, HalfEven, "-10.0", ".......c"),
    ("power", ["-1E+1", "1"], 3, -3, 1, true, HalfUp, "-10.0", ".......c"),
    ("power", ["-1E+1", "1"], 3, -3, 1, true, HalfDown, "-10.0", ".......c"),
    ("power", ["10", "3"], 2, -9, 3, true, HalfEven, "1.0E+3", ".r......"),
    ("power", ["10", "3"], 2, -9, 3, true, HalfUp, "1.0E+3", ".r......"),
    ("power", ["10", "3"], 2, -9, 3, true, HalfDown, "1.0E+3", ".r......"),
  ]
  issue305_check(rows)
}
