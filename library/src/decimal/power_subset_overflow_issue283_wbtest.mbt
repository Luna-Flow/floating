///|
fn issue283_flags_text(flags : DecimalFlags) -> String {
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
fn issue283_mode_name(mode : DecimalRoundingMode) -> String {
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
fn issue283_run(
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
    "power" => x.pow_ctx(y, ctx)
    "plus" => x.plus_ctx(ctx)
    _ => abort("unexpected operation \{op}")
  }
  (issue283_value_text(value), issue283_flags_text(flags))
}

///|
fn issue283_value_text(value : Decimal) -> String {
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
fn issue283_check(
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
    let id = "\{op} \{args_text} p=\{precision} emin=\{e_min} emax=\{e_max} clamp=\{clamp} \{issue283_mode_name(mode)}"
    let by_ctx = issue283_run(
      op, args, precision, e_min, e_max, clamp, extended, mode,
    )
    assert_eq((id, by_ctx), (id, (expected, expected_flags)))
  }
}

///|
/// A non-extended context (`extended: 0`) overflows when the reciprocal of a tiny positive power leaves the
/// working range; the result is the overflow result of the context, not an abort. Expected values:
/// Python `decimal` (libmpdec 4.0.0) for the value and flag set; the oracle is not the specification.
test "a subset-context power whose reciprocal overflows returns the overflow result (#283)" {
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
    // Subset arithmetic (extended: 0, GDA 1.70 Appendix A): a negative power takes the reciprocal of the
    // positive power at the end. A tiny power has a reciprocal beyond the working range: that is an
    // Overflow of the result (GDA 1.70, Exceptional conditions), Infinity or the largest finite
    // number by sign and rounding mode, and it must not abort. Rows: the 71 failing rows of a 20,000
    // row random campaign (seed 818) that aborted with "decimal_apply_finite_ctx expects a finite
    // operand" on main, one per rounding mode and sign.
    (
      "power",
      ["58E-2", "-24"],
      2,
      -6,
      0,
      true,
      HalfEven,
      "Infinity",
      "xr..o...",
    ),
    (
      "power",
      ["-8379611E-7", "-40"],
      3,
      -5,
      2,
      false,
      Up,
      "Infinity",
      "xr..o...",
    ),
    (
      "power",
      ["9999998E-10", "-1"],
      6,
      -6,
      0,
      false,
      Floor,
      "9.99999",
      "xr..o...",
    ),
    (
      "power",
      ["-599999999E-9", "-9"],
      3,
      -6,
      0,
      false,
      Floor,
      "-Infinity",
      "xr..o...",
    ),
    (
      "power",
      ["3726E-5", "-1"],
      3,
      -5,
      0,
      false,
      Ceiling,
      "Infinity",
      "xr..o...",
    ),
    ("power", ["-999E-4", "-3"], 3, -5, 0, false, Ceiling, "-9.99", "xr..o..."),
    (
      "power",
      ["-519E-3", "-12"],
      3,
      -5,
      0,
      false,
      Ceiling,
      "Infinity",
      "xr..o...",
    ),
    (
      "power",
      ["2263472E-7", "-6"],
      3,
      -5,
      0,
      false,
      Ceiling,
      "Infinity",
      "xr..o...",
    ),
    (
      "power",
      ["84136E-5", "-39"],
      3,
      -5,
      0,
      false,
      Ceiling,
      "Infinity",
      "xr..o...",
    ),
    ("power", ["9E-1", "-22"], 3, -2, 0, false, Up, "Infinity", "xr..o..."),
    ("power", ["52E-2", "-4"], 5, -3, 0, false, Floor, "9.9999", "xr..o..."),
    (
      "power",
      ["-59E-3", "-3"],
      4,
      -4,
      0,
      false,
      HalfUp,
      "-Infinity",
      "xr..o...",
    ),
    (
      "power",
      ["-607E-3", "-9"],
      4,
      -4,
      0,
      false,
      HalfUp,
      "-Infinity",
      "xr..o...",
    ),
    (
      "power",
      ["-5999999E-8", "-2"],
      6,
      -5,
      1,
      false,
      HalfEven,
      "Infinity",
      "xr..o...",
    ),
    (
      "power",
      ["-54E-2", "-6"],
      2,
      -2,
      0,
      false,
      HalfEven,
      "Infinity",
      "xr..o...",
    ),
    (
      "power",
      ["-93E-2", "-33"],
      2,
      -2,
      0,
      false,
      HalfEven,
      "-Infinity",
      "xr..o...",
    ),
    (
      "power",
      ["6007821E-7", "-25"],
      3,
      -6,
      0,
      true,
      HalfEven,
      "Infinity",
      "xr..o...",
    ),
    ("power", ["-6E-4", "-1"], 5, -6, 1, false, Down, "-99.999", "xr..o..."),
    (
      "power",
      ["48334866224E-12", "-1"],
      5,
      -4,
      0,
      true,
      ZeroFiveUp,
      "9.9999",
      "xr..o...",
    ),
    (
      "power",
      ["-102295E-9", "-1"],
      5,
      -6,
      0,
      false,
      Up,
      "-Infinity",
      "xr..o...",
    ),
    (
      "power",
      ["-78020E-5", "-24"],
      5,
      -5,
      0,
      true,
      HalfUp,
      "Infinity",
      "xr..o...",
    ),
    ("power", ["79E-3", "-1"], 2, -4, 0, true, HalfDown, "Infinity", "xr..o..."),
  ]
  issue283_check(rows, extended=false)
}
