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
// oracle: A
// source: IEEE 754-2019 9.2.1, Table 9.1 and 9.2.2 (read from the PDF text in this session): f(+-0) is +-0, f(+inf) is +inf for log2p1 and log10p1 and for exp2m1 and exp10m1, f(-inf) is -1 for the two exponentials, log2p1 and log10p1 of -1 are -inf with divideByZero, of anything below -1 or of -inf invalid operation with a quiet NaN; zero results at exponent 0; the 36 lines are written out and checked in each of the eight directions and three contexts
// shares: pm1_call, pm1_exact (Decimal::from_string), pm1_ctx and pm1_flags_text (they build the operands and contexts and print value and flags: Decimal::to_string), the try_ and plain _ctx functions (the code under test)
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
// oracle: A, S
// source: IEEE 754-2019 6.2.3 and 9.2: a signaling NaN operand signals invalid and gives a quiet NaN, a quiet NaN keeps its payload if the format can hold it (decimal32 holds 6 payload digits, decimal64 15, 3.5.2); the sign of the NaN result is not specified (6.3), the library keeps the operand's sign, and a payload that does not fit keeps its low digits: those two details are the library's convention (level S)
// shares: pm1_call, pm1_exact (Decimal::from_string), pm1_ctx and pm1_flags_text (they build the operands and contexts and print value and flags: Decimal::to_string), the try_ and plain _ctx functions (the code under test)
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
// oracle: A, S
// source: the limit is the library's documented one (precision or e_max beyond 999,999, adjusted operand exponent outside -1,999,997 to 999,999, shared with decNumber): the Err cases are that design limit (level S); the least legal operand -1E-1999997 gives -0E-1000013 with inexact and underflow by arithmetic: the exact value is -c * 1E-1999997 with c below 3.4, far below half of 1E-1000013 (Etiny = e_min - precision + 1 = -999998 - 15)
// shares: pm1_call, pm1_exact (Decimal::from_string), pm1_ctx and pm1_flags_text (they build the operands and contexts and print value and flags: Decimal::to_string), the try_ and plain _ctx functions (the code under test)
test "pm1 restricted contexts and operands are not computed" {
  // The decimal math functions share the decNumber limits: a precision or an
  // exponent bound beyond 999,999, or an operand outside
  // `decimal_math_operand_out_of_range` (adjusted exponent below -1,999,997 or
  // above 999,999), is not computed (S4): `Err` in the `try_` form (the
  // `certification-failure` below), NaN with `not_computed` in the plain form.
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
      #|exp2m1 certification-failure certification-failure certification-failure -0E-1000013 xu
      #|exp10m1 certification-failure certification-failure certification-failure -0E-1000013 xu
      #|log2p1 certification-failure certification-failure certification-failure -0E-1000013 xu
      #|log10p1 certification-failure certification-failure certification-failure -0E-1000013 xu
      #|
    ),
  )
}

///|
// oracle: A
// source: IEEE 754-2019 9.2.1, Table 9.1 and 9.2.2 (read from the PDF text in this session) and 5.2: the preferred exponent is 0 and exact results are the plain integers or terminating decimals: 2^4 - 1 = 15, 1 - 2^-1 = 0.5, 2^50 - 1 = 1125899906842623, 10^2 - 1 = 99, log2(1024) = 10, log2(1/2) = -1, log2(1/16) = -4, log10(10) = 1, log10(10^9) = 9, log10(1/10) = -1, log10(1/100) = -2; each argument cohort (1, 1.000, 10E-1) gives the same text; written out
// shares: pm1_call, pm1_exact (Decimal::from_string), pm1_ctx and pm1_flags_text (they build the operands and contexts and print value and flags: Decimal::to_string), the try_ and plain _ctx functions (the code under test)
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
// oracle: A
// source: mathematics and IEEE 754-2019 9.2.1 (f(1) = +0 is listed for log, log2 and log10 only): log2(1 + 1) = 1 exactly and log10(2) = 0.30102999566... rounds to 0.3010300 at 7 digits, inexact (CPython decimal log10 of 2 at 7 digits agrees)
// shares: pm1_call, pm1_exact (Decimal::from_string), pm1_ctx and pm1_flags_text (they build the operands and contexts and print value and flags: Decimal::to_string), the try_ and plain _ctx functions (the code under test)
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
// oracle: A
// source: IEEE 754-2019 4.3 (the sign of an inexact result is the sign of the unrounded result; quoted in the block) and 7.5: for |x| = 1E-1999996 every value f(x) is about c x, below half of the least subnormal 1E-398 at 16 digits and Emin -383 (Etiny = -383 - 15 = -398), so it rounds to 0 or the least subnormal by direction (ceiling and up for positive, floor and up for negative, 05up away from zero because the kept digit is 0), flags inexact and underflow; written out
// shares: pm1_call, pm1_exact (Decimal::from_string), pm1_ctx and pm1_flags_text (they build the operands and contexts and print value and flags: Decimal::to_string), the try_ and plain _ctx functions (the code under test)
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
fn pm1_top(value : @binary.Binary) -> Int64 {
  value.exponent2().to_int64() +
  (value.coefficient().bit_length() - 1).to_int64()
}

///|
// oracle: S
// source: property of the enclosure: sign of f(x) equals the sign of x and the upper and lower endpoints of the 200-bit interval evaluation agree to 190 bits (a precision claim of the interval code, not a value); no expected value is written out; the values of these four functions are level A in elementary_pm1_rows_wbtest.mbt (MPFR 4.2.2)
// shares: decimal_to_certified_ball, DecimalPm1::evaluate and the interval bounds (the code under test), pm1_exact and pm1_top (they build the operand and read the bit length)
test "pm1 enclosures stay relatively tight down to 10^-1999997" {
  // The m1/p1 functions are built on expm1 and log1p, series in x, so the
  // enclosure of f(x) keeps a relative width of a few ulps of the working
  // precision for every legal operand (no cancellation near zero, design note
  // of #236): at w = 200 bits the endpoints agree to at least 190 bits.
  let up = @binary.BinaryContext::new(
    precision=64,
    rounding=@binary.BinaryRoundingMode::RoundTowardPositive,
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
      assert_eq(lower.is_sign_minus(), x.negative, msg="\{op.name()} \{text}")
      assert_eq(upper.is_sign_minus(), x.negative, msg="\{op.name()} \{text}")
      let width = upper.sub_ctx(lower, up).0
      assert_true(
        width.is_zero() || pm1_top(width) <= pm1_top(lower) - 190L,
        msg="\{op.name()} \{text}",
      )
    }
  }
}

///|
// oracle: A
// source: mathematics: for x = -(1 - 9 * 10^-D) the value 1 + x is 9 * 10^-D, log2 of it is negative and inexact, log10 of it is -D + log10(9) = -D + 0.954, inside (-D, -D + 1); the bracket is computed from that identity, not read from the library
// shares: Decimal::from_string and from_int (they build the operands and the bracket), compare, try_log2p1_ctx and try_log10p1_ctx (the code under test)
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
// oracle: A
// source: arithmetic and IEEE 754-2019 4.3, 7.4: 10^999999 - 1 (999999 nines) at 16 digits is 1.000000000000000E+999999 when rounded to nearest or up and 9.999999999999999E+999998 toward zero, down or 05up; 10^1000000 - 1 exceeds the largest finite number and overflows to infinity (with overflow and inexact) when rounded to nearest or up, and is the largest finite 9.999999999999999E+999999 (inexact only: not above it before the exponent bound, 7.4) when rounded toward zero, down or 05up; written out
// shares: pm1_call, pm1_exact (Decimal::from_string), pm1_ctx and pm1_flags_text (they build the operands and contexts and print value and flags: Decimal::to_string), the try_ and plain _ctx functions (the code under test)
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
// oracle: S
// source: the identity exp2m1(n) = exp2(n) after rounding for n beyond the exact gate, argued in the comment above (no boundary of the rounding is 2^n or 2^n - 1); the sibling function exp2 is the comparison, no expected value is written out; the exact cases and MPFR rows of exp2m1 are level A in elementary_pm1_rows_wbtest.mbt (tools/generate_decimal_pm1_rows.py)
// shares: Decimal::from_int, exp2m1_ctx and exp2_ctx (the code under test on both sides), pm1_ctx
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
// oracle: A
// source: arithmetic: log2(1 + (2^3000 - 1)) = 3000 exactly; log2(1 + 2^3000) = 3000 + 1/(2^3000 ln 2), which rounds to 3000.000000000000000000000000000000 at 34 digits, inexact; the two small predicates are checked on 2^40 (exponent 40) and on 10^30 - 5^30 (true) and 10^30 - 5^30 + 10 (false), integers computed by BigInt pow
// shares: BigInt::pow and BigInt::from_int, Decimal::from_bigint and coeff_from_bigint (they build the operands), pm1_call (prints value and flags), decimal_coeff_power_of_two_exponent and decimal_coeff_is_ten_minus_five_power (the code under test)
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
// oracle: A
// source: arithmetic and IEEE 754-2019 4.3, 7.4: log2(2^15) = 15 at one digit is the midpoint of 1E+1 and 2E+1 (even rule 2E+1, half_down 1E+1, directed by direction, 05up keeps 1E+1 since the kept digit is 1), log10(10^10) = 10 is exact at one digit, 2^6 - 1 = 63 is 63.0 at three digits with e_max 1 (clamped to the largest exponent -1), 2^7 - 1 = 127 exceeds 99.9 and overflows (infinity to nearest or up, 99.9 toward zero, both with overflow and inexact); written out
// shares: pm1_call, pm1_exact (Decimal::from_string), pm1_ctx and pm1_flags_text (they build the operands and contexts and print value and flags: Decimal::to_string), the try_ and plain _ctx functions (the code under test)
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
// oracle: A
// source: arithmetic: 2^(1E+300) exceeds 10^384 (overflow to infinity), 2^(-1E+300) and 0.5^100000 = 1E-30103 are below the least subnormal 1E-398 of decimal64 and round to 0E-398 with inexact and underflow (7.5); written out
// shares: Decimal::from_int and from_string (they build the operands), pm1_call_power (prints), pow_ctx (the code under test)
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
// oracle: S
// source: equivalence of the shortcut with the certified Ziv loop (decimal_certified_unary_result with the interval evaluation of exp2m1, exp10m1, log2p1 and log10p1), the general route that decimal_pm1_tiny_scaled replaces; value and flags compared when the shortcut decides. No expected value is written out: the operands of this block go to E-6176 and the level A rows of elementary_pm1_rows_wbtest.mbt (fractions.Fraction exact cases and MPFR 4.2.2 enclosures, tools/generate_decimal_pm1_rows.py) go only to about E-100, so that table does not reach them. The block `pm1 tiny arguments next to a rounding midpoint` below has level A rows for the soundness of the shortcut
// shares: decimal_certified_unary_result, the interval functions and DecimalPm1::evaluate (both sides use them)
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

///|
// oracle: A
// source: table pm1_tiny_rows generated by tools/generate_decimal_oracle_rows.py: tiny arguments x (60 significant digits, adjusted exponents -16 to -40) chosen so that the first-order value c x lies a few 1e-20 relative to one side of a rounding midpoint of the 3-digit grid and the true value f(x) = c x (1 + d) on the other, with f(x) from the series of expm1 and log1p at 150 digits (CPython decimal) rounded once half-even; the shortcut of decimal_pm1_tiny_scaled must not decide these wrongly (its enclosure of the factor 1 +- 2^k must cover d), and the Ziv loop must give the same
// shares: Decimal::from_string, exp2m1_ctx, exp10m1_ctx, log2p1_ctx, log10p1_ctx and to_string (they build the operand and read the result as text)
test "pm1 tiny arguments next to a rounding midpoint" {
  let ctx = DecimalContext::new(precision=3)
  for row in pm1_tiny_rows() {
    let (operation, _, text, expected) = row
    let x = Decimal::from_string(text, precision=64).unwrap()
    let got = match operation {
      "exp2m1" => x.exp2m1_ctx(ctx).0
      "exp10m1" => x.exp10m1_ctx(ctx).0
      "log2p1" => x.log2p1_ctx(ctx).0
      _ => x.log10p1_ctx(ctx).0
    }
    assert_eq((operation, text, got.to_string()), (operation, text, expected))
  }
}
