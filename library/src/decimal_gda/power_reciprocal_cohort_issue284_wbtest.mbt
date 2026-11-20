///|
fn issue284_flags_text(flags : DecimalFlags) -> String {
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
fn issue284_gda_flags_text(flags : GdaFlags) -> String {
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
fn issue284_mode_name(mode : DecimalRoundingMode) -> String {
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
fn issue284_gda_mode(mode : DecimalRoundingMode) -> GdaRoundingMode {
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
fn issue284_run(
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
  let gda = GdaContext::new(
    precision~,
    rounding=issue284_gda_mode(mode),
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
    (issue284_value_text(value), issue284_flags_text(flags)),
    (
      issue284_value_text(outcome.value()),
      issue284_gda_flags_text(outcome.raised()),
    ),
  )
}

///|
fn issue284_value_text(value : Decimal) -> String {
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
fn issue284_check(
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
    let id = "\{op} \{args_text} p=\{precision} emin=\{e_min} emax=\{e_max} clamp=\{clamp} \{issue284_mode_name(mode)}"
    let (by_ctx, by_gda) = issue284_run(
      op, args, precision, e_min, e_max, clamp, extended, mode,
    )
    assert_eq((id, by_ctx), (id, (expected, expected_flags)))
    assert_eq((id, by_gda), (id, (expected, expected_flags)))
  }
}

///|
/// GDA 1.70, *power*: the exponent of an unrounded result is the one repeated multiplication gives.
/// Expected values: Python `decimal` (libmpdec 4.0.0) as oracle, checked against the clause by hand;
/// the oracle is not the specification.
test "an exact negative integer power keeps the cohort of its reciprocal (#284)" {
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
    // The reciprocal that starts a negative power keeps the cohort of the division (1 / 5E-2 is 2E+1, not 20):
    // GDA 1.70, power, takes the exponent of an unrounded result "that which would result if the operation
    // were calculated by repeated multiplication (if the second operand is negative then the reciprocal of
    // the first operand is used)". (2E+1)^8 is 2.56E+10 with three digits and no Rounded; padding the reciprocal
    // towards exponent 0 gave 2.5600E+10 and, at precision 3, Rounded for an exact result. The 50 rows are
    // every failure of an exact-reciprocal grid on main (32 bases, exponents -12..12, precision 1..16, no clamp).
    (
      "power",
      ["-0.05", "-3"],
      1,
      -999,
      999,
      false,
      HalfEven,
      "-8E+3",
      "........",
    ),
    (
      "power",
      ["-0.05", "-2"],
      1,
      -999,
      999,
      false,
      HalfEven,
      "4E+2",
      "........",
    ),
    ("power", ["0.05", "-3"], 1, -999, 999, false, HalfEven, "8E+3", "........"),
    ("power", ["0.05", "-2"], 1, -999, 999, false, HalfEven, "4E+2", "........"),
    (
      "power",
      ["-0.05", "-6"],
      2,
      -999,
      999,
      false,
      HalfEven,
      "6.4E+7",
      "........",
    ),
    (
      "power",
      ["-0.05", "-5"],
      2,
      -999,
      999,
      false,
      HalfEven,
      "-3.2E+6",
      "........",
    ),
    (
      "power",
      ["-0.05", "-4"],
      2,
      -999,
      999,
      false,
      HalfEven,
      "1.6E+5",
      "........",
    ),
    (
      "power",
      ["-0.05", "-3"],
      2,
      -999,
      999,
      false,
      HalfEven,
      "-8E+3",
      "........",
    ),
    (
      "power",
      ["0.05", "-6"],
      2,
      -999,
      999,
      false,
      HalfEven,
      "6.4E+7",
      "........",
    ),
    (
      "power",
      ["0.05", "-5"],
      2,
      -999,
      999,
      false,
      HalfEven,
      "3.2E+6",
      "........",
    ),
    (
      "power",
      ["0.05", "-4"],
      2,
      -999,
      999,
      false,
      HalfEven,
      "1.6E+5",
      "........",
    ),
    ("power", ["0.05", "-3"], 2, -999, 999, false, HalfEven, "8E+3", "........"),
    (
      "power",
      ["-0.05", "-9"],
      3,
      -999,
      999,
      false,
      HalfEven,
      "-5.12E+11",
      "........",
    ),
    (
      "power",
      ["-0.05", "-8"],
      3,
      -999,
      999,
      false,
      HalfEven,
      "2.56E+10",
      "........",
    ),
    (
      "power",
      ["-0.05", "-7"],
      3,
      -999,
      999,
      false,
      HalfEven,
      "-1.28E+9",
      "........",
    ),
    (
      "power",
      ["-0.05", "-6"],
      3,
      -999,
      999,
      false,
      HalfEven,
      "6.4E+7",
      "........",
    ),
    (
      "power",
      ["-0.05", "-5"],
      3,
      -999,
      999,
      false,
      HalfEven,
      "-3.2E+6",
      "........",
    ),
    (
      "power",
      ["0.05", "-9"],
      3,
      -999,
      999,
      false,
      HalfEven,
      "5.12E+11",
      "........",
    ),
    (
      "power",
      ["0.05", "-8"],
      3,
      -999,
      999,
      false,
      HalfEven,
      "2.56E+10",
      "........",
    ),
    (
      "power",
      ["0.05", "-7"],
      3,
      -999,
      999,
      false,
      HalfEven,
      "1.28E+9",
      "........",
    ),
    (
      "power",
      ["0.05", "-6"],
      3,
      -999,
      999,
      false,
      HalfEven,
      "6.4E+7",
      "........",
    ),
    (
      "power",
      ["0.05", "-5"],
      3,
      -999,
      999,
      false,
      HalfEven,
      "3.2E+6",
      "........",
    ),
    (
      "power",
      ["-0.05", "-12"],
      4,
      -999,
      999,
      false,
      HalfEven,
      "4.096E+15",
      "........",
    ),
    (
      "power",
      ["-0.05", "-11"],
      4,
      -999,
      999,
      false,
      HalfEven,
      "-2.048E+14",
      "........",
    ),
    (
      "power",
      ["-0.05", "-10"],
      4,
      -999,
      999,
      false,
      HalfEven,
      "1.024E+13",
      "........",
    ),
    (
      "power",
      ["-0.05", "-9"],
      4,
      -999,
      999,
      false,
      HalfEven,
      "-5.12E+11",
      "........",
    ),
    (
      "power",
      ["-0.05", "-8"],
      4,
      -999,
      999,
      false,
      HalfEven,
      "2.56E+10",
      "........",
    ),
    (
      "power",
      ["-0.05", "-7"],
      4,
      -999,
      999,
      false,
      HalfEven,
      "-1.28E+9",
      "........",
    ),
    (
      "power",
      ["-0.05", "-6"],
      4,
      -999,
      999,
      false,
      HalfEven,
      "6.4E+7",
      "........",
    ),
    (
      "power",
      ["0.05", "-12"],
      4,
      -999,
      999,
      false,
      HalfEven,
      "4.096E+15",
      "........",
    ),
    (
      "power",
      ["0.05", "-11"],
      4,
      -999,
      999,
      false,
      HalfEven,
      "2.048E+14",
      "........",
    ),
    (
      "power",
      ["0.05", "-10"],
      4,
      -999,
      999,
      false,
      HalfEven,
      "1.024E+13",
      "........",
    ),
    (
      "power",
      ["0.05", "-9"],
      4,
      -999,
      999,
      false,
      HalfEven,
      "5.12E+11",
      "........",
    ),
    (
      "power",
      ["0.05", "-8"],
      4,
      -999,
      999,
      false,
      HalfEven,
      "2.56E+10",
      "........",
    ),
    (
      "power",
      ["0.05", "-7"],
      4,
      -999,
      999,
      false,
      HalfEven,
      "1.28E+9",
      "........",
    ),
    (
      "power",
      ["0.05", "-6"],
      4,
      -999,
      999,
      false,
      HalfEven,
      "6.4E+7",
      "........",
    ),
    (
      "power",
      ["-0.05", "-12"],
      5,
      -999,
      999,
      false,
      HalfEven,
      "4.096E+15",
      "........",
    ),
    (
      "power",
      ["-0.05", "-11"],
      5,
      -999,
      999,
      false,
      HalfEven,
      "-2.048E+14",
      "........",
    ),
    (
      "power",
      ["-0.05", "-10"],
      5,
      -999,
      999,
      false,
      HalfEven,
      "1.024E+13",
      "........",
    ),
    (
      "power",
      ["-0.05", "-9"],
      5,
      -999,
      999,
      false,
      HalfEven,
      "-5.12E+11",
      "........",
    ),
    (
      "power",
      ["-0.05", "-8"],
      5,
      -999,
      999,
      false,
      HalfEven,
      "2.56E+10",
      "........",
    ),
    (
      "power",
      ["0.05", "-12"],
      5,
      -999,
      999,
      false,
      HalfEven,
      "4.096E+15",
      "........",
    ),
    (
      "power",
      ["0.05", "-11"],
      5,
      -999,
      999,
      false,
      HalfEven,
      "2.048E+14",
      "........",
    ),
    (
      "power",
      ["0.05", "-10"],
      5,
      -999,
      999,
      false,
      HalfEven,
      "1.024E+13",
      "........",
    ),
    (
      "power",
      ["0.05", "-9"],
      5,
      -999,
      999,
      false,
      HalfEven,
      "5.12E+11",
      "........",
    ),
    (
      "power",
      ["0.05", "-8"],
      5,
      -999,
      999,
      false,
      HalfEven,
      "2.56E+10",
      "........",
    ),
    (
      "power",
      ["-0.05", "-12"],
      7,
      -999,
      999,
      false,
      HalfEven,
      "4.096E+15",
      "........",
    ),
    (
      "power",
      ["-0.05", "-11"],
      7,
      -999,
      999,
      false,
      HalfEven,
      "-2.048E+14",
      "........",
    ),
    (
      "power",
      ["0.05", "-12"],
      7,
      -999,
      999,
      false,
      HalfEven,
      "4.096E+15",
      "........",
    ),
    (
      "power",
      ["0.05", "-11"],
      7,
      -999,
      999,
      false,
      HalfEven,
      "2.048E+14",
      "........",
    ),
  ]
  issue284_check(rows)
}
