///|
fn issue305_flags_text(flags : DecimalFlags) -> String {
  (if flags.inexact { "x" } else { "." }) +
  (if flags.invalid_operation { "i" } else { "." }) +
  (if flags.division_by_zero { "z" } else { "." }) +
  (if flags.overflow { "o" } else { "." }) +
  (if flags.underflow { "u" } else { "." })
}

///|
fn issue305_mode_name(mode : DecimalRound) -> String {
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
fn issue305_run(
  op : String,
  args : Array[String],
  precision : Int32,
  _e_min : Int32,
  e_max : Int32,
  _clamp : Bool,
  _extended : Bool,
  mode : DecimalRound,
) -> (String, String) {
  let ctx = DecimalContext::new(precision~, e_max~).with_round(mode)
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
  (issue305_value_text(value), issue305_flags_text(flags))
}

///|
fn issue305_value_text(value : Decimal) -> String {
  if value.is_infinite() {
    if value.is_sign_minus() {
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
      DecimalRound,
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
    let by_ctx = issue305_run(
      op, args, precision, e_min, e_max, clamp, extended, mode,
    )
    assert_eq((id, by_ctx), (id, (expected, expected_flags)))
  }
}

///|
/// An inexact result is delivered with `precision` digits, whose exponent is at most Etop, so it is
/// never folded down: `Clamped` is not signaled. Expected values: Python `decimal` (libmpdec 4.0.0)
/// as oracle, checked against the package contract by hand (IEEE 754 has no clamped condition); the oracle is not the specification.
/// The package has no Clamped flag (IEEE 754 has none): what these rows observe is the delivered value and cohort member (the fold-down itself); the Clamped flag is asserted by the same rows in `decimal_gda`'s test of the same name.

///|
// oracle: A
// source: 8 rows re-derived with Python decimal (libmpdec) re-run on 2026-11-26 with the context of each row (precision, Emin, Emax, clamp, rounding), library-ran: no: all 8 agree (GDA 1.70: an inexact result has exactly precision digits, so its exponent is at most Etop and nothing is folded down); the flags text is written from the five condition letters x (inexact), i (invalid), z (divideByZero), o (overflow), u (underflow)
// shares: issue305_check builds the context with DecimalContext::new and with_round and reads the operands with Decimal::from_string; issue305_run, issue305_value_text, issue305_flags_text and issue305_mode_name run and print; pow_ctx is the code under test
test "an inexact integer power that rounds to a power of ten is delivered with precision digits, not folded down (#305)" {
  let rows : Array[
    (
      String,
      Array[String],
      Int32,
      Int32,
      Int32,
      Bool,
      DecimalRound,
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
      ["000999999900000000000000000E-27", "-6"],
      4,
      -17,
      18,
      true,
      HalfEven,
      "1.000E+18",
      "x....",
    ),
    (
      "power",
      ["000999999900000000000000000E-27", "-6"],
      4,
      -17,
      18,
      true,
      HalfUp,
      "1.000E+18",
      "x....",
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
      "x....",
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
      "x....",
    ),
    // Clamped still occurs when the exponent of an exact result is above Etop (not touched): (-1E+1)^1 at
    // precision 3, Emax 1 under clamp (Etop -1) is -10.0 Clamped; an exact 10^3 at precision 2 only
    // drops a zero (1.0E+3 Rounded) and is not altered to fit.
    ("power", ["-1E+1", "1"], 3, 0, 1, true, HalfEven, "-10.0", "....."),
    ("power", ["-1E+1", "1"], 3, 0, 1, true, HalfUp, "-10.0", "....."),
    ("power", ["10", "3"], 2, -2, 3, true, HalfEven, "1.0E+3", "....."),
    ("power", ["10", "3"], 2, -2, 3, true, HalfUp, "1.0E+3", "....."),
  ]
  issue305_check(rows)
}
