///|
fn issue287_flags_text(flags : DecimalFlags) -> String {
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
fn issue287_gda_flags_text(flags : GdaFlags) -> String {
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
fn issue287_mode_name(mode : DecimalRoundingMode) -> String {
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
fn issue287_gda_mode(mode : DecimalRoundingMode) -> GdaRoundingMode {
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
fn issue287_run(
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
    rounding=issue287_gda_mode(mode),
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
    (issue287_value_text(value), issue287_flags_text(flags)),
    (
      issue287_value_text(outcome.value()),
      issue287_gda_flags_text(outcome.raised()),
    ),
  )
}

///|
fn issue287_value_text(value : Decimal) -> String {
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
fn issue287_check(
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
    let id = "\{op} \{args_text} p=\{precision} emin=\{e_min} emax=\{e_max} clamp=\{clamp} \{issue287_mode_name(mode)}"
    let (by_ctx, by_gda) = issue287_run(
      op, args, precision, e_min, e_max, clamp, extended, mode,
    )
    assert_eq((id, by_ctx), (id, (expected, expected_flags)))
    assert_eq((id, by_gda), (id, (expected, expected_flags)))
  }
}

///|
/// `decimal_power_ten_cohort_result` returned the preferred cohort of a power of ten without the
/// clamp fold-down. Expected values: Python `decimal` (libmpdec 4.0.0) as oracle, checked against the
/// clause by hand; the oracle is not the specification.
// oracle: A
// source: CPython decimal rows checked against Clamped clause; 43/43 re-run, 0 disagree
// shares: Decimal::from_string and to_string (reading the inputs, printing the result, through the helper issue287_check)
test "a power of ten above Etop is folded down and flagged Clamped (#287)" {
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
    // GDA 1.70, Exceptional conditions, Clamped: "the exponent of a result has been altered in order to
    // fit the constraints of a specific concrete representation ... the exponent is reduced to fit and
    // the corresponding number of zero digits are appended to the coefficient (fold-down)". A power of ten
    // whose exponent is above Etop = Emax - p + 1 under clamp is folded down and flagged: p = 7,
    // Emax = 999: (-1E+998)^1 is -1.00000E+998 Clamped. The value 1 keeps its cohort, as it does in libmpdec.
    (
      "power",
      ["-1E+998", "1"],
      7,
      -999,
      999,
      true,
      HalfEven,
      "-1.00000E+998",
      ".......c",
    ),
    ("power", ["-1E+1", "-1"], 3, -5, 0, true, HalfEven, "-0.10", ".......c"),
    ("power", ["-1E+1", "1"], 3, -3, 1, true, HalfEven, "-10.0", ".......c"),
    // The same for a grid of powers of ten (bases 1E+k, 10E+k, 100E+k and signs, exponents -9..9,
    // nine contexts, nearest and Down): the 94 rows of the grid that main answered without the fold-down
    // (a random sample of 40 is listed).
    ("power", ["-1E+1", "6"], 4, -6, 6, true, HalfEven, "1.000E+6", ".......c"),
    ("power", ["-1E-2", "-1"], 5, -3, 3, true, Down, "-100.0", ".......c"),
    ("power", ["1E+1", "-1"], 3, -5, 0, true, Down, "0.10", ".......c"),
    ("power", ["1E-2", "-3"], 4, -6, 6, true, HalfEven, "1.000E+6", ".......c"),
    ("power", ["1E+1", "1"], 3, -3, 1, true, HalfEven, "10.0", ".......c"),
    ("power", ["-1E+1", "3"], 5, -3, 3, true, Down, "-1000.0", ".......c"),
    ("power", ["1E+1", "1"], 5, -3, 3, true, HalfEven, "10.0", ".......c"),
    ("power", ["-1E+1", "-1"], 3, -5, 0, true, HalfEven, "-0.10", ".......c"),
    ("power", ["-1E-2", "-3"], 4, -6, 6, true, Down, "-1.000E+6", ".......c"),
    (
      "power",
      ["-1E-6", "-1"],
      4,
      -6,
      6,
      true,
      HalfEven,
      "-1.000E+6",
      ".......c",
    ),
    ("power", ["1E+1", "4"], 4, -6, 6, true, Down, "1.0E+4", ".......c"),
    (
      "power",
      ["1E+12", "8"],
      7,
      -95,
      96,
      true,
      Down,
      "1.000000E+96",
      ".......c",
    ),
    ("power", ["-1E+5", "1"], 4, -6, 6, true, Down, "-1.00E+5", ".......c"),
    ("power", ["1E-2", "-3"], 4, -6, 6, true, Down, "1.000E+6", ".......c"),
    ("power", ["1E+3", "1"], 5, -3, 3, true, HalfEven, "1000.0", ".......c"),
    ("power", ["1E+3", "2"], 4, -6, 6, true, Down, "1.000E+6", ".......c"),
    (
      "power",
      ["-1E-2", "-3"],
      4,
      -6,
      6,
      true,
      HalfEven,
      "-1.000E+6",
      ".......c",
    ),
    ("power", ["0.01", "-2"], 4, -6, 6, true, HalfEven, "1.0E+4", ".......c"),
    ("power", ["-1E+1", "2"], 5, -3, 3, true, HalfEven, "100.0", ".......c"),
    ("power", ["0.01", "-2"], 4, -6, 6, true, Down, "1.0E+4", ".......c"),
    ("power", ["-1E-2", "-2"], 4, -6, 6, true, HalfEven, "1.0E+4", ".......c"),
    ("power", ["-1E+1", "1"], 3, -3, 1, true, HalfEven, "-10.0", ".......c"),
    ("power", ["1E+3", "1"], 5, -3, 3, true, Down, "1000.0", ".......c"),
    ("power", ["0.01", "-3"], 4, -6, 6, true, Down, "1.000E+6", ".......c"),
    ("power", ["1E-6", "-1"], 4, -6, 6, true, HalfEven, "1.000E+6", ".......c"),
    ("power", ["-1E+2", "1"], 5, -3, 3, true, HalfEven, "-100.0", ".......c"),
    (
      "power",
      ["1E+12", "8"],
      7,
      -95,
      96,
      true,
      HalfEven,
      "1.000000E+96",
      ".......c",
    ),
    ("power", ["-1E+3", "2"], 4, -6, 6, true, Down, "1.000E+6", ".......c"),
    ("power", ["1E-2", "-2"], 4, -6, 6, true, HalfEven, "1.0E+4", ".......c"),
    ("power", ["1E+2", "1"], 5, -3, 3, true, Down, "100.0", ".......c"),
    ("power", ["-1E+1", "4"], 4, -6, 6, true, Down, "1.0E+4", ".......c"),
    ("power", ["-1E+3", "1"], 5, -3, 3, true, HalfEven, "-1000.0", ".......c"),
    ("power", ["-1E+1", "5"], 4, -6, 6, true, HalfEven, "-1.00E+5", ".......c"),
    (
      "power",
      ["-1E+12", "8"],
      7,
      -95,
      96,
      true,
      Down,
      "1.000000E+96",
      ".......c",
    ),
    ("power", ["-1E+1", "1"], 5, -3, 3, true, HalfEven, "-10.0", ".......c"),
    ("power", ["-1E+1", "5"], 4, -6, 6, true, Down, "-1.00E+5", ".......c"),
    ("power", ["-1E+2", "1"], 5, -3, 3, true, Down, "-100.0", ".......c"),
    ("power", ["-1E+3", "2"], 4, -6, 6, true, HalfEven, "1.000E+6", ".......c"),
    ("power", ["1E+5", "1"], 4, -6, 6, true, Down, "1.00E+5", ".......c"),
    ("power", ["-1E+1", "3"], 5, -3, 3, true, HalfEven, "-1000.0", ".......c"),
  ]
  issue287_check(rows)
}
