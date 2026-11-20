///|
fn issue268_flags_text(flags : DecimalFlags) -> String {
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
fn issue268_gda_flags_text(flags : GdaFlags) -> String {
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
fn issue268_mode_name(mode : DecimalRoundingMode) -> String {
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
fn issue268_gda_mode(mode : DecimalRoundingMode) -> GdaRoundingMode {
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
fn issue268_run(
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
    rounding=issue268_gda_mode(mode),
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
    (issue268_value_text(value), issue268_flags_text(flags)),
    (
      issue268_value_text(outcome.value()),
      issue268_gda_flags_text(outcome.raised()),
    ),
  )
}

///|
fn issue268_value_text(value : Decimal) -> String {
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
fn issue268_check(
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
    let id = "\{op} \{args_text} p=\{precision} emin=\{e_min} emax=\{e_max} clamp=\{clamp} \{issue268_mode_name(mode)}"
    let (by_ctx, by_gda) = issue268_run(
      op, args, precision, e_min, e_max, clamp, extended, mode,
    )
    assert_eq((id, by_ctx), (id, (expected, expected_flags)))
    assert_eq((id, by_gda), (id, (expected, expected_flags)))
  }
}

///|
/// GDA 1.70, *Exceptional conditions*, Subnormal and Underflow: tininess is judged on the
/// exact power before rounding. The working arithmetic of the integer power rounds to a
/// finite precision, so the side of the exact power relative to 10^Emin has to be decided
/// separately when the delivered result is exactly 10^Emin. Expected values: the sides from
/// exact rational arithmetic, the rest from Python `decimal` (libmpdec 4.0.0); the oracle is
/// not the specification.
test "an integer power just below 10^Emin is subnormal although it rounds to 10^Emin (#268)" {
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
    // GDA 1.70, Exceptional conditions: Subnormal is signaled when the adjusted exponent of the result
    // is less than Emin "before any rounding", Underflow when the result is also inexact; IEEE 754-2019
    // 7.5 detects tininess before rounding for decimal formats. 1 / 1.00000000000000000001 is
    // 0.99999999999999999999, below 10^0 = 10^Emin, although it rounds to 1 at precision 1. Powers
    // that lie just above 10^Emin (the exact value 1.00000000000000000001) are not tiny.
    (
      "power",
      ["100000000000000000001E-20", "-1"],
      1,
      0,
      999,
      false,
      HalfEven,
      "1",
      "xr...us.",
    ),
    (
      "power",
      ["100000000000000000001E-20", "-1"],
      1,
      0,
      999,
      false,
      HalfUp,
      "1",
      "xr...us.",
    ),
    (
      "power",
      ["100000000000000000001E-20", "-1"],
      1,
      0,
      999,
      false,
      HalfDown,
      "1",
      "xr...us.",
    ),
    (
      "power",
      ["1.00000000000000000001", "-1"],
      3,
      0,
      999,
      true,
      HalfEven,
      "1.00",
      "xr...us.",
    ),
    (
      "power",
      ["0.99999999999999999999", "1"],
      1,
      0,
      999,
      false,
      HalfEven,
      "1",
      "xr...us.",
    ),
    (
      "power",
      ["1.00000000000000000001", "1"],
      1,
      0,
      999,
      false,
      HalfEven,
      "1",
      "xr......",
    ),
    (
      "power",
      ["1.00000000000000000001", "-2"],
      1,
      0,
      999,
      false,
      HalfEven,
      "1",
      "xr...us.",
    ),
    // Powers within a hair of 10^Emin on both sides. Each row's side was decided with exact rational
    // arithmetic (Fraction) on the exact power; the value and the other flags come from Python
    // `decimal` (libmpdec 4.0.0), which does not decide the side itself when the power is closer to
    // 10^Emin than its own working precision. Tiny rows:
    (
      "power",
      ["99999999999999992E-17", "2"],
      2,
      0,
      999,
      true,
      HalfUp,
      "1.0",
      "xr...us.",
    ),
    (
      "power",
      ["-999999999999997E-17", "1"],
      4,
      -2,
      2,
      true,
      HalfUp,
      "-0.01000",
      "xr...us.",
    ),
    (
      "power",
      ["9999999997E-10", "12"],
      3,
      0,
      999,
      false,
      HalfEven,
      "1.00",
      "xr...us.",
    ),
    (
      "power",
      ["999999994E-9", "3"],
      6,
      0,
      0,
      true,
      HalfEven,
      "1.00000",
      "xr...us.",
    ),
    (
      "power",
      ["99999999991E-14", "9"],
      3,
      -27,
      999,
      false,
      HalfUp,
      "1.00E-27",
      "xr...us.",
    ),
    (
      "power",
      ["100000000000000005E-17", "-7"],
      4,
      0,
      2,
      false,
      HalfDown,
      "1.000",
      "xr...us.",
    ),
    (
      "power",
      ["99999999997E-14", "2"],
      2,
      -6,
      999,
      false,
      HalfDown,
      "0.0000010",
      "xr...us.",
    ),
    ("power", ["999999999E-9", "5"], 1, 0, 2, true, HalfDown, "1", "xr...us."),
    (
      "power",
      ["99999999E-10", "3"],
      1,
      -6,
      999,
      true,
      HalfDown,
      "0.000001",
      "xr...us.",
    ),
    (
      "power",
      ["1000000000000008E-14", "-2"],
      1,
      -2,
      1,
      false,
      HalfDown,
      "0.01",
      "xr...us.",
    ),
    (
      "power",
      ["99999999999999999996E-21", "3"],
      1,
      -3,
      999,
      false,
      HalfDown,
      "0.001",
      "xr...us.",
    ),
    (
      "power",
      ["9999999E-8", "12"],
      6,
      -12,
      999,
      false,
      HalfEven,
      "1.00000E-12",
      "xr...us.",
    ),
    (
      "power",
      ["99999999999999999993E-22", "4"],
      3,
      -8,
      1,
      true,
      HalfEven,
      "1.00E-8",
      "xr...us.",
    ),
    (
      "power",
      ["999999999E-12", "9"],
      4,
      -27,
      999,
      false,
      HalfDown,
      "1.000E-27",
      "xr...us.",
    ),
    (
      "power",
      ["100000000000000000007E-20", "-9"],
      4,
      0,
      999,
      false,
      HalfEven,
      "1.000",
      "xr...us.",
    ),
    (
      "power",
      ["10001E-2", "-1"],
      5,
      -2,
      999,
      false,
      HalfEven,
      "0.009999",
      "xr...us.",
    ),
    (
      "power",
      ["99999999999999993E-17", "33"],
      3,
      0,
      999,
      true,
      HalfUp,
      "1.00",
      "xr...us.",
    ),
    (
      "power",
      ["99999999999999999998E-21", "9"],
      1,
      -9,
      999,
      true,
      HalfEven,
      "1E-9",
      "xr...us.",
    ),
    (
      "power",
      ["1000000000000000000000008E-24", "-1"],
      5,
      0,
      999,
      false,
      HalfUp,
      "1.0000",
      "xr...us.",
    ),
    (
      "power",
      ["9999999999999999999997E-23", "1"],
      1,
      -1,
      0,
      false,
      HalfEven,
      "0.1",
      "xr...us.",
    ),
    (
      "power",
      ["-999999999999999999997E-22", "1"],
      5,
      -1,
      0,
      true,
      HalfEven,
      "-0.10000",
      "xr...us.",
    ),
    (
      "power",
      ["-9996E-6", "1"],
      5,
      -2,
      999,
      true,
      HalfUp,
      "-0.009996",
      "......s.",
    ),
    // The same family, not tiny (the exact power is above 10^Emin):
    (
      "power",
      ["9999999999999999999999996E-25", "-7"],
      4,
      0,
      999,
      true,
      HalfUp,
      "1.000",
      "xr......",
    ),
    (
      "power",
      ["10000000009E-12", "4"],
      5,
      -8,
      3,
      false,
      HalfUp,
      "1.0000E-8",
      "xr......",
    ),
    (
      "power",
      ["9996E-1", "-9"],
      4,
      -27,
      999,
      true,
      HalfEven,
      "1.004E-27",
      "xr......",
    ),
    (
      "power",
      ["10000000000000000006E-22", "7"],
      5,
      -21,
      999,
      true,
      HalfDown,
      "1.0000E-21",
      "xr......",
    ),
    (
      "power",
      ["1000000000008E-13", "12"],
      5,
      -12,
      1,
      true,
      HalfEven,
      "1.0000E-12",
      "xr......",
    ),
    (
      "power",
      ["-1000000000000008E-17", "2"],
      1,
      -4,
      4,
      true,
      HalfDown,
      "0.0001",
      "xr......",
    ),
    (
      "power",
      ["-100000000000000007E-18", "9"],
      3,
      -9,
      3,
      false,
      HalfUp,
      "-1.00E-9",
      "xr......",
    ),
    (
      "power",
      ["100000000000000000007E-22", "9"],
      1,
      -18,
      999,
      true,
      HalfEven,
      "1E-18",
      "xr......",
    ),
    (
      "power",
      ["10000000000000002E-17", "5"],
      3,
      -5,
      0,
      true,
      HalfEven,
      "0.0000100",
      "xr......",
    ),
    (
      "power",
      ["100000000000003E-17", "5"],
      5,
      -15,
      5,
      true,
      HalfUp,
      "1.0000E-15",
      "xr......",
    ),
    ("power", ["999992E-6", "-4"], 1, 0, 999, true, HalfDown, "1", "xr......"),
    (
      "power",
      ["10000006E-7", "9"],
      3,
      0,
      999,
      false,
      HalfDown,
      "1.00",
      "xr......",
    ),
    (
      "power",
      ["1000000000000002E-17", "33"],
      1,
      -66,
      999,
      false,
      HalfDown,
      "1E-66",
      "xr......",
    ),
    (
      "power",
      ["-100000000000000000005E-23", "12"],
      3,
      -36,
      5,
      true,
      HalfUp,
      "1.00E-36",
      "xr......",
    ),
  ]
  issue268_check(rows)
}
