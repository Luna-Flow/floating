///|
// White-box tests of exp2m1, exp10m1, log2p1 and log10p1 (issue #236).
// The clause quotes are from IEEE Std 754-2019; the generated table
// `elementary_pm1_rows_wbtest.mbt` holds the exact and MPFR-certified rows.

///|
fn pm1_flags_text(flags : DecimalFlags) -> String {
  let builder = StringBuilder()
  if flags.inexact() {
    builder.write_char('x')
  }
  if flags.overflow() {
    builder.write_char('o')
  }
  if flags.underflow() {
    builder.write_char('u')
  }
  if flags.invalid_operation() {
    builder.write_char('v')
  }
  if flags.division_by_zero() {
    builder.write_char('z')
  }
  let text = builder.to_string()
  if text.length() == 0 {
    "-"
  } else {
    text
  }
}

///|
fn pm1_rounding(name : String) -> DecimalRound {
  match name {
    "half_even" => HalfEven
    "half_up" => HalfUp
    "half_down" => HalfDown
    "down" => Down
    "ceiling" => Ceiling
    "floor" => Floor
    "up" => Up
    "05up" => ZeroFiveUp
    _ => abort("unknown rounding " + name)
  }
}

///|
let pm1_modes : Array[String] = [
  "half_even", "half_up", "half_down", "down", "ceiling", "floor", "up", "05up",
]

///|
fn pm1_try(
  op : String,
  x : Decimal,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  match op {
    "exp2m1" => x.try_exp2m1_ctx(ctx)
    "exp10m1" => x.try_exp10m1_ctx(ctx)
    "log2p1" => x.try_log2p1_ctx(ctx)
    "log10p1" => x.try_log10p1_ctx(ctx)
    _ => abort("unknown operation " + op)
  }
}

///|
fn pm1_call(op : String, x : Decimal, ctx : DecimalContext) -> String {
  match pm1_try(op, x, ctx) {
    Ok((value, flags)) => "\{value} \{pm1_flags_text(flags)}"
    Err(_) => "certification-failure"
  }
}

///|
fn pm1_exact(text : String) -> Decimal {
  Decimal::from_string(text, precision=Int32::max(1, text.length())).unwrap()
}

///|
fn pm1_ctx(
  precision : Int32,
  rounding : String,
  e_min : Int32,
  e_max : Int32,
  clamp : Bool,
  tininess : String,
) -> DecimalContext {
  // The context is built from the precision and `e_max` only: the other columns of the
  // row must say the same thing, or the row is not a context of this package (IEEE 754-2019
  // 3.3: `e_min = 1 - e_max`, every result a member of the format, 7.5: tininess before
  // rounding) and the expected value was computed for something this test does not run.
  if e_min != 1 - e_max || !clamp || tininess != "b" {
    abort(
      "row context is not an IEEE format: precision=\{precision} e_min=\{e_min} e_max=\{e_max} clamp=\{clamp} tininess=\{tininess}",
    )
  }
  DecimalContext::new(precision~, e_max~).with_round(pm1_rounding(rounding))
}

///|
/// The context of the previous row: consecutive rows of the generated tables
/// share it, so it is rebuilt only when a parameter changes.
let pm1_ctx_last : Ref[
  (Int32, String, Int32, Int32, Bool, String, DecimalContext)?,
] = Ref(None)

///|
fn pm1_ctx_cached(
  precision : Int32,
  rounding : String,
  e_min : Int32,
  e_max : Int32,
  clamp : Bool,
  tininess : String,
) -> DecimalContext {
  match pm1_ctx_last.val {
    Some((p, r, lo, hi, c, t, ctx)) if p == precision &&
      r == rounding &&
      lo == e_min &&
      hi == e_max &&
      c == clamp &&
      t == tininess => ctx
    _ => {
      let ctx = pm1_ctx(precision, rounding, e_min, e_max, clamp, tininess)
      pm1_ctx_last.val = Some(
        (precision, rounding, e_min, e_max, clamp, tininess, ctx),
      )
      ctx
    }
  }
}

///|
let pm1_ops : Array[String] = ["exp2m1", "exp10m1", "log2p1", "log10p1"]

///|
test "pm1 generated rows: exact and MPFR-certified results, cohort and flags" {
  let failures = StringBuilder()
  let mut count = 0
  let rows = pm1_rows()
  for row in rows {
    let (
      op,
      rounding,
      precision,
      e_min,
      e_max,
      clamp,
      tininess,
      x,
      expected,
      flags,
    ) = row
    let ctx = pm1_ctx_cached(precision, rounding, e_min, e_max, clamp, tininess)
    let want = pm1_exact(expected)
    match pm1_try(op, pm1_exact(x), ctx) {
      Ok((value, actual_flags)) =>
        if value.total_order_compare(want) != 0 ||
          pm1_flags_text(actual_flags) != flags {
          count += 1
          if count <= 20 {
            failures.write_string(
              "\{op} \{rounding} p=\{precision} [\{e_min},\{e_max}] clamp=\{clamp} \{tininess} x=\{x}: want \{expected} \{flags}, got \{value} \{pm1_flags_text(actual_flags)}\n",
            )
          }
        }
      Err(_) => {
        count += 1
        if count <= 20 {
          failures.write_string(
            "\{op} \{rounding} p=\{precision} x=\{x}: certification failure\n",
          )
        }
      }
    }
  }
  inspect(failures.to_string(), content="")
  assert_true(rows.length() > 7000)
}

///|
test "pm1 special values follow 9.2.1 in every rounding mode" {
  // IEEE 754-2019 9.2.1: "For the operations sin, tan, ..., expm1, exp2m1,
  // exp10m1, logp1, log2p1, and log10p1, f(+0) is +0 and f(-0) is -0 with no
  // exception."
  // "For the operations expm1, exp2m1, and exp10m1, f(+inf) is +inf and
  // f(-inf) is -1 with no exception."
  // "For the operations log, log2, log10, logp1, log2p1, and log10p1, f(+inf)
  // is +inf with no exception." "For the operations logp1, log2p1, and
  // log10p1, f(-1) is -inf and signals the divideByZero exception."
  // Table 9.1: the domain of log2p1 and log10p1 is [-1, +inf];
  // "x < -1: invalid operation"; 9.2: "Outside its domain an operation shall
  // return a quiet NaN and signal the invalid operation exception."
  // 9.2.2: "The preferred exponent for operations in sub-clause 9.2 is 0", so
  // the zero results are 0E0 whatever the exponent of the zero operand.
  for mode in pm1_modes {
    for
      spec in [
        (7, -95, 96, true),
        (16, -383, 384, true),
        (5, -999998, 999999, true),
      ] {
      let (precision, e_min, e_max, clamp) = spec
      let ctx = pm1_ctx(precision, mode, e_min, e_max, clamp, "b")
      let out = StringBuilder()
      for op in pm1_ops {
        for x in ["0", "-0", "0E-7", "-0E+3", "Infinity", "-Infinity"] {
          out.write_string("\{op}(\{x}) = \{pm1_call(op, pm1_exact(x), ctx)}\n")
        }
      }
      for op in ["log2p1", "log10p1"] {
        for x in ["-1", "-1.000000", "-1.000001", "-2", "-1E+50", "-10"] {
          out.write_string("\{op}(\{x}) = \{pm1_call(op, pm1_exact(x), ctx)}\n")
        }
      }
      inspect(
        out.to_string(),
        content=(
          #|exp2m1(0) = 0 -
          #|exp2m1(-0) = -0 -
          #|exp2m1(0E-7) = 0 -
          #|exp2m1(-0E+3) = -0 -
          #|exp2m1(Infinity) = inf -
          #|exp2m1(-Infinity) = -1 -
          #|exp10m1(0) = 0 -
          #|exp10m1(-0) = -0 -
          #|exp10m1(0E-7) = 0 -
          #|exp10m1(-0E+3) = -0 -
          #|exp10m1(Infinity) = inf -
          #|exp10m1(-Infinity) = -1 -
          #|log2p1(0) = 0 -
          #|log2p1(-0) = -0 -
          #|log2p1(0E-7) = 0 -
          #|log2p1(-0E+3) = -0 -
          #|log2p1(Infinity) = inf -
          #|log2p1(-Infinity) = nan v
          #|log10p1(0) = 0 -
          #|log10p1(-0) = -0 -
          #|log10p1(0E-7) = 0 -
          #|log10p1(-0E+3) = -0 -
          #|log10p1(Infinity) = inf -
          #|log10p1(-Infinity) = nan v
          #|log2p1(-1) = -inf z
          #|log2p1(-1.000000) = -inf z
          #|log2p1(-1.000001) = nan v
          #|log2p1(-2) = nan v
          #|log2p1(-1E+50) = nan v
          #|log2p1(-10) = nan v
          #|log10p1(-1) = -inf z
          #|log10p1(-1.000000) = -inf z
          #|log10p1(-1.000001) = nan v
          #|log10p1(-2) = nan v
          #|log10p1(-1E+50) = nan v
          #|log10p1(-10) = nan v
          #|
        ),
      )
    }
  }
}

///|
test "pm1 NaN operands: quiet NaN propagates, signaling NaN signals invalid" {
  // IEEE 754-2019 9.2: "An operation that returns a floating-point result
  // shall return a quiet NaN as a result if there is a signaling NaN among the
  // operation's operands." "For all operations, signaling NaN operands shall
  // signal the invalid operation exception." 6.2.3: an operation that
  // propagates a NaN operand "should produce a NaN with the payload of the
  // input NaN if representable in the destination format"; a clamped
  // (interchange-shaped) format holds at most p - 1 payload digits (3.5.2).
  // 6.3 does not specify the sign of a NaN result; the decimal package keeps
  // the operand's sign, as for every other operation.
  let out = StringBuilder()
  for ctx in [DecimalContext::decimal32(), DecimalContext::decimal64()] {
    for op in pm1_ops {
      for
        x in ["NaN", "-NaN", "NaN123", "-NaN7", "sNaN", "-sNaN45", "NaN1234567"] {
        out.write_string("\{op}(\{x}) = \{pm1_call(op, pm1_exact(x), ctx)}\n")
      }
    }
  }
  inspect(
    out.to_string(),
    content=(
      #|exp2m1(NaN) = nan -
      #|exp2m1(-NaN) = -nan -
      #|exp2m1(NaN123) = nan123 -
      #|exp2m1(-NaN7) = -nan7 -
      #|exp2m1(sNaN) = nan v
      #|exp2m1(-sNaN45) = -nan45 v
      #|exp2m1(NaN1234567) = nan234567 -
      #|exp10m1(NaN) = nan -
      #|exp10m1(-NaN) = -nan -
      #|exp10m1(NaN123) = nan123 -
      #|exp10m1(-NaN7) = -nan7 -
      #|exp10m1(sNaN) = nan v
      #|exp10m1(-sNaN45) = -nan45 v
      #|exp10m1(NaN1234567) = nan234567 -
      #|log2p1(NaN) = nan -
      #|log2p1(-NaN) = -nan -
      #|log2p1(NaN123) = nan123 -
      #|log2p1(-NaN7) = -nan7 -
      #|log2p1(sNaN) = nan v
      #|log2p1(-sNaN45) = -nan45 v
      #|log2p1(NaN1234567) = nan234567 -
      #|log10p1(NaN) = nan -
      #|log10p1(-NaN) = -nan -
      #|log10p1(NaN123) = nan123 -
      #|log10p1(-NaN7) = -nan7 -
      #|log10p1(sNaN) = nan v
      #|log10p1(-sNaN45) = -nan45 v
      #|log10p1(NaN1234567) = nan234567 -
      #|exp2m1(NaN) = nan -
      #|exp2m1(-NaN) = -nan -
      #|exp2m1(NaN123) = nan123 -
      #|exp2m1(-NaN7) = -nan7 -
      #|exp2m1(sNaN) = nan v
      #|exp2m1(-sNaN45) = -nan45 v
      #|exp2m1(NaN1234567) = nan1234567 -
      #|exp10m1(NaN) = nan -
      #|exp10m1(-NaN) = -nan -
      #|exp10m1(NaN123) = nan123 -
      #|exp10m1(-NaN7) = -nan7 -
      #|exp10m1(sNaN) = nan v
      #|exp10m1(-sNaN45) = -nan45 v
      #|exp10m1(NaN1234567) = nan1234567 -
      #|log2p1(NaN) = nan -
      #|log2p1(-NaN) = -nan -
      #|log2p1(NaN123) = nan123 -
      #|log2p1(-NaN7) = -nan7 -
      #|log2p1(sNaN) = nan v
      #|log2p1(-sNaN45) = -nan45 v
      #|log2p1(NaN1234567) = nan1234567 -
      #|log10p1(NaN) = nan -
      #|log10p1(-NaN) = -nan -
      #|log10p1(NaN123) = nan123 -
      #|log10p1(-NaN7) = -nan7 -
      #|log10p1(sNaN) = nan v
      #|log10p1(-sNaN45) = -nan45 v
      #|log10p1(NaN1234567) = nan1234567 -
      #|
    ),
  )
}

///|
test "pm1 restricted contexts and operands give invalid_context" {
  // The decimal math functions share the decNumber limits: a precision or an
  // exponent bound beyond 999,999, or an operand outside
  // `decimal_math_operand_out_of_range` (adjusted exponent below -1,999,997 or
  // above 999,999), is InvalidContext (as exp and ln).
  let wide = DecimalContext::new(precision=16, e_max=1_000_000)
  let ctx = DecimalContext::new(precision=16, e_max=999_999)
  let out = StringBuilder()
  for op in pm1_ops {
    out.write_string("\{op} \{pm1_call(op, pm1_exact("0.5"), wide)} ")
    out.write_string("\{pm1_call(op, pm1_exact("1E-1999998"), ctx)} ")
    out.write_string("\{pm1_call(op, pm1_exact("1E+1000000"), ctx)} ")
    // The least legal operand: adjusted exponent -1,999,997.
    out.write_string("\{pm1_call(op, pm1_exact("-1E-1999997"), ctx)}\n")
  }
  inspect(
    out.to_string(),
    content=(
      #|exp2m1 nan v nan v nan v -0E-1000013 xu
      #|exp10m1 nan v nan v nan v -0E-1000013 xu
      #|log2p1 nan v nan v nan v -0E-1000013 xu
      #|log10p1 nan v nan v nan v -0E-1000013 xu
      #|
    ),
  )
}

///|
test "pm1 exact results take the preferred exponent 0 (9.2.2)" {
  // IEEE 754-2019 9.2.2: "The preferred exponent for operations in sub-clause
  // 9.2 is 0" (exp2m1, exp10m1, log2p1 and log10p1 are not among the
  // exceptions). 5.2: "If the result is exact, the cohort member is selected
  // based on the preferred exponent ... If the result's cohort does not
  // include a member with the preferred exponent, the member with the
  // exponent closest to the preferred exponent is used."
  let ctx = DecimalContext::decimal64()
  let out = StringBuilder()
  for
    pair in [
      ("exp2m1", "1"),
      ("exp2m1", "1.000"),
      ("exp2m1", "10E-1"),
      ("exp2m1", "4"),
      ("exp2m1", "-1"),
      ("exp2m1", "-4"),
      ("exp2m1", "5E+1"),
      ("exp10m1", "2"),
      ("exp10m1", "-2.0"),
      ("exp10m1", "-0.1E+1"),
      ("log2p1", "1"),
      ("log2p1", "1.0"),
      ("log2p1", "1023"),
      ("log2p1", "-0.5"),
      ("log2p1", "-0.50"),
      ("log2p1", "-0.9375"),
      ("log10p1", "9"),
      ("log10p1", "9.00"),
      ("log10p1", "999999999"),
      ("log10p1", "-0.9"),
      ("log10p1", "-0.99000"),
    ] {
    let (op, x) = pair
    out.write_string("\{op}(\{x}) = \{pm1_call(op, pm1_exact(x), ctx)}\n")
  }
  inspect(
    out.to_string(),
    content=(
      #|exp2m1(1) = 1 -
      #|exp2m1(1.000) = 1 -
      #|exp2m1(10E-1) = 1 -
      #|exp2m1(4) = 15 -
      #|exp2m1(-1) = -0.5 -
      #|exp2m1(-4) = -0.9375 -
      #|exp2m1(5E+1) = 1125899906842623 -
      #|exp10m1(2) = 99 -
      #|exp10m1(-2.0) = -0.99 -
      #|exp10m1(-0.1E+1) = -0.9 -
      #|log2p1(1) = 1 -
      #|log2p1(1.0) = 1 -
      #|log2p1(1023) = 10 -
      #|log2p1(-0.5) = -1 -
      #|log2p1(-0.50) = -1 -
      #|log2p1(-0.9375) = -4 -
      #|log10p1(9) = 1 -
      #|log10p1(9.00) = 1 -
      #|log10p1(999999999) = 9 -
      #|log10p1(-0.9) = -1 -
      #|log10p1(-0.99000) = -2 -
      #|
    ),
  )
}

///|
test "pm1 log of 1 is not a special rule: log2p1(1) = 1, log10p1(1) inexact" {
  // 9.2.1 states f(1) = +0 only for log, log2 and log10; for log2p1 the
  // argument 1 means 1 + x = 2, an exact result 1 (and an inexact one for
  // log10p1).
  let ctx = DecimalContext::decimal32()
  inspect(pm1_call("log2p1", pm1_exact("1"), ctx), content="1 -")
  inspect(
    pm1_call("log10p1", pm1_exact("1"), ctx),
    content=(
      #|0.3010300 x
    ),
  )
}

///|
test "pm1 zero results keep the sign of the operand in every mode" {
  // A result below half the smallest subnormal rounds to a zero (or the
  // smallest subnormal) of the sign of the exact result, which is the sign of
  // x for all four functions. IEEE 754-2019 4.3: "Inexact numeric
  // floating-point results always have the same sign as the unrounded
  // result." Underflow, Subnormal and Inexact are raised; never a replaced
  // zero.
  let out = StringBuilder()
  for mode in pm1_modes {
    let ctx = pm1_ctx(16, mode, -383, 384, true, "b")
    for op in pm1_ops {
      out.write_string(
        "\{mode} \{op} \{pm1_call(op, pm1_exact("1E-1999996"), ctx)} \{pm1_call(op, pm1_exact("-1E-1999996"), ctx)}\n",
      )
    }
  }
  inspect(
    out.to_string(),
    content=(
      #|half_even exp2m1 0E-398 xu -0E-398 xu
      #|half_even exp10m1 0E-398 xu -0E-398 xu
      #|half_even log2p1 0E-398 xu -0E-398 xu
      #|half_even log10p1 0E-398 xu -0E-398 xu
      #|half_up exp2m1 0E-398 xu -0E-398 xu
      #|half_up exp10m1 0E-398 xu -0E-398 xu
      #|half_up log2p1 0E-398 xu -0E-398 xu
      #|half_up log10p1 0E-398 xu -0E-398 xu
      #|half_down exp2m1 0E-398 xu -0E-398 xu
      #|half_down exp10m1 0E-398 xu -0E-398 xu
      #|half_down log2p1 0E-398 xu -0E-398 xu
      #|half_down log10p1 0E-398 xu -0E-398 xu
      #|down exp2m1 0E-398 xu -0E-398 xu
      #|down exp10m1 0E-398 xu -0E-398 xu
      #|down log2p1 0E-398 xu -0E-398 xu
      #|down log10p1 0E-398 xu -0E-398 xu
      #|ceiling exp2m1 1E-398 xu -0E-398 xu
      #|ceiling exp10m1 1E-398 xu -0E-398 xu
      #|ceiling log2p1 1E-398 xu -0E-398 xu
      #|ceiling log10p1 1E-398 xu -0E-398 xu
      #|floor exp2m1 0E-398 xu -1E-398 xu
      #|floor exp10m1 0E-398 xu -1E-398 xu
      #|floor log2p1 0E-398 xu -1E-398 xu
      #|floor log10p1 0E-398 xu -1E-398 xu
      #|up exp2m1 1E-398 xu -1E-398 xu
      #|up exp10m1 1E-398 xu -1E-398 xu
      #|up log2p1 1E-398 xu -1E-398 xu
      #|up log10p1 1E-398 xu -1E-398 xu
      #|05up exp2m1 1E-398 xu -1E-398 xu
      #|05up exp10m1 1E-398 xu -1E-398 xu
      #|05up log2p1 1E-398 xu -1E-398 xu
      #|05up log10p1 1E-398 xu -1E-398 xu
      #|
    ),
  )
}

///|
/// The top binary exponent of a nonzero finite value: |v| in [2^top, 2^(top+1)).
fn pm1_top(value : @bin_float.BinFloat) -> Int64 {
  value.exponent2().to_int64() +
  (value.coefficient().bit_length() - 1).to_int64()
}

///|
test "pm1 enclosures stay relatively tight down to 10^-1999997" {
  // The m1/p1 functions are built on expm1 and log1p, series in x, so the
  // enclosure of f(x) keeps a relative width of a few ulps of the working
  // precision for every legal operand (no cancellation near zero, design note
  // of #236): at w = 200 bits the endpoints agree to at least 190 bits.
  let up = @bin_float.BinaryContext::new(
    precision=64,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardPositive,
  )
  let ops : Array[DecimalPm1] = [Exp2m1, Exp10m1, Log2p1, Log10p1]
  // The binary conversion of 10^-1999997 is the expensive step: once per x.
  for text in ["1E-20000", "-3E-300000", "-1E-1999997"] {
    let x = pm1_exact(text)
    let input = decimal_to_certified_ball(x, 200)
    for op in ops {
      let interval = op.evaluate(input).unwrap()
      let lower = interval.lower_bound()
      let upper = interval.upper_bound()
      assert_eq(lower.is_negative(), x.negative, msg="\{op.name()} \{text}")
      assert_eq(upper.is_negative(), x.negative, msg="\{op.name()} \{text}")
      let width = upper.sub_ctx(lower, up).0
      assert_true(
        width.is_zero() || pm1_top(width) <= pm1_top(lower) - 190L,
        msg="\{op.name()} \{text}",
      )
    }
  }
}

///|
test "pm1 log poles: operands with D digits just above -1 at D = 52, 500, 5000" {
  // Near -1, log1p amplifies the input error by |x| / (1 + x) >= 10^-D; the
  // working precision 4 max(D, p) + 64 bits keeps the enclosure off the pole.
  for digits in [52, 500, 5000] {
    let ctx = DecimalContext::decimal64()
    let x = Decimal::from_string(
      "-0." + String::make(digits - 1, '9') + "1",
      precision=digits,
    ).unwrap()
    let two = x.try_log2p1_ctx(ctx).unwrap()
    let ten = x.try_log10p1_ctx(ctx).unwrap()
    // log2(10^-D * 1.0...) ~ -3.3219 D and log10 ~ -D.
    assert_true(two.0.negative && two.1.inexact())
    assert_true(ten.0.negative && ten.1.inexact())
    // 1 + x = 9 * 10^-D: log10p1(x) = -D + log10(9) lies in (-D, -D + 1).
    let low = Decimal::from_int(-digits, precision=16)
    let high = Decimal::from_int(1 - digits, precision=16)
    assert_true(ten.0.compare(low) > 0 && ten.0.compare(high) < 0)
  }
}

///|
test "pm1 the 10^n - 1 cluster is decided without forming 10^n" {
  // exp10m1(n) = 10^n - 1 for n far above 4 (p + 2) lies just below the
  // representable 10^n; an enclosure cannot separate them, so the
  // representative 10^n - 10^(n - p - 2) decides it (same open rounding
  // cell). A context with e_max = 999,999 makes 10^999999 - 1 a 1,000,000-digit
  // value that is never expanded.
  let out = StringBuilder()
  for mode in pm1_modes {
    let ctx = pm1_ctx(16, mode, -999_998, 999_999, true, "b")
    out.write_string(
      "\{mode} \{pm1_call("exp10m1", pm1_exact("999999"), ctx)} \{pm1_call("exp10m1", pm1_exact("1000000"), ctx)}\n",
    )
  }
  inspect(
    out.to_string(),
    content=(
      #|half_even 1.000000000000000E+999999 x inf xo
      #|half_up 1.000000000000000E+999999 x inf xo
      #|half_down 1.000000000000000E+999999 x inf xo
      #|down 9.999999999999999E+999998 x 9.999999999999999E+999999 x
      #|ceiling 1.000000000000000E+999999 x inf xo
      #|floor 9.999999999999999E+999998 x 9.999999999999999E+999999 x
      #|up 1.000000000000000E+999999 x inf xo
      #|05up 9.999999999999999E+999998 x 9.999999999999999E+999999 x
      #|
    ),
  )
}

///|
test "pm1 2^n - 1 beyond the exact gate rounds like 2^n" {
  // For n > 4 (p + 2), 2^n has D >= p + 3 digits; every rounding boundary of
  // a D-digit integer is a multiple of 5 * 10^(D - p - 1), and neither 2^n nor
  // the odd 2^n - 1 is one, so both round alike: exp2m1(n) = exp2(n).
  for mode in pm1_modes {
    for precision in [1, 3, 7, 16] {
      let ctx = pm1_ctx(precision, mode, -999_998, 999_999, true, "b")
      for n in [4 * (precision + 2) + 1, 100, 1001, 3321, 100000] {
        let x = Decimal::from_int(n, precision=10)
        let m1 = x.exp2m1_ctx(ctx)
        let plain = x.exp2_ctx(ctx)
        assert_eq(
          m1.0.total_order_compare(plain.0),
          0,
          msg="\{mode} \{precision} \{n}",
        )
        assert_eq(pm1_flags_text(m1.1), pm1_flags_text(plain.1))
        assert_true(m1.1.inexact())
      }
    }
  }
}

///|
test "pm1 log2p1 decides 2^k - 1 for a long operand by its lowest unit" {
  // 1 + x = 2^k is decided on x: the candidate powers of two with the digit
  // count of x + 1 are compared modulo 10^9 before one is formed.
  let ctx = DecimalContext::decimal128()
  let big = Decimal::from_bigint(
    BigInt::from_int(2).pow(3000) - BigInt::from_int(1),
    precision=1000,
  )
  inspect(pm1_call("log2p1", big, ctx), content="3000 -")
  let near = Decimal::from_bigint(BigInt::from_int(2).pow(3000), precision=1000)
  inspect(
    pm1_call("log2p1", near, ctx),
    content=(
      #|3000.000000000000000000000000000000 x
    ),
  )
  let tiny = decimal_coeff_power_of_two_exponent(
    coeff_from_bigint(BigInt::from_int(2).pow(40)),
  )
  assert_eq(tiny, Some(40L))
  inspect(
    decimal_coeff_is_ten_minus_five_power(
      coeff_from_bigint(
        BigInt::from_int(10).pow(30) - BigInt::from_int(5).pow(30),
      ),
      30,
    ),
    content="true",
  )
  inspect(
    decimal_coeff_is_ten_minus_five_power(
      coeff_from_bigint(
        BigInt::from_int(10).pow(30) -
        BigInt::from_int(5).pow(30) +
        BigInt::from_int(10),
      ),
      30,
    ),
    content="false",
  )
}

///|
test "pm1 exact results are rounded with the flags of the context" {
  // An exact value the context cannot hold is rounded once (Table 9.1 lists
  // overflow and underflow; 7.4, 7.5): log2p1(2^15 - 1) = 15 at p = 1 is a
  // midpoint, exp2m1(6) = 63 needs 630E-1 when e_max = 1 and clamp is set.
  let out = StringBuilder()
  for mode in pm1_modes {
    let p1 = pm1_ctx(1, mode, -98, 99, true, "b")
    let clamped = pm1_ctx(3, mode, 0, 1, true, "b")
    out.write_string(
      "\{mode} \{pm1_call("log2p1", pm1_exact("32767"), p1)} \{pm1_call("log10p1", pm1_exact("9999999999"), p1)} \{pm1_call("exp2m1", pm1_exact("6"), clamped)} \{pm1_call("exp2m1", pm1_exact("7"), clamped)}\n",
    )
  }
  inspect(
    out.to_string(),
    content=(
      #|half_even 2E+1 x 1E+1 - 63.0 - inf xo
      #|half_up 2E+1 x 1E+1 - 63.0 - inf xo
      #|half_down 1E+1 x 1E+1 - 63.0 - inf xo
      #|down 1E+1 x 1E+1 - 63.0 - 99.9 xo
      #|ceiling 2E+1 x 1E+1 - 63.0 - inf xo
      #|floor 1E+1 x 1E+1 - 63.0 - 99.9 xo
      #|up 2E+1 x 1E+1 - 63.0 - inf xo
      #|05up 1E+1 x 1E+1 - 63.0 - 99.9 xo
      #|
    ),
  )
}

///|
test "pm1 the power range refactor keeps pow results" {
  // `decimal_range_from_log2_bracket` is the former tail of
  // `decimal_power_out_of_range`; the results below are those of main.
  let ctx = DecimalContext::decimal64()
  let two = Decimal::from_int(2, precision=16)
  inspect(
    pm1_call_power(two, "1E+300", ctx),
    content=(
      #|inf xo
    ),
  )
  inspect(
    pm1_call_power(two, "-1E+300", ctx),
    content=(
      #|0E-398 xu
    ),
  )
  inspect(
    pm1_call_power(Decimal::from_string("0.5").unwrap(), "1E+5", ctx),
    content=(
      #|0E-398 xu
    ),
  )
}

///|
fn pm1_call_power(
  base : Decimal,
  exponent : String,
  ctx : DecimalContext,
) -> String {
  let (value, flags) = base.pow_ctx(pm1_exact(exponent), ctx)
  "\{value} \{pm1_flags_text(flags)}"
}

///|
test "pm1 the tiny-argument shortcut gives the Ziv loop's result" {
  // `decimal_pm1_tiny_scaled` is a cheaper enclosure of the same value; when
  // it decides, its result and flags must be those of the certified loop.
  let ops : Array[DecimalPm1] = [Exp2m1, Exp10m1, Log2p1, Log10p1]
  let mut decided = 0
  for mode in pm1_modes {
    for
      spec in [
        (7, -95, 96, true),
        (16, -383, 384, true),
        (16, -2999, 3000, true),
        (34, -6143, 6144, true),
      ] {
      let (precision, e_min, e_max, clamp) = spec
      for tininess in ["b"] {
        let ctx = pm1_ctx(precision, mode, e_min, e_max, clamp, tininess)
        for
          text in [
            "1E-50", "-7.25E-100", "3.14159E-390", "-9.999999E-401", "1.2345678901234567E-2990",
            "-6E-6170", "4.4E-6176",
          ] {
          let x = pm1_exact(text)
          for op in ops {
            match decimal_pm1_tiny_scaled(x, op, ctx) {
              None => ()
              Some(fast) => {
                decided += 1
                let slow = decimal_certified_unary_result(x, ctx, op.name(), fn(
                  input,
                ) {
                  op.evaluate(input)
                }).unwrap()
                assert_eq(
                  fast.0.total_order_compare(slow.0),
                  0,
                  msg="\{op.name()} \{mode} \{text}",
                )
                assert_eq(pm1_flags_text(fast.1), pm1_flags_text(slow.1))
              }
            }
          }
        }
      }
    }
  }
  assert_true(decided > 500)
}
