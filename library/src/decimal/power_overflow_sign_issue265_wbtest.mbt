///|
fn issue265_flags_text(flags : DecimalFlags) -> String {
  (if flags.inexact { "x" } else { "." }) +
  (if flags.invalid_operation { "i" } else { "." }) +
  (if flags.division_by_zero { "z" } else { "." }) +
  (if flags.overflow { "o" } else { "." }) +
  (if flags.underflow { "u" } else { "." })
}

///|
fn issue265_mode_name(mode : DecimalRound) -> String {
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
fn issue265_run(
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
  (issue265_value_text(value), issue265_flags_text(flags))
}

///|
fn issue265_value_text(value : Decimal) -> String {
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
fn issue265_check(
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
    let id = "\{op} \{args_text} p=\{precision} emin=\{e_min} emax=\{e_max} clamp=\{clamp} \{issue265_mode_name(mode)}"
    let by_ctx = issue265_run(
      op, args, precision, e_min, e_max, clamp, extended, mode,
    )
    assert_eq((id, by_ctx), (id, (expected, expected_flags)))
  }
}

///|
/// IEEE 754-2019 7.4: an overflow carries the sign of the intermediate result, which
/// for an even integral exponent is positive whatever the sign of the base (the same
/// rule as GDA 1.70 *power*). An overflowing reciprocal must not carry the base's
/// sign into the result. Expected values: Python `decimal` (libmpdec 4.0.0) as
/// oracle, checked against the clauses by hand; the oracle is not the standard.

///|
// oracle: A
// source: 35 rows: 32 re-derived with Python decimal (libmpdec) re-run on 2026-11-26 with the context of each row (precision, Emin, Emax, clamp, rounding), library-ran: no and 3 (-0^-2, -0^-3 and 0^-3 at precision 5) that agree with Python in value and differ only in the divideByZero flag, which is written from IEEE Std 754-2019 9.2.1 (pow(+-0, y) is infinite and signals divideByZero for y < 0; GDA does not signal it); the overflow carries the sign of the power (7.4, GDA 1.70 power): a negative base with an even negative exponent overflows to +infinity or the largest finite number, with an odd one to -infinity or its negative; the flags text is written from the five condition letters x (inexact), i (invalid), z (divideByZero), o (overflow), u (underflow)
// shares: issue265_check builds the context with DecimalContext::new and with_round and reads the operands with Decimal::from_string; issue265_run and the text helpers run and print; pow_ctx is the code under test
test "power overflows with the sign of the power, not of the reciprocal (#265)" {
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
    // GDA 1.70, power: "The sign of the result will be 1 only if the right-hand side has an
    // integral value and is odd (and is not infinite) and also the sign of the left-hand
    // side is 1. In all other cases, the sign of the result will be 0." A negative base
    // with an even negative exponent overflows to +Infinity (or the largest finite
    // number in the directed modes, GDA 1.70, Overflow), not to -Infinity.
    ("power", ["-7E-2", "-8"], 3, -1, 2, true, HalfEven, "Infinity", "x..o."),
    ("power", ["-7E-2", "-8"], 3, -1, 2, true, Down, "999", "x..o."),
    ("power", ["-7E-2", "-8"], 3, -1, 2, true, Ceiling, "Infinity", "x..o."),
    ("power", ["-7E-2", "-8"], 3, -1, 2, true, Floor, "999", "x..o."),
    ("power", ["-1E-20", "-6"], 7, -95, 96, true, HalfEven, "Infinity", "x..o."),
    ("power", ["-1E-20", "-6"], 7, -95, 96, true, HalfUp, "Infinity", "x..o."),
    ("power", ["-1E-20", "-6"], 7, -95, 96, true, Down, "9.999999E+96", "x..o."),
    ("power", ["-1E-20", "-6"], 7, -95, 96, true, Ceiling, "Infinity", "x..o."),
    (
      "power",
      ["-1E-20", "-6"],
      7,
      -95,
      96,
      true,
      Floor,
      "9.999999E+96",
      "x..o.",
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
      "x..o.",
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
      "x..o.",
    ),
    // An odd negative exponent keeps the sign of a negative base: the overflow is
    // -Infinity (or -Nmax). A positive base never gives a negative result.
    (
      "power",
      ["-1E-20", "-5"],
      7,
      -95,
      96,
      true,
      HalfEven,
      "-Infinity",
      "x..o.",
    ),
    ("power", ["-1E-20", "-5"], 7, -95, 96, true, HalfUp, "-Infinity", "x..o."),
    (
      "power",
      ["-1E-20", "-5"],
      7,
      -95,
      96,
      true,
      Down,
      "-9.999999E+96",
      "x..o.",
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
      "x..o.",
    ),
    ("power", ["-1E-20", "-5"], 7, -95, 96, true, Floor, "-Infinity", "x..o."),
    // Positive exponents and underflow: the zero or tiny result carries the sign of the
    // power (GDA 1.70, power; Underflow: "with the sign of the intermediate result").
    // Nearest modes and Down only: the directed-away modes are covered by
    // power_underflow_rounding_issue168_wbtest.mbt.
    ("power", ["-1E+20", "5"], 7, -95, 96, true, HalfEven, "-Infinity", "x..o."),
    ("power", ["-1E+20", "5"], 7, -95, 96, true, HalfUp, "-Infinity", "x..o."),
    ("power", ["-1E+20", "5"], 7, -95, 96, true, Down, "-9.999999E+96", "x..o."),
    ("power", ["-1E+20", "6"], 7, -95, 96, true, HalfEven, "Infinity", "x..o."),
    ("power", ["-1E+20", "6"], 7, -95, 96, true, HalfUp, "Infinity", "x..o."),
    ("power", ["-1E+20", "6"], 7, -95, 96, true, Down, "9.999999E+96", "x..o."),
    // Zero base: "If the left-hand operand is a zero, the result will be exact and will be
    // infinite if the right-hand side is negative or 0 if the right-hand side is positive";
    // the sign is 1 for an odd power of -0 (IEEE 754-2019 9.2.1, pown).
    ("power", ["-0", "-2"], 5, -95, 96, true, HalfEven, "Infinity", "..z.."),
    ("power", ["-0", "-3"], 5, -95, 96, true, HalfEven, "-Infinity", "..z.."),
    ("power", ["0", "-3"], 5, -95, 96, true, HalfEven, "Infinity", "..z.."),
    ("power", ["-0", "2"], 5, -95, 96, true, HalfEven, "0", "....."),
    ("power", ["-0", "3"], 5, -95, 96, true, HalfEven, "-0", "....."),
    // An exponent beyond the nine digits of the repeated-multiplication path takes the
    // large-coefficient route of the decimal package; its overflowing reciprocal has to give the
    // same sign by parity (IEEE 754-2019 7.4, 9.2.1: pow behaves as pown for an integral y).
    (
      "power",
      ["-1E-5", "-99999999999998"],
      7,
      -95,
      96,
      true,
      HalfEven,
      "Infinity",
      "x..o.",
    ),
    (
      "power",
      ["-1E-5", "-99999999999998"],
      7,
      -95,
      96,
      true,
      Down,
      "9.999999E+96",
      "x..o.",
    ),
    (
      "power",
      ["-1E-5", "-99999999999998"],
      7,
      -95,
      96,
      true,
      Ceiling,
      "Infinity",
      "x..o.",
    ),
    (
      "power",
      ["-1E-5", "-99999999999998"],
      7,
      -95,
      96,
      true,
      Floor,
      "9.999999E+96",
      "x..o.",
    ),
    (
      "power",
      ["-1E-5", "-99999999999999"],
      7,
      -95,
      96,
      true,
      HalfEven,
      "-Infinity",
      "x..o.",
    ),
    (
      "power",
      ["-1E-5", "-99999999999999"],
      7,
      -95,
      96,
      true,
      Down,
      "-9.999999E+96",
      "x..o.",
    ),
    (
      "power",
      ["-1E-5", "-99999999999999"],
      7,
      -95,
      96,
      true,
      Ceiling,
      "-9.999999E+96",
      "x..o.",
    ),
    (
      "power",
      ["-1E-5", "-99999999999999"],
      7,
      -95,
      96,
      true,
      Floor,
      "-Infinity",
      "x..o.",
    ),
  ]
  issue265_check(rows)
}
