///|
fn issue342_flags_text(flags : DecimalFlags) -> String {
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
fn issue342_mode_name(mode : DecimalRoundingMode) -> String {
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
/// Runs one row through `Decimal::*_ctx`, returning `(value, flags)` text.
fn issue342_run(
  op : String,
  args : Array[String],
  precision : Int32,
  e_min : Int32,
  e_max : Int32,
  clamp : Bool,
  extended : Bool,
  mode : DecimalRoundingMode,
) -> (String, String) {
  let ctx = DecimalContext::new(
    precision~,
    decimal_rounding=mode,
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
  (issue342_value_text(value), issue342_flags_text(flags))
}

///|
fn issue342_value_text(value : Decimal) -> String {
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
fn issue342_check(
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
    let id = "\{op} \{args_text} p=\{precision} emin=\{e_min} emax=\{e_max} clamp=\{clamp} \{issue342_mode_name(mode)}"
    let by_ctx = issue342_run(
      op, args, precision, e_min, e_max, clamp, extended, mode,
    )
    assert_eq((id, by_ctx), (id, (expected, expected_flags)))
  }
}

///|
/// IEEE 754-2019 7.5: for decimal formats tininess is detected before rounding, on the exact
/// result, and underflow is signaled when the tiny result is inexact. The same rows as the
/// decimal_gda regression (#342); this package already delivers them. The rows cover negative
/// and positive exponents, the `-9.E+0` spelling, signs, clamp, and every rounding mode.
/// Expected values and flags: Python `decimal` (libmpdec 4.0.0); the oracle is not the
/// standard, and rows where it decides tininess after rounding, or rounds a directed mode
/// one unit away from the exact power, are left out.
test "an inexact subnormal integer power raises Underflow (#342)" {
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
    (
      "power",
      ["10.000000000000000000000000001", "-9"],
      23,
      -1,
      1,
      false,
      HalfEven,
      "1.00000000000000E-9",
      "xr...us.",
    ),
    (
      "power",
      ["10.000000000000000000000000001", "-9"],
      23,
      -1,
      1,
      false,
      HalfUp,
      "1.00000000000000E-9",
      "xr...us.",
    ),
    (
      "power",
      ["10.000000000000000000000000001", "-9"],
      23,
      -1,
      1,
      false,
      HalfDown,
      "1.00000000000000E-9",
      "xr...us.",
    ),
    (
      "power",
      ["10.000000000000000000000000001", "-9"],
      23,
      -1,
      1,
      false,
      Ceiling,
      "1.00000000000000E-9",
      "xr...us.",
    ),
    (
      "power",
      ["10.000000000000000000000000001", "-9"],
      23,
      -1,
      1,
      false,
      Up,
      "1.00000000000000E-9",
      "xr...us.",
    ),
    (
      "power",
      ["10.000000000000000000000000001", "-9.E+0"],
      23,
      -1,
      1,
      false,
      HalfEven,
      "1.00000000000000E-9",
      "xr...us.",
    ),
    (
      "power",
      ["10.000000000000000000000000001", "-9"],
      23,
      -1,
      1,
      true,
      HalfEven,
      "1.00000000000000E-9",
      "xr...us.",
    ),
    (
      "power",
      ["-10.000000000000000000000000001", "-9"],
      23,
      -1,
      1,
      false,
      HalfEven,
      "-1.00000000000000E-9",
      "xr...us.",
    ),
    (
      "power",
      ["-10.000000000000000000000000001", "-8"],
      23,
      -1,
      1,
      false,
      HalfEven,
      "1.000000000000000E-8",
      "xr...us.",
    ),
    (
      "power",
      ["-10.000000000000000000000000001", "-8"],
      23,
      -1,
      1,
      false,
      Up,
      "1.000000000000000E-8",
      "xr...us.",
    ),
    (
      "power",
      ["10.000000000000000000000000001", "-9"],
      5,
      -1,
      1,
      false,
      HalfEven,
      "0.00000",
      "xr...usc",
    ),
    (
      "power",
      ["10.000000000000000000000000001", "-9"],
      5,
      -1,
      1,
      false,
      HalfUp,
      "0.00000",
      "xr...usc",
    ),
    (
      "power",
      ["10.000000000000000000000000001", "-9"],
      5,
      -1,
      1,
      false,
      HalfDown,
      "0.00000",
      "xr...usc",
    ),
    (
      "power",
      ["10.000000000000000000000000001", "-9"],
      5,
      -1,
      1,
      false,
      Down,
      "0.00000",
      "xr...usc",
    ),
    (
      "power",
      ["10.000000000000000000000000001", "-9"],
      5,
      -1,
      1,
      false,
      Ceiling,
      "0.00001",
      "xr...us.",
    ),
    (
      "power",
      ["10.000000000000000000000000001", "-9"],
      5,
      -1,
      1,
      false,
      Floor,
      "0.00000",
      "xr...usc",
    ),
    (
      "power",
      ["10.000000000000000000000000001", "-9"],
      5,
      -1,
      1,
      false,
      Up,
      "0.00001",
      "xr...us.",
    ),
    (
      "power",
      ["10.000000000000000000000000001", "-9"],
      5,
      -1,
      1,
      false,
      ZeroFiveUp,
      "0.00001",
      "xr...us.",
    ),
    (
      "power",
      ["0.0999999999999999999999999991", "9"],
      23,
      -1,
      1,
      false,
      HalfEven,
      "1.00000000000000E-9",
      "xr...us.",
    ),
    (
      "power",
      ["0.0999999999999999999999999991", "9"],
      23,
      -1,
      1,
      false,
      HalfUp,
      "1.00000000000000E-9",
      "xr...us.",
    ),
    (
      "power",
      ["0.0999999999999999999999999991", "9"],
      23,
      -1,
      1,
      false,
      HalfDown,
      "1.00000000000000E-9",
      "xr...us.",
    ),
    (
      "power",
      ["0.0999999999999999999999999991", "9"],
      23,
      -1,
      1,
      false,
      Ceiling,
      "1.00000000000000E-9",
      "xr...us.",
    ),
    (
      "power",
      ["0.0999999999999999999999999991", "9"],
      23,
      -1,
      1,
      false,
      Up,
      "1.00000000000000E-9",
      "xr...us.",
    ),
    (
      "power",
      ["0.0999999999999999999999999991", "9"],
      5,
      -1,
      1,
      false,
      HalfEven,
      "0.00000",
      "xr...usc",
    ),
    (
      "power",
      ["0.10000000000000000000000001", "9"],
      23,
      -1,
      1,
      false,
      HalfEven,
      "1.00000000000000E-9",
      "xr...us.",
    ),
    (
      "power",
      ["0.10000000000000000000000001", "9"],
      5,
      -1,
      1,
      false,
      HalfEven,
      "0.00000",
      "xr...usc",
    ),
    (
      "power",
      ["0.10000000000000000000000001", "9.E+0"],
      5,
      -1,
      1,
      false,
      HalfEven,
      "0.00000",
      "xr...usc",
    ),
    (
      "power",
      ["3.000000000000000000000001", "-30"],
      10,
      -10,
      5,
      false,
      HalfEven,
      "4.8569E-15",
      "xr...us.",
    ),
    (
      "power",
      ["3.000000000000000000000001", "-30"],
      10,
      -10,
      5,
      false,
      Ceiling,
      "4.8570E-15",
      "xr...us.",
    ),
    (
      "power",
      ["3.000000000000000000000001", "30"],
      10,
      -10,
      500,
      false,
      HalfEven,
      "2.058911321E+14",
      "xr......",
    ),
  ]
  issue342_check(rows)
}
