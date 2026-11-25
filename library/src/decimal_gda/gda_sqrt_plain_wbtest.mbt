///|
// Differential test of the plain path of `sqrt` against the general route
// (`sqrt_ctx_impl(plain=false)`, the previous behavior of the function), kept
// as reference. The comparison is made at the public level: the value
// representation, every condition raised (Inexact, Rounded, Subnormal,
// Underflow, Clamped, ...), the status of the returned context and trapped or
// completed. Helpers of `gda_add_plain_wbtest.mbt`.

///|
let sqrt_plain_cases : Int32 = 400

///|
fn sqrt_plain_expected(
  value : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  // a subset context rounds the operand with the context first (page 56), the
  // result with round-half-even (the mathematical context)
  let (operand, operand_flags) = gda_prepare_operand(value, ctx)
  let (result, flags) = operand.sqrt_ctx_impl(
    ctx.mathematical_decimal_context(),
    plain=false,
  )
  complete_decimal_gda(result, ctx, flags.combine(operand_flags))
}

///|
fn sqrt_plain_flags(outcome : GdaOutcome[Decimal]) -> GdaFlags {
  match outcome {
    Completed(_, _, flags) => flags
    Trapped(_, _, _, flags) => flags
  }
}

///|
/// Checks `sqrt` against the reference; returns whether the plain path
/// answered (and agreed with the reference at the engine level too).
fn sqrt_plain_check(value : Decimal, ctx : GdaContext) -> Bool raise {
  if !add_plain_same_outcome(sqrt(value, ctx), sqrt_plain_expected(value, ctx)) {
    fail("sqrt differs: \{value.to_sci_string()} precision \{ctx.precision_}")
  }
  // the engine level: the operand as `sqrt_ctx` sees it (prepared for the
  // context), the plain path against the general route
  let math = ctx.mathematical_decimal_context()
  let (operand, _) = gda_prepare_operand(value, ctx)
  match decimal_sqrt_plain(operand, math, math.precision) {
    Some((root, flags)) => {
      let (expected, expected_flags) = decimal_sqrt_general(
        operand,
        math,
        math.precision,
      )
      if !add_plain_same_decimal(root, expected) || flags != expected_flags {
        fail(
          "plain sqrt differs: \{value.to_sci_string()} precision \{ctx.precision_} plain \{root.to_sci_string()} expected \{expected.to_sci_string()}",
        )
      }
      true
    }
    None => false
  }
}

///|
fn sqrt_plain_text(value : String, e_max : Int32) -> Decimal {
  to_number(value, GdaContext::new(precision=400, e_min=-e_max, e_max~)).value()
}

///|
/// The decimal text of `digits` squared (exact, through the wide context).
fn sqrt_plain_square(digits : String) -> String {
  let wide = GdaContext::new(precision=400)
  let root = to_number(digits, wide).value()
  multiply(root, root, wide).value().to_string()
}

///|
fn sqrt_plain_operand(
  state : Ref[UInt64],
  ctx : GdaContext,
  kind : UInt64,
  max_digits : Int32,
) -> Decimal {
  let digits = add_plain_digits(
    state,
    add_plain_range(state, 1, Int32::max(1, max_digits)),
  )
  // an exponent in the middle of the range, or near either end of it
  let place = add_plain_next(state) % 4UL
  let exponent = if place == 0UL {
    2 * ctx.e_min_ + add_plain_range(state, -4, 12)
  } else if place == 1UL {
    2 * ctx.e_max_ + add_plain_range(state, -12, 4)
  } else {
    add_plain_range(state, -60, 60)
  }
  let text = if kind == 0UL {
    // a square of up to `max_digits / 2` digits, possibly with trailing zeros
    let root = add_plain_digits(
        state,
        add_plain_range(state, 1, Int32::max(1, max_digits / 2)),
      ) +
      String::make(add_plain_range(state, 0, 3), '0')
    // an even exponent: with an odd one the root is not a decimal
    sqrt_plain_square(root) + "E" + (exponent - (exponent & 1)).to_string()
  } else if kind == 1UL {
    // a square plus or minus a few units: remainders 0, 1, r, r + 1, 2 r
    let root = add_plain_digits(
      state,
      add_plain_range(state, 1, Int32::max(1, max_digits / 2)),
    )
    let wide = GdaContext::new(precision=400)
    let square = to_number(sqrt_plain_square(root), wide).value()
    let delta = to_number(
      match add_plain_next(state) % 4UL {
        0UL => "1"
        1UL => "-1"
        2UL => root
        _ => "-" + root
      },
      wide,
    ).value()
    add(square, delta, wide).value().to_string() + "E" + exponent.to_string()
  } else {
    digits + "E" + exponent.to_string()
  }
  to_number(
    text,
    GdaContext::new(precision=400, e_min=-999999999, e_max=999999999),
  ).value()
}

///|
fn sqrt_plain_run(max_digits : Int32, seed : UInt64) -> Array[Int32] raise {
  let state = Ref(seed)
  let hits = [0, 0, 0, 0]
  for index in 0..<sqrt_plain_cases {
    let ctx = add_plain_context(state)
    let kind = (index % 3).to_uint64()
    let value = sqrt_plain_operand(state, ctx, kind, max_digits)
    // a non-extended context rounds the operand to its precision first, which
    // can turn a square into a non-square: those are not counted as squares
    let counted = kind != 0UL || ctx.extended_
    if sqrt_plain_check(value, ctx) && counted {
      hits[kind.to_int()] = hits[kind.to_int()] + 1
    }
    hits[3] = hits[3] + 1
  }
  hits
}

///|
// oracle: E
// source: the general route as the reference (`sqrt_plain_check` compares the plain path with sqrt_ctx and complete_decimal_gda in full), random operands of 1 to 130 digits; the counts of hits assert that squares are declined
// shares: complete_decimal_gda, sqrt_ctx
// underneath: the general route of sqrt (sqrt_ctx, then complete_decimal_gda) has level A oracles on extended arithmetic: the official squareroot.decTest rows in the gate stages DECIMAL_GDA: official decTest and official0, and the sqrt rows of plain_operator_rows_wbtest.mbt (CPython, precision 3, 16, 34); other inputs stay level E
test "sqrt plain equals the general route (short operands)" {
  let hits = sqrt_plain_run(40, 0x9E3779B97F4A7C15UL)
  // a square is never taken (the residue tests are necessary conditions)
  assert_eq(hits[0], 0)
  assert_true(hits[1] > 40 && hits[2] > 40)
}

///|
// oracle: E
// source: the general route as the reference (`sqrt_plain_check` compares the plain path with sqrt_ctx and complete_decimal_gda in full), random operands of 1 to 130 digits; the counts of hits assert that squares are declined
// shares: complete_decimal_gda, sqrt_ctx
// underneath: the general route of sqrt (sqrt_ctx, then complete_decimal_gda) has level A oracles on extended arithmetic: the official squareroot.decTest rows in the gate stages DECIMAL_GDA: official decTest and official0, and the sqrt rows of plain_operator_rows_wbtest.mbt (CPython, precision 3, 16, 34); other inputs stay level E
test "sqrt plain equals the general route (long operands)" {
  let hits = sqrt_plain_run(130, 0xD1B54A32D192ED03UL)
  assert_eq(hits[0], 0)
  assert_true(hits[1] > 20 && hits[2] > 20)
}

///|
/// Rows of the official `squareroot.decTest` whose conditions include Rounded
/// without Inexact: there are 15, of which these 12 are exact roots in range
/// (sqtx1204, 1228, 1268, 8010, 8112, 8525, 8526, 8543, 8544, 8634, 8641,
/// 8654); the other three (8511, 8533, 8557) also raise Subnormal and take the
/// general route.
// oracle: A
// source: 12 rows of the official squareroot.decTest (sqtx1204, 1228, 1268, 8010, 8112, 8525, 8526, 8543, 8544, 8634, 8641, 8654) written out with operand, precision, e_max and expected result, as the comment above the block says
// shares: Decimal::to_string (prints the result)
test "sqrt plain on the exact rows that raise Rounded without Inexact" {
  // (operand, precision, e_max, expected, plain path expected to answer)
  let rows : Array[(String, Int32, Int32, String)] = [
    ("1.00E-2", 1, 999, "0.1"),
    ("4.00E-2", 1, 999, "0.2"),
    ("9.00E-2", 1, 999, "0.3"),
    ("100", 1, 9, "1E+1"),
    ("10000", 2, 9, "1.0E+2"),
    ("1.000E-18", 2, 999, "1.0E-9"),
    ("1.0000E-18", 2, 999, "1.0E-9"),
    ("1.00000E-18", 3, 999, "1.00E-9"),
    ("1.000000E-18", 3, 999, "1.00E-9"),
    ("1.000E+18", 2, 999, "1.0E+9"),
    ("1.00000000000E+18", 6, 999, "1.00000E+9"),
    ("10000000000", 3, 999, "1.00E+5"),
  ]
  let mut answered = 0
  for row in rows {
    let (text, precision, e_max, expected) = row
    let ctx = GdaContext::new(precision~, e_min=-e_max, e_max~)
    let value = sqrt_plain_text(text, e_max)
    let outcome = sqrt(value, ctx)
    assert_eq(outcome.value().to_sci_string(), expected)
    let flags = sqrt_plain_flags(outcome)
    assert_true(flags.contains(Rounded))
    assert_true(!flags.contains(Inexact))
    if sqrt_plain_check(value, ctx) {
      answered = answered + 1
    }
  }
  // none of the official rows is plain: their coefficients are longer than the
  // radicand of a root of the precision allows, so the general route raises Rounded
  assert_eq(answered, 0)
}

///|
/// The rounding rule `rem > r`: at two digits `sqrt(156)` has `r = 12` and
/// `rem = 12` (below the midpoint, 12.49...), `sqrt(157)` has `rem = 13` (above,
/// 12.53...); `sqrt(2)`, `sqrt(0.5)`, `sqrt(1E+1)` and the carry `sqrt(9999)`.
// oracle: A
// source: written out by hand at two digits: sqrt(156) has root 12 and remainder 12, below the midpoint, giving 12; sqrt(157) has remainder 13, above, giving 13; sqrt(2) = 1.4, sqrt(0.5) = 0.71, sqrt(10) = 3.2 and the carry sqrt(9999)
// shares: Decimal::to_string (prints the result)
test "sqrt plain at the rounding boundary and at a carry" {
  let ctx = GdaContext::new(precision=2, e_min=-99, e_max=99)
  for
    row in [
      ("156", "12"),
      ("157", "13"),
      ("2", "1.4"),
      ("0.5", "0.71"),
      ("10", "3.2"),
      ("9999", "1.0E+2"),
      ("99", "9.9"),
      ("98.9", "9.9"),
    ] {
    let (text, expected) = row
    let value = sqrt_plain_text(text, 99)
    assert_eq(sqrt(value, ctx).value().to_sci_string(), expected)
    let answered = sqrt_plain_check(value, ctx)
    assert_true(answered)
  }
}

///|
/// Ideal-exponent cases of exact roots at nine digits: zeros stripped and
/// appended, odd and even exponents, negative exponents (the ideal exponent is
/// the exponent halved towards minus infinity), and two inexact ones.
// oracle: A
// source: written out from the ideal exponent rule of GDA 1.70 square-root (the exponent of an exact root is half the exponent of the operand, rounded toward minus infinity): sqrt(100) = 10, sqrt(1E+4) = 1E+2, sqrt(0.01) = 0.1, sqrt(2.25) = 1.5, sqrt(1.00E+2) = 10, two inexact cases
// shares: Decimal::to_string (prints the result)
test "sqrt plain keeps the ideal exponent of exact roots" {
  let ctx = GdaContext::new(precision=9, e_min=-999, e_max=999)
  for
    row in [
      ("100", "10"),
      ("1E+4", "1E+2"),
      ("0.01", "0.1"),
      ("2.25", "1.5"),
      ("1.00E+2", "10"),
      ("1.0000E+2", "10.0"),
      ("1.000000E+2", "10.00"),
      ("4E+0", "2"),
      ("4.00", "2.0"),
      ("4.0000000000", "2.00000"),
      ("1E-2", "0.1"),
      ("1E-3", "0.0316227766"),
      ("1E+3", "31.6227766"),
      ("144", "12"),
      ("14400", "120"),
      ("0.000144", "0.012"),
    ] {
    let (text, expected) = row
    let value = sqrt_plain_text(text, 999)
    assert_eq(sqrt(value, ctx).value().to_sci_string(), expected)
    // `1E-3` and `1E+3` (odd exponents) are certainly not squares
    assert_eq(sqrt_plain_check(value, ctx), text == "1E-3" || text == "1E+3")
  }
}

///|
// oracle: A, E
// source: design limits of the plain path, written out from the comments of the source (not a standard: the cut-offs are the implementation's own): an operand 1E-215 at precision 7 is declined by the plain path (written out), and the public result is compared with the general route
// shares: complete_decimal_gda, sqrt_ctx for the comparison
// underneath: the general route of sqrt (sqrt_ctx, then complete_decimal_gda) has level A oracles on extended arithmetic: the official squareroot.decTest rows in the gate stages DECIMAL_GDA: official decTest and official0, and the sqrt rows of plain_operator_rows_wbtest.mbt (CPython, precision 3, 16, 34); other inputs stay level E
test "sqrt plain declines a tiny operand and agrees" {
  let ctx = GdaContext::new(precision=7, e_min=-99, e_max=99)
  let math = ctx.mathematical_decimal_context()
  let value = sqrt_plain_text("1E-215", 999)
  assert_true(decimal_sqrt_tiny_result(value, math) is Some(_))
  assert_true(decimal_sqrt_plain(value, math, math.precision) is None)
  assert_true(!sqrt_plain_check(value, ctx))
}

///|
// oracle: A, E
// source: design limits of the plain path, written out from the comments of the source (not a standard: the cut-offs are the implementation's own): operands whose root has an adjusted exponent below e_min or not below e_max are declined (written out), and the public result is compared with the general route
// shares: complete_decimal_gda, sqrt_ctx for the comparison
// underneath: the general route of sqrt (sqrt_ctx, then complete_decimal_gda) has level A oracles on extended arithmetic: the official squareroot.decTest rows in the gate stages DECIMAL_GDA: official decTest and official0, and the sqrt rows of plain_operator_rows_wbtest.mbt (CPython, precision 3, 16, 34); other inputs stay level E
test "sqrt plain declines a subnormal and an out-of-range root and agrees" {
  let ctx = GdaContext::new(precision=5, e_min=-9, e_max=9)
  let math = ctx.mathematical_decimal_context()
  // the root's adjusted exponent is below e_min or not below e_max
  for text in ["1E-19", "1.5E-19", "4E-20", "2E-19", "1E+19", "2E+19", "9E+19"] {
    let value = sqrt_plain_text(text, 99)
    if !(decimal_sqrt_plain(value, math, math.precision) is None) {
      fail("expected a decline: " + text)
    }
    assert_true(!sqrt_plain_check(value, ctx))
  }
  // at the edge of the range the plain path answers
  for text in ["2E-18", "3E-18", "2E+17", "3E+17"] {
    let value = sqrt_plain_text(text, 99)
    if !(decimal_sqrt_plain(value, math, math.precision) is Some(_)) {
      fail("expected an answer: " + text)
    }
    assert_true(sqrt_plain_check(value, ctx))
  }
}

///|
// oracle: A, E
// source: design limits of the plain path, written out from the comments of the source (not a standard: the cut-offs are the implementation's own): squares such as 144, 4, 1E+4, 0.01, 2.25, 14400, 6.25E+2 are declined by the residue tests (written out); the public result is compared with the general route
// shares: complete_decimal_gda, sqrt_ctx for the comparison
// underneath: the general route of sqrt (sqrt_ctx, then complete_decimal_gda) has level A oracles on extended arithmetic: the official squareroot.decTest rows in the gate stages DECIMAL_GDA: official decTest and official0, and the sqrt rows of plain_operator_rows_wbtest.mbt (CPython, precision 3, 16, 34); other inputs stay level E
test "sqrt plain declines the operands that may be squares" {
  let ctx = GdaContext::new(precision=9, e_min=-999, e_max=999)
  let math = ctx.mathematical_decimal_context()
  // squares (also with zeros in the coefficient) are declined
  for
    text in [
      "144", "4", "1E+4", "0.01", "2.25", "14400", "6.25E+2", "1E+8", "400",
    ] {
    let value = sqrt_plain_text(text, 999)
    if !(decimal_sqrt_plain(value, math, math.precision) is None) {
      fail("expected a decline: " + text)
    }
    ignore(sqrt_plain_check(value, ctx))
  }
  // a coefficient that is not a square modulo 64 (or 63, 65, 11) is taken, and
  // an odd exponent always (an exact root would be divisible by 10)
  for
    text in [
      "2", "3", "5", "7", "145", "2E+1", "1E+1", "1E-1", "10", "30", "1000", "100E+1",
    ] {
    let value = sqrt_plain_text(text, 999)
    let planned = decimal_sqrt_plain(value, math, math.precision) is Some(_)
    // `100E+1` is 10^3: c0 = 1, z = 2, q + z = 3 is odd, so it is taken too
    assert_true(planned)
    ignore(sqrt_plain_check(value, ctx))
  }
}

///|
// oracle: A, E
// source: design limits of the plain path, written out from the comments of the source (not a standard: the cut-offs are the implementation's own): 40-digit coefficients at precision 7 are declined (written out), and the public result is compared with the general route
// shares: complete_decimal_gda, sqrt_ctx for the comparison
// underneath: the general route of sqrt (sqrt_ctx, then complete_decimal_gda) has level A oracles on extended arithmetic: the official squareroot.decTest rows in the gate stages DECIMAL_GDA: official decTest and official0, and the sqrt rows of plain_operator_rows_wbtest.mbt (CPython, precision 3, 16, 34); other inputs stay level E
test "sqrt plain declines long coefficients and agrees" {
  // 7 digits of precision, a coefficient of 40 digits
  let ctx = GdaContext::new(precision=7, e_min=-999, e_max=999)
  let math = ctx.mathematical_decimal_context()
  for
    text in [
      "1234567890123456789012345678901234567890E-20", "9999999999999999999999999999999999999999",
      "1000000000000000000000000000000000000000E+0",
    ] {
    let value = sqrt_plain_text(text, 999)
    assert_true(decimal_sqrt_plain(value, math, math.precision) is None)
    ignore(sqrt_plain_check(value, ctx))
  }
}

///|
// oracle: A, E
// source: design limits of the plain path, written out from the comments of the source (not a standard: the cut-offs are the implementation's own): the exact root 1E+8 of 1E+16 at precision 5, e_max 9 and clamp has its digits folded down, so the plain path declines (written out); the public result is compared with the general route
// shares: complete_decimal_gda, sqrt_ctx for the comparison
// underneath: the general route of sqrt (sqrt_ctx, then complete_decimal_gda) has level A oracles on extended arithmetic: the official squareroot.decTest rows in the gate stages DECIMAL_GDA: official decTest and official0, and the sqrt rows of plain_operator_rows_wbtest.mbt (CPython, precision 3, 16, 34); other inputs stay level E
test "sqrt plain declines the clamp fold-down of an exact root and agrees" {
  // precision 5, e_max 9: the largest exponent of the format is 5; the exact
  // root 1E+8 of 1E+16 has exponent 8 and the clamp folds its digits down
  let ctx = GdaContext::new(precision=5, e_min=-9, e_max=9, clamp=true)
  let math = ctx.mathematical_decimal_context()
  let value = sqrt_plain_text("1E+16", 99)
  assert_true(decimal_sqrt_plain(value, math, math.precision) is None)
  assert_true(!sqrt_plain_check(value, ctx))
}
