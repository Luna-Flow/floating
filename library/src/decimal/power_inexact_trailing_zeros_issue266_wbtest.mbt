///|
fn issue266_flags_text(flags : DecimalFlags) -> String {
  (if flags.inexact { "x" } else { "." }) +
  (if flags.invalid_operation { "i" } else { "." }) +
  (if flags.division_by_zero { "z" } else { "." }) +
  (if flags.overflow { "o" } else { "." }) +
  (if flags.underflow { "u" } else { "." })
}

///|
fn issue266_mode_name(mode : DecimalRound) -> String {
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
fn issue266_run(
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
  (issue266_value_text(value), issue266_flags_text(flags))
}

///|
fn issue266_value_text(value : Decimal) -> String {
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
fn issue266_check(
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
    let id = "\{op} \{args_text} p=\{precision} emin=\{e_min} emax=\{e_max} clamp=\{clamp} \{issue266_mode_name(mode)}"
    let by_ctx = issue266_run(
      op, args, precision, e_min, e_max, clamp, extended, mode,
    )
    assert_eq((id, by_ctx), (id, (expected, expected_flags)))
  }
}

///|
/// IEEE 754-2019 5.2: an inexact result uses the cohort member of least possible exponent, that
/// is `precision` digits, trailing zeros included (GDA 1.70 says the same) (the cohort member of least possible
/// exponent for an inexact result). Evidence for the convention: the official decTest
/// corpus has 126 inexact power rows whose coefficient ends in 0 and no inexact normal row
/// with fewer than `precision` digits. Expected values: Python `decimal` (libmpdec 4.0.0)
/// as oracle, checked against the clauses by hand; the oracle is not the specification.
test "an inexact integer power keeps precision digits, trailing zeros included (#266)" {
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
    // GDA 1.70, Arithmetic operations, general rules: a result with more digits than the precision
    // is "rounded (shortened) to exactly precision digits", so an inexact result has `precision`
    // digits; IEEE 754-2019 5.2: "if the result is inexact the cohort member of least possible
    // exponent is used to get the maximum number of significant digits". The rows of the issue. Ceiling and Up are not in the table: GDA 1.70 allows an inexact power to
    // be up to 1 ulp off, and there libmpdec and the packages differ in the last digit
    // (999.99999999^-8 is 1.0000000008E-24, 1.01E-24 under Ceiling).
    (
      "power",
      ["999.99999999", "-8"],
      3,
      -96,
      97,
      true,
      HalfEven,
      "1.00E-24",
      "x....",
    ),
    (
      "power",
      ["999.99999999", "-8"],
      3,
      -96,
      97,
      true,
      HalfUp,
      "1.00E-24",
      "x....",
    ),
    (
      "power",
      ["999.99999999", "-8"],
      3,
      -96,
      97,
      true,
      Down,
      "1.00E-24",
      "x....",
    ),
    (
      "power",
      ["999.99999999", "-8"],
      3,
      -96,
      97,
      true,
      Floor,
      "1.00E-24",
      "x....",
    ),
    (
      "power",
      ["999.99999999", "-8"],
      3,
      -96,
      97,
      true,
      HalfEven,
      "1.00E-24",
      "x....",
    ),
    (
      "power",
      ["999.99999999", "-8"],
      3,
      -96,
      97,
      true,
      HalfUp,
      "1.00E-24",
      "x....",
    ),
    // The same for integer powers of other signs and sizes: 1 / 9999.9 rounded to two digits is
    // 0.00010, not 0.0001. Positive and negative exponents, one to six digits of precision.
    (
      "power",
      ["11952E-2", "-2"],
      4,
      -998,
      999,
      true,
      HalfEven,
      "0.00007000",
      "x....",
    ),
    (
      "power",
      ["11952E-2", "-2"],
      4,
      -998,
      999,
      true,
      HalfUp,
      "0.00007000",
      "x....",
    ),
    (
      "power",
      ["20286E-1", "-3"],
      3,
      -998,
      999,
      true,
      HalfEven,
      "1.20E-10",
      "x....",
    ),
    (
      "power",
      ["20286E-1", "-3"],
      3,
      -998,
      999,
      true,
      HalfUp,
      "1.20E-10",
      "x....",
    ),
    (
      "power",
      ["87550E-5", "-8"],
      5,
      -998,
      999,
      true,
      HalfEven,
      "2.8970",
      "x....",
    ),
    ("power", ["87550E-5", "-8"], 5, -998, 999, true, HalfUp, "2.8970", "x...."),
    ("power", ["49790E-5", "-3"], 3, -998, 999, true, HalfEven, "8.10", "x...."),
    ("power", ["49790E-5", "-3"], 3, -998, 999, true, HalfUp, "8.10", "x...."),
    (
      "power",
      ["62964E-1", "-8"],
      2,
      -998,
      999,
      true,
      HalfEven,
      "4.0E-31",
      "x....",
    ),
    (
      "power",
      ["62964E-1", "-8"],
      2,
      -998,
      999,
      true,
      HalfUp,
      "4.0E-31",
      "x....",
    ),
    (
      "power",
      ["97973E2", "-2"],
      2,
      -998,
      999,
      true,
      HalfEven,
      "1.0E-14",
      "x....",
    ),
    ("power", ["97973E2", "-2"], 2, -998, 999, true, HalfUp, "1.0E-14", "x...."),
    (
      "power",
      ["1170E-2", "-4"],
      6,
      -998,
      999,
      true,
      HalfEven,
      "0.0000533650",
      "x....",
    ),
    (
      "power",
      ["1170E-2", "-4"],
      6,
      -998,
      999,
      true,
      HalfUp,
      "0.0000533650",
      "x....",
    ),
    ("power", ["71272E-4", "3"], 4, -998, 999, true, HalfEven, "362.0", "x...."),
    ("power", ["71272E-4", "3"], 4, -998, 999, true, HalfUp, "362.0", "x...."),
    (
      "power",
      ["26843E-3", "7"],
      3,
      -998,
      999,
      true,
      HalfEven,
      "1.00E+10",
      "x....",
    ),
    (
      "power",
      ["26843E-3", "7"],
      3,
      -998,
      999,
      true,
      HalfUp,
      "1.00E+10",
      "x....",
    ),
    (
      "power",
      ["-62964E-1", "-9"],
      2,
      -998,
      999,
      true,
      HalfEven,
      "-6.4E-35",
      "x....",
    ),
    (
      "power",
      ["-62964E-1", "-9"],
      2,
      -998,
      999,
      true,
      HalfUp,
      "-6.4E-35",
      "x....",
    ),
    (
      "power",
      ["79782E1", "5"],
      6,
      -998,
      999,
      true,
      HalfEven,
      "3.23240E+29",
      "x....",
    ),
    (
      "power",
      ["79782E1", "5"],
      6,
      -998,
      999,
      true,
      HalfUp,
      "3.23240E+29",
      "x....",
    ),
    // Padding with clamp: the coefficient trimmed by the rounding sits above Etop = 369 and would
    // be folded down, but the padded coefficient of 16 digits has exponent 363 and nothing was
    // altered to fit, so there is no Clamped (GDA 1.70, Exceptional conditions, Clamped).
    (
      "power",
      ["9999999999999999999999995E-151", "-3"],
      16,
      -383,
      384,
      true,
      HalfEven,
      "1.000000000000000E+378",
      "x....",
    ),
    (
      "power",
      ["9999999999999999999999995E-151", "-3"],
      16,
      -383,
      384,
      true,
      HalfUp,
      "1.000000000000000E+378",
      "x....",
    ),
    // Rows of the official decTest corpus (power.decTest powx028, powx706, powx1186) whose
    // inexact results carry trailing zeros: they pass in the corpus and keep doing so.
    (
      "power",
      ["2", "32"],
      9,
      -999999998,
      999999999,
      true,
      HalfUp,
      "4.29496730E+9",
      "x....",
    ),
    (
      "power",
      ["1234567896", "1"],
      9,
      -999999998,
      999999999,
      true,
      HalfUp,
      "1.23456790E+9",
      "x....",
    ),
    (
      "power",
      ["7", "-1000000001"],
      9,
      -999999998,
      999999999,
      true,
      HalfUp,
      "1.38243630E-845098041",
      "x....",
    ),
  ]
  issue266_check(rows)
}
