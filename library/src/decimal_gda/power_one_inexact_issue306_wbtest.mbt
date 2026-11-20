///|
fn issue306_flags_text(flags : DecimalFlags) -> String {
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
fn issue306_gda_flags_text(flags : GdaFlags) -> String {
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
fn issue306_mode_name(mode : DecimalRoundingMode) -> String {
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
fn issue306_gda_mode(mode : DecimalRoundingMode) -> GdaRoundingMode {
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
fn issue306_run(
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
    rounding=issue306_gda_mode(mode),
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
    (issue306_value_text(value), issue306_flags_text(flags)),
    (
      issue306_value_text(outcome.value()),
      issue306_gda_flags_text(outcome.raised()),
    ),
  )
}

///|
fn issue306_value_text(value : Decimal) -> String {
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
fn issue306_check(
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
    let id = "\{op} \{args_text} p=\{precision} emin=\{e_min} emax=\{e_max} clamp=\{clamp} \{issue306_mode_name(mode)}"
    let (by_ctx, by_gda) = issue306_run(
      op, args, precision, e_min, e_max, clamp, extended, mode,
    )
    assert_eq((id, by_ctx), (id, (expected, expected_flags)))
    assert_eq((id, by_gda), (id, (expected, expected_flags)))
  }
}

///|
/// GDA 1.70 *power*: the result is inexact unless the exponent is integral and the result exact, so
/// 1^1.03 is `1.0000 Inexact Rounded` at precision 5. Expected values: Python `decimal` (libmpdec 4.0.0)
/// as oracle, checked against the clause by hand; the oracle is not the specification.
test "the power of 1 to a non-integer exponent is inexact whatever Emax is (#306)" {
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
    // GDA 1.70, power: "In cases not covered above, the result will be inexact unless the right-hand side has
    // an integral value and the result is finite and can be expressed exactly within precision digits." The
    // power of a base of value 1 and a non-integral exponent is therefore inexact, with `precision` digits (the
    // official corpus: powx2017 `power 1 1.01 -> 1.00 Inexact Rounded`). The shortcut for a huge exponent
    // took any exponent whose adjusted exponent is at least Emax, and with a small Emax (here 0) that is
    // 1.03: the result was the exact 1 (and Clamped under clamp). Row .3705 of the random differential
    // (seed 20261118, decimal_gda-power) is the last row of the group.
    ("power", ["1", "1.03"], 5, -1, 0, true, HalfEven, "1.0000", "xr......"),
    ("power", ["1", "1.03"], 5, -1, 0, true, HalfUp, "1.0000", "xr......"),
    ("power", ["1", "1.03"], 5, -1, 0, true, HalfDown, "1.0000", "xr......"),
    ("power", ["1", "1.03"], 5, -1, 0, true, Down, "1.0000", "xr......"),
    ("power", ["1", "1.03"], 5, -1, 0, true, Ceiling, "1.0000", "xr......"),
    ("power", ["1", "1.03"], 5, -1, 0, true, Floor, "1.0000", "xr......"),
    ("power", ["1", "1.03"], 5, -1, 0, true, Up, "1.0000", "xr......"),
    ("power", ["1", "1.03"], 5, -1, 0, true, ZeroFiveUp, "1.0000", "xr......"),
    ("power", ["1", "1.03"], 5, -1, 0, false, HalfEven, "1.0000", "xr......"),
    ("power", ["1", "1.03"], 5, -1, 0, false, HalfUp, "1.0000", "xr......"),
    ("power", ["1", "1.03"], 5, -1, 0, false, HalfDown, "1.0000", "xr......"),
    ("power", ["1", "1.03"], 5, -1, 0, false, Down, "1.0000", "xr......"),
    ("power", ["1", "1.03"], 5, -1, 0, false, Ceiling, "1.0000", "xr......"),
    ("power", ["1", "1.03"], 5, -1, 0, false, Floor, "1.0000", "xr......"),
    ("power", ["1", "1.03"], 5, -1, 0, false, Up, "1.0000", "xr......"),
    ("power", ["1", "1.03"], 5, -1, 0, false, ZeroFiveUp, "1.0000", "xr......"),
    ("power", ["1.0", "-1.03"], 5, -1, 0, true, HalfEven, "1.0000", "xr......"),
    ("power", ["1.0", "-1.03"], 5, -1, 0, true, Down, "1.0000", "xr......"),
    (
      "power",
      ["1.00000", "2.5"],
      5,
      -3,
      3,
      true,
      HalfEven,
      "1.0000",
      "xr......",
    ),
    ("power", ["1.00000", "2.5"], 5, -3, 3, true, Down, "1.0000", "xr......"),
    ("power", ["1", "1.03"], 3, 0, 0, false, HalfEven, "1.00", "xr......"),
    ("power", ["1", "1.03"], 1, 0, 0, false, HalfEven, "1", "xr......"),
    ("power", ["1", "1.03"], 1, 0, 0, false, Up, "1", "xr......"),
    ("power", ["1", "12.3"], 3, -5, 1, true, HalfEven, "1.00", "xr......"),
    (
      "power",
      ["1.00000000000000000000000", "1.03"],
      5,
      -1,
      0,
      true,
      HalfEven,
      "1.0000",
      "xr......",
    ),
    // The same base with the exponent beyond the adjusted exponent of Emax in a large context, and
    // with a bigger Emax, is unchanged (and the exact power of an integral exponent stays exact).
    (
      "power",
      ["1", "1.03"],
      5,
      -999,
      999,
      false,
      HalfEven,
      "1.0000",
      "xr......",
    ),
    ("power", ["1", "1.03"], 5, -3, 3, true, HalfEven, "1.0000", "xr......"),
    ("power", ["1", "2"], 5, -1, 0, true, HalfEven, "1", "........"),
    ("power", ["1", "3.0"], 5, -1, 0, false, HalfEven, "1", "........"),
  ]
  issue306_check(rows)
}
