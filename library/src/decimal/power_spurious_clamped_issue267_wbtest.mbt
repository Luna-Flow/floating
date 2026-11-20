///|
fn issue267_flags_text(flags : DecimalFlags) -> String {
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
fn issue267_mode_name(mode : DecimalRoundingMode) -> String {
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
fn issue267_run(
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
  (issue267_value_text(value), issue267_flags_text(flags))
}

///|
fn issue267_value_text(value : Decimal) -> String {
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
fn issue267_check(
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
    let id = "\{op} \{args_text} p=\{precision} emin=\{e_min} emax=\{e_max} clamp=\{clamp} \{issue267_mode_name(mode)}"
    let by_ctx = issue267_run(
      op, args, precision, e_min, e_max, clamp, extended, mode,
    )
    assert_eq((id, by_ctx), (id, (expected, expected_flags)))
  }
}

///|
/// The working-precision arithmetic of the integer power must not leak a fold-down of its own
/// into the flags: the `clamped` condition of the package is signaled only when the delivered
/// exponent was altered (a package condition, IEEE 754-2019 has no clause for it). Expected values:
/// Python `decimal` (libmpdec 4.0.0) as oracle, checked against the package contract by hand; the
/// oracle is not the standard.
test "power signals Clamped only when the result exponent was altered (#267)" {
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
    // GDA 1.70, Exceptional conditions, Clamped: "This occurs and signals clamped if the exponent
    // of a result has been altered in order to fit the constraints of a specific concrete
    // representation." An inexact power whose rounded result already fits the exponent range
    // (here Etop = Emax - p + 1 = 0) is not altered: no Clamped.
    ("power", ["6E-1", "2"], 1, -1, 0, true, HalfEven, "0.4", "xr......"),
    ("power", ["6E-1", "2"], 1, -1, 0, true, HalfUp, "0.4", "xr......"),
    ("power", ["6E-1", "2"], 1, -1, 0, true, HalfDown, "0.4", "xr......"),
    ("power", ["6E-1", "2"], 1, -1, 0, true, Down, "0.3", "xr......"),
    ("power", ["6E-1", "2"], 1, -1, 0, true, Ceiling, "0.4", "xr......"),
    ("power", ["6E-1", "2"], 1, -1, 0, true, Floor, "0.3", "xr......"),
    ("power", ["6E-1", "2"], 1, -1, 0, true, Up, "0.4", "xr......"),
    ("power", ["6E-1", "2"], 1, -1, 0, true, ZeroFiveUp, "0.3", "xr......"),
    ("power", ["6E-1", "2"], 1, -1, 0, false, HalfEven, "0.4", "xr......"),
    ("power", ["6E-1", "2"], 1, -1, 0, false, HalfUp, "0.4", "xr......"),
    ("power", ["6E-1", "2"], 1, -1, 0, false, HalfDown, "0.4", "xr......"),
    ("power", ["-0.5", "3"], 2, -3, 1, true, HalfEven, "-0.12", "xr......"),
    ("power", ["-0.5", "3"], 2, -3, 1, true, HalfUp, "-0.13", "xr......"),
    ("power", ["-0.5", "3"], 2, -3, 1, true, HalfDown, "-0.12", "xr......"),
    ("power", ["-0.5", "8"], 2, -3, 1, true, HalfEven, "0.0039", "xr......"),
    ("power", ["-0.5", "8"], 2, -3, 1, true, HalfUp, "0.0039", "xr......"),
    ("power", ["-0.5", "8"], 2, -3, 1, true, HalfDown, "0.0039", "xr......"),
    ("power", ["-0.5", "9"], 2, -3, 1, true, HalfEven, "-0.0020", "xr......"),
    ("power", ["-0.5", "9"], 2, -3, 1, true, HalfUp, "-0.0020", "xr......"),
    ("power", ["-0.5", "9"], 2, -3, 1, true, HalfDown, "-0.0020", "xr......"),
    ("power", ["-9.99", "1"], 2, -3, 1, true, HalfEven, "-10", "xr......"),
    ("power", ["-9.99", "1"], 2, -3, 1, true, HalfUp, "-10", "xr......"),
    ("power", ["-9.99", "1"], 2, -3, 1, true, HalfDown, "-10", "xr......"),
    ("power", ["6E-1", "-3"], 2, -3, 3, true, HalfEven, "4.6", "xr......"),
    ("power", ["6E-1", "-3"], 2, -3, 3, true, HalfUp, "4.6", "xr......"),
    ("power", ["6E-1", "-3"], 2, -3, 3, true, HalfDown, "4.6", "xr......"),
    // The same for exact results: the repeated multiplication 1 / -0.5 = -2, squared, is
    // exactly 4 and fits Etop, so there is neither Clamped nor Rounded.
    ("power", ["-0.5", "-2"], 1, 0, 0, true, HalfEven, "4", "........"),
    ("power", ["-0.5", "-2"], 1, 0, 0, true, HalfUp, "4", "........"),
    ("power", ["-0.5", "-2"], 1, 0, 0, true, HalfDown, "4", "........"),
    ("power", ["-0.5", "-2"], 1, -1, 0, true, HalfEven, "4", "........"),
    ("power", ["-0.5", "-2"], 1, -1, 0, true, HalfUp, "4", "........"),
    ("power", ["-0.5", "-2"], 1, -1, 0, true, HalfDown, "4", "........"),
    ("power", ["-0.5", "-3.0"], 1, 0, 0, true, HalfEven, "-8", "........"),
    // Overflow is not a clamp: the result is Infinity or the largest finite number and
    // the exponent of the result was not altered to fit.
    ("power", ["-9.99", "2"], 2, -3, 1, true, HalfEven, "Infinity", "xr..o..."),
    ("power", ["-9.99", "2"], 2, -3, 1, true, HalfUp, "Infinity", "xr..o..."),
    ("power", ["-9.99", "2"], 2, -3, 1, true, HalfDown, "Infinity", "xr..o..."),
    ("power", ["-9.99", "1"], 1, 0, 0, true, HalfEven, "-Infinity", "xr..o..."),
    ("power", ["-9.99", "1"], 1, 0, 0, true, HalfUp, "-Infinity", "xr..o..."),
    ("power", ["-9.99", "1"], 1, 0, 0, true, HalfDown, "-Infinity", "xr..o..."),
    ("power", ["9.99", "3"], 1, 0, 0, true, HalfEven, "Infinity", "xr..o..."),
    ("power", ["9.99", "3"], 1, 0, 0, true, HalfUp, "Infinity", "xr..o..."),
    ("power", ["9.99", "3"], 1, 0, 0, true, HalfDown, "Infinity", "xr..o..."),
    // Clamped still occurs when the exponent of the delivered result is above Etop and
    // the result is folded down (here p = 3, Emax = 2, Etop = 0).
    ("power", ["2E+1", "1"], 3, -2, 2, true, HalfEven, "20", ".......c"),
    ("power", ["2E+1", "1"], 3, -2, 2, true, HalfUp, "20", ".......c"),
    ("power", ["2E+1", "1"], 3, -2, 2, true, HalfDown, "20", ".......c"),
    ("power", ["2E+1", "2"], 3, -2, 2, true, HalfEven, "400", ".......c"),
    ("power", ["2E+1", "2"], 3, -2, 2, true, HalfUp, "400", ".......c"),
    ("power", ["2E+1", "2"], 3, -2, 2, true, HalfDown, "400", ".......c"),
    ("power", ["1.5E+1", "2"], 3, -2, 2, true, HalfEven, "225", "........"),
    ("power", ["1.5E+1", "2"], 3, -2, 2, true, HalfUp, "225", "........"),
    ("power", ["1.5E+1", "2"], 3, -2, 2, true, HalfDown, "225", "........"),
    ("power", ["1.2E+1", "2"], 3, -2, 2, true, HalfEven, "144", "........"),
    ("power", ["1.2E+1", "2"], 3, -2, 2, true, HalfUp, "144", "........"),
    ("power", ["1.2E+1", "2"], 3, -2, 2, true, HalfDown, "144", "........"),
  ]
  issue267_check(rows)
}
