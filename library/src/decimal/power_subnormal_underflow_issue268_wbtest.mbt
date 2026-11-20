///|
fn issue268_flags_text(flags : DecimalFlags) -> String {
  (if flags.inexact { "x" } else { "." }) +
  (if flags.invalid_operation { "i" } else { "." }) +
  (if flags.division_by_zero { "z" } else { "." }) +
  (if flags.overflow { "o" } else { "." }) +
  (if flags.underflow { "u" } else { "." })
}

///|
fn issue268_mode_name(mode : DecimalRound) -> String {
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
fn issue268_run(
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
  (issue268_value_text(value), issue268_flags_text(flags))
}

///|
fn issue268_value_text(value : Decimal) -> String {
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
fn issue268_check(
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
    let id = "\{op} \{args_text} p=\{precision} emin=\{e_min} emax=\{e_max} clamp=\{clamp} \{issue268_mode_name(mode)}"
    let by_ctx = issue268_run(
      op, args, precision, e_min, e_max, clamp, extended, mode,
    )
    assert_eq((id, by_ctx), (id, (expected, expected_flags)))
  }
}

///|
/// IEEE 754-2019 7.5: for decimal formats tininess is detected before rounding, on the exact
/// result. The integer power of the decimal package encloses the exact power between two
/// directed roundings; when the enclosure straddles 10^Emin the side has to be decided by
/// refining it. Expected values: the sides from exact rational arithmetic, the rest from
/// Python `decimal` (libmpdec 4.0.0); the oracle is not the standard.
test "an integer power just below 10^Emin is subnormal although it rounds to 10^Emin (#268)" {
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
      1,
      true,
      HalfEven,
      "1",
      "x...u",
    ),
    (
      "power",
      ["100000000000000000001E-20", "-1"],
      1,
      0,
      1,
      true,
      HalfUp,
      "1",
      "x...u",
    ),
    (
      "power",
      ["1.00000000000000000001", "-1"],
      3,
      0,
      1,
      true,
      HalfEven,
      "1.00",
      "x...u",
    ),
    (
      "power",
      ["0.99999999999999999999", "1"],
      1,
      0,
      1,
      true,
      HalfEven,
      "1",
      "x...u",
    ),
    (
      "power",
      ["1.00000000000000000001", "1"],
      1,
      -998,
      999,
      true,
      HalfEven,
      "1",
      "x....",
    ),
    (
      "power",
      ["1.00000000000000000001", "-2"],
      1,
      0,
      1,
      true,
      HalfEven,
      "1",
      "x...u",
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
      1,
      true,
      HalfUp,
      "1.0",
      "x...u",
    ),
    (
      "power",
      ["-999999999999997E-17", "1"],
      4,
      -2,
      3,
      true,
      HalfUp,
      "-0.01000",
      "x...u",
    ),
    (
      "power",
      ["9999999997E-10", "12"],
      3,
      0,
      1,
      true,
      HalfEven,
      "1.00",
      "x...u",
    ),
    (
      "power",
      ["99999999991E-14", "9"],
      3,
      -27,
      28,
      true,
      HalfUp,
      "1.00E-27",
      "x...u",
    ),
    (
      "power",
      ["9999999E-8", "12"],
      6,
      -12,
      13,
      true,
      HalfEven,
      "1.00000E-12",
      "x...u",
    ),
    (
      "power",
      ["99999999999999999993E-22", "4"],
      3,
      -8,
      9,
      true,
      HalfEven,
      "1.00E-8",
      "x...u",
    ),
    (
      "power",
      ["100000000000000000007E-20", "-9"],
      4,
      0,
      1,
      true,
      HalfEven,
      "1.000",
      "x...u",
    ),
    ("power", ["10001E-2", "-1"], 5, -2, 3, true, HalfEven, "0.009999", "x...u"),
    (
      "power",
      ["99999999999999993E-17", "33"],
      3,
      0,
      1,
      true,
      HalfUp,
      "1.00",
      "x...u",
    ),
    (
      "power",
      ["99999999999999999998E-21", "9"],
      1,
      -9,
      10,
      true,
      HalfEven,
      "1E-9",
      "x...u",
    ),
    (
      "power",
      ["1000000000000000000000008E-24", "-1"],
      5,
      0,
      1,
      true,
      HalfUp,
      "1.0000",
      "x...u",
    ),
    ("power", ["-9996E-6", "1"], 5, -2, 3, true, HalfUp, "-0.009996", "....."),
    // The same family, not tiny (the exact power is above 10^Emin):
    (
      "power",
      ["9999999999999999999999996E-25", "-7"],
      4,
      -998,
      999,
      true,
      HalfUp,
      "1.000",
      "x....",
    ),
    (
      "power",
      ["10000000009E-12", "4"],
      5,
      -2,
      3,
      true,
      HalfUp,
      "0.000000",
      "x...u",
    ),
    (
      "power",
      ["9996E-1", "-9"],
      4,
      -998,
      999,
      true,
      HalfEven,
      "1.004E-27",
      "x....",
    ),
    (
      "power",
      ["1000000000008E-13", "12"],
      5,
      0,
      1,
      true,
      HalfEven,
      "0.0000",
      "x...u",
    ),
    (
      "power",
      ["-100000000000000007E-18", "9"],
      3,
      -2,
      3,
      true,
      HalfUp,
      "-0.0000",
      "x...u",
    ),
    (
      "power",
      ["100000000000000000007E-22", "9"],
      1,
      -998,
      999,
      true,
      HalfEven,
      "1E-18",
      "x....",
    ),
    (
      "power",
      ["100000000000003E-17", "5"],
      5,
      -4,
      5,
      true,
      HalfUp,
      "0E-8",
      "x...u",
    ),
    (
      "power",
      ["-100000000000000000005E-23", "12"],
      3,
      -4,
      5,
      true,
      HalfUp,
      "0.000000",
      "x...u",
    ),
  ]
  issue268_check(rows)
}
