///|
fn issue284_flags_text(flags : DecimalFlags) -> String {
  (if flags.inexact { "x" } else { "." }) +
  (if flags.invalid_operation { "i" } else { "." }) +
  (if flags.division_by_zero { "z" } else { "." }) +
  (if flags.overflow { "o" } else { "." }) +
  (if flags.underflow { "u" } else { "." })
}

///|
fn issue284_mode_name(mode : DecimalRound) -> String {
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
fn issue284_run(
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
  (issue284_value_text(value), issue284_flags_text(flags))
}

///|
fn issue284_value_text(value : Decimal) -> String {
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
fn issue284_check(
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
    let id = "\{op} \{args_text} p=\{precision} emin=\{e_min} emax=\{e_max} clamp=\{clamp} \{issue284_mode_name(mode)}"
    let by_ctx = issue284_run(
      op, args, precision, e_min, e_max, clamp, extended, mode,
    )
    assert_eq((id, by_ctx), (id, (expected, expected_flags)))
  }
}

///|
/// IEEE 754-2019 5.2 and 9.2.2: an exact result has the cohort member closest to the preferred exponent
/// floor(y * Q(x)), so 0.05^-3 is 8E+3, not 8.0E+3. The `rounded` condition of the package is raised
/// only when digits were discarded. Expected values: Python `decimal` (libmpdec 4.0.0) as oracle,
/// checked against the clauses by hand; the oracle is not the standard.
test "an exact negative integer power keeps the cohort of its reciprocal (#284)" {
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
    // The reciprocal that starts a negative power keeps the cohort of the division (1 / 5E-2 is 2E+1, not 20):
    // GDA 1.70, power, takes the exponent of an unrounded result "that which would result if the operation
    // were calculated by repeated multiplication (if the second operand is negative then the reciprocal of
    // the first operand is used)". (2E+1)^8 is 2.56E+10 with three digits and no Rounded; padding the reciprocal
    // towards exponent 0 gave 2.5600E+10 and, at precision 3, Rounded for an exact result. The 50 rows are
    // every failure of an exact-reciprocal grid on main (32 bases, exponents -12..12, precision 1..16, no clamp).
    ("power", ["-0.05", "-3"], 1, -998, 999, true, HalfEven, "-8E+3", "....."),
    ("power", ["-0.05", "-2"], 1, -998, 999, true, HalfEven, "4E+2", "....."),
    ("power", ["0.05", "-3"], 1, -998, 999, true, HalfEven, "8E+3", "....."),
    ("power", ["0.05", "-2"], 1, -998, 999, true, HalfEven, "4E+2", "....."),
    ("power", ["-0.05", "-6"], 2, -998, 999, true, HalfEven, "6.4E+7", "....."),
    ("power", ["-0.05", "-5"], 2, -998, 999, true, HalfEven, "-3.2E+6", "....."),
    ("power", ["-0.05", "-4"], 2, -998, 999, true, HalfEven, "1.6E+5", "....."),
    ("power", ["-0.05", "-3"], 2, -998, 999, true, HalfEven, "-8E+3", "....."),
    ("power", ["0.05", "-6"], 2, -998, 999, true, HalfEven, "6.4E+7", "....."),
    ("power", ["0.05", "-5"], 2, -998, 999, true, HalfEven, "3.2E+6", "....."),
    ("power", ["0.05", "-4"], 2, -998, 999, true, HalfEven, "1.6E+5", "....."),
    ("power", ["0.05", "-3"], 2, -998, 999, true, HalfEven, "8E+3", "....."),
    (
      "power",
      ["-0.05", "-9"],
      3,
      -998,
      999,
      true,
      HalfEven,
      "-5.12E+11",
      ".....",
    ),
    (
      "power",
      ["-0.05", "-8"],
      3,
      -998,
      999,
      true,
      HalfEven,
      "2.56E+10",
      ".....",
    ),
    (
      "power",
      ["-0.05", "-7"],
      3,
      -998,
      999,
      true,
      HalfEven,
      "-1.28E+9",
      ".....",
    ),
    ("power", ["-0.05", "-6"], 3, -998, 999, true, HalfEven, "6.4E+7", "....."),
    ("power", ["-0.05", "-5"], 3, -998, 999, true, HalfEven, "-3.2E+6", "....."),
    ("power", ["0.05", "-9"], 3, -998, 999, true, HalfEven, "5.12E+11", "....."),
    ("power", ["0.05", "-8"], 3, -998, 999, true, HalfEven, "2.56E+10", "....."),
    ("power", ["0.05", "-7"], 3, -998, 999, true, HalfEven, "1.28E+9", "....."),
    ("power", ["0.05", "-6"], 3, -998, 999, true, HalfEven, "6.4E+7", "....."),
    ("power", ["0.05", "-5"], 3, -998, 999, true, HalfEven, "3.2E+6", "....."),
    (
      "power",
      ["-0.05", "-12"],
      4,
      -998,
      999,
      true,
      HalfEven,
      "4.096E+15",
      ".....",
    ),
    (
      "power",
      ["-0.05", "-11"],
      4,
      -998,
      999,
      true,
      HalfEven,
      "-2.048E+14",
      ".....",
    ),
    (
      "power",
      ["-0.05", "-10"],
      4,
      -998,
      999,
      true,
      HalfEven,
      "1.024E+13",
      ".....",
    ),
    (
      "power",
      ["-0.05", "-9"],
      4,
      -998,
      999,
      true,
      HalfEven,
      "-5.12E+11",
      ".....",
    ),
    (
      "power",
      ["-0.05", "-8"],
      4,
      -998,
      999,
      true,
      HalfEven,
      "2.56E+10",
      ".....",
    ),
    (
      "power",
      ["-0.05", "-7"],
      4,
      -998,
      999,
      true,
      HalfEven,
      "-1.28E+9",
      ".....",
    ),
    ("power", ["-0.05", "-6"], 4, -998, 999, true, HalfEven, "6.4E+7", "....."),
    (
      "power",
      ["0.05", "-12"],
      4,
      -998,
      999,
      true,
      HalfEven,
      "4.096E+15",
      ".....",
    ),
    (
      "power",
      ["0.05", "-11"],
      4,
      -998,
      999,
      true,
      HalfEven,
      "2.048E+14",
      ".....",
    ),
    (
      "power",
      ["0.05", "-10"],
      4,
      -998,
      999,
      true,
      HalfEven,
      "1.024E+13",
      ".....",
    ),
    ("power", ["0.05", "-9"], 4, -998, 999, true, HalfEven, "5.12E+11", "....."),
    ("power", ["0.05", "-8"], 4, -998, 999, true, HalfEven, "2.56E+10", "....."),
    ("power", ["0.05", "-7"], 4, -998, 999, true, HalfEven, "1.28E+9", "....."),
    ("power", ["0.05", "-6"], 4, -998, 999, true, HalfEven, "6.4E+7", "....."),
    (
      "power",
      ["-0.05", "-12"],
      5,
      -998,
      999,
      true,
      HalfEven,
      "4.096E+15",
      ".....",
    ),
    (
      "power",
      ["-0.05", "-11"],
      5,
      -998,
      999,
      true,
      HalfEven,
      "-2.048E+14",
      ".....",
    ),
    (
      "power",
      ["-0.05", "-10"],
      5,
      -998,
      999,
      true,
      HalfEven,
      "1.024E+13",
      ".....",
    ),
    (
      "power",
      ["-0.05", "-9"],
      5,
      -998,
      999,
      true,
      HalfEven,
      "-5.12E+11",
      ".....",
    ),
    (
      "power",
      ["-0.05", "-8"],
      5,
      -998,
      999,
      true,
      HalfEven,
      "2.56E+10",
      ".....",
    ),
    (
      "power",
      ["0.05", "-12"],
      5,
      -998,
      999,
      true,
      HalfEven,
      "4.096E+15",
      ".....",
    ),
    (
      "power",
      ["0.05", "-11"],
      5,
      -998,
      999,
      true,
      HalfEven,
      "2.048E+14",
      ".....",
    ),
    (
      "power",
      ["0.05", "-10"],
      5,
      -998,
      999,
      true,
      HalfEven,
      "1.024E+13",
      ".....",
    ),
    ("power", ["0.05", "-9"], 5, -998, 999, true, HalfEven, "5.12E+11", "....."),
    ("power", ["0.05", "-8"], 5, -998, 999, true, HalfEven, "2.56E+10", "....."),
    (
      "power",
      ["-0.05", "-12"],
      7,
      -998,
      999,
      true,
      HalfEven,
      "4.096E+15",
      ".....",
    ),
    (
      "power",
      ["-0.05", "-11"],
      7,
      -998,
      999,
      true,
      HalfEven,
      "-2.048E+14",
      ".....",
    ),
    (
      "power",
      ["0.05", "-12"],
      7,
      -998,
      999,
      true,
      HalfEven,
      "4.096E+15",
      ".....",
    ),
    (
      "power",
      ["0.05", "-11"],
      7,
      -998,
      999,
      true,
      HalfEven,
      "2.048E+14",
      ".....",
    ),
  ]
  issue284_check(rows)
}
