///|
/// `DecimalContext::with_clamp_fold` (issue 234). IEEE 754-2019 §5.3.2 quantize
/// is silent about a zero result whose exponent cannot be encoded (above
/// `e_max - precision + 1`, 90, 369 and 6111 for decimal32, decimal64 and
/// decimal128 and the `clamp` of the interchange formats). By default `quantize`
/// returns the exponent asked for (as before); with the opt-in fold and `clamp`
/// the exponent is folded down to `e_max - precision + 1` and `clamped` is
/// raised, which is what decNumber does: `decQuantizeOp` sets the exponent of a
/// zero operand and calls `decFinalize`, whose clamp branch lowers the exponent
/// to `emax - digits + 1` and raises `DEC_Clamped`. The expected rows are the
/// rule applied by hand: a target above the top folds, a target at or below it
/// and a target above `e_max` (invalid) do not.

///|
let issue234_contexts : Array[(String, Int32, Int32, Int32, Bool)] = [
  ("decimal32", 7, -95, 96, true),
  ("decimal64", 16, -383, 384, true),
  ("decimal128", 34, -6143, 6144, true),
  ("small", 5, -10, 3, true),
  ("not clamped", 16, -383, 384, false),
]

///|
/// (context, zero, target quantum, result with the fold off, result with the
/// fold on, clamped with the fold on)
let issue234_rows : Array[(String, String, String, String, String, Bool)] = [
  ("decimal64", "0", "1E+380", "0E+380", "0E+369", true),
  ("decimal64", "-0", "1E+380", "-0E+380", "-0E+369", true),
  ("decimal64", "0E+5", "1E+380", "0E+380", "0E+369", true),
  ("decimal64", "0E-3", "1E+370", "0E+370", "0E+369", true),
  ("decimal64", "0", "1E+384", "0E+384", "0E+369", true),
  ("decimal64", "0", "1E+369", "0E+369", "0E+369", false),
  ("decimal64", "0", "1E+368", "0E+368", "0E+368", false),
  ("decimal64", "0", "1", "0", "0", false),
  ("decimal64", "-0", "1E-398", "-0E-398", "-0E-398", false),
  ("decimal64", "0", "1E+385", "NaN", "NaN", false),
  ("decimal32", "0", "1E+96", "0E+96", "0E+90", true),
  ("decimal32", "0", "1E+91", "0E+91", "0E+90", true),
  ("decimal32", "0", "1E+90", "0E+90", "0E+90", false),
  ("decimal128", "0", "1E+6144", "0E+6144", "0E+6111", true),
  ("decimal128", "-0", "1E+6112", "-0E+6112", "-0E+6111", true),
  ("decimal128", "0", "1E+6111", "0E+6111", "0E+6111", false),
  ("small", "0", "1E+3", "0E+3", "0.0", true),
  ("small", "0", "1E+0", "0", "0.0", true),
  ("small", "0", "1E-1", "0.0", "0.0", false),
  ("small", "0", "1E-2", "0.00", "0.00", false),
  ("not clamped", "0", "1E+380", "0E+380", "0E+380", false),
  ("not clamped", "-0", "1E+384", "-0E+384", "-0E+384", false),
]

///|
fn issue234_context(name : String, fold : Bool) -> DecimalContext {
  let mut found : (String, Int32, Int32, Int32, Bool)? = None
  for entry in issue234_contexts {
    if entry.0 == name {
      found = Some(entry)
    }
  }
  let (_, precision, e_min, e_max, clamp) = found.unwrap()
  DecimalContext::new(precision~, e_min~, e_max~, clamp~).with_clamp_fold(fold)
}

///|
fn issue234_text(value : Decimal) -> String {
  if value.is_nan() {
    "NaN"
  } else {
    value.to_string()
  }
}

///|
test "a zero quantize result above the top exponent folds down only with the opt-in fold (issue 234)" {
  for row in issue234_rows {
    let (name, zero, quantum, off, on, clamped) = row
    let x = Decimal::from_string(zero).unwrap()
    let q = Decimal::from_string(quantum).unwrap()
    let label = "\{name} quantize \{zero} \{quantum}"
    let (default_value, default_flags) = x.quantize(
      q,
      issue234_context(name, false),
    )
    assert_eq(
      (label + " off", issue234_text(default_value)),
      (label + " off", off),
    )
    assert_false(default_flags.clamped, msg=label + " off")
    let (folded, flags) = x.quantize(q, issue234_context(name, true))
    assert_eq((label + " on", issue234_text(folded)), (label + " on", on))
    assert_eq(
      (label + " clamped", flags.clamped),
      (label + " clamped", clamped),
    )
    assert_false(flags.inexact || flags.rounded, msg=label)
    // rescale takes the exponent as an integer and shares the path
    if !folded.is_nan() {
      let (by_rescale, rescale_flags) = x.rescale(
        Decimal::from_int(q.exponent10),
        issue234_context(name, true),
      )
      assert_eq(
        (label + " rescale", issue234_text(by_rescale)),
        (label + " rescale", on),
      )
      assert_eq((label, rescale_flags.clamped), (label, clamped))
    }
  }
}

///|
test "the fold does not change a non-zero result and is off in every context (issue 234)" {
  let on = DecimalContext::decimal64().with_clamp_fold(true)
  let off = DecimalContext::decimal64()
  for
    pair in [
      ("5", "1E+380"),
      ("123.456", "1E-2"),
      ("1E+360", "1E+369"),
      ("9.999999999999999E+384", "1E+369"),
      ("0.5", "1"),
    ] {
    let x = Decimal::from_string(pair.0).unwrap()
    let q = Decimal::from_string(pair.1).unwrap()
    let (a, fa) = x.quantize(q, off)
    let (b, fb) = x.quantize(q, on)
    assert_eq(
      (pair.0, issue234_text(a), fa.clamped),
      (pair.0, issue234_text(b), fb.clamped),
    )
  }
  for
    context in [
      DecimalContext::decimal32(),
      DecimalContext::decimal64(),
      DecimalContext::decimal128(),
      DecimalContext::exact(),
      DecimalContext::new(),
      DecimalContext::try_new().unwrap(),
      DecimalContext::from_arithmetic_context(
        @lf_arith.ArithmeticContext::new(16),
      ).unwrap(),
    ] {
    assert_false(context.clamp_fold())
    assert_true(context.with_clamp_fold(true).clamp_fold())
    assert_false(
      context.with_clamp_fold(true).with_clamp_fold(false).clamp_fold(),
    )
    // the setter copies and the derived equality sees the field
    assert_true(context == context.with_clamp_fold(false))
    assert_true(context != context.with_clamp_fold(true))
  }
}

///|
test "other operations that produce such a zero already fold with or without the option (issue 234)" {
  // The quantize path was the only one that returned the exponent asked for.
  let off = DecimalContext::decimal64()
  let on = off.with_clamp_fold(true)
  let zero = Decimal::from_string("0E+380").unwrap()
  let one = Decimal::from_string("1").unwrap()
  for ctx in [off, on] {
    let results = [
      zero.apply_ctx(ctx),
      zero.plus_ctx(ctx),
      zero.add_ctx(zero, ctx),
      zero.mul_ctx(one, ctx),
      zero.div_ctx(one, ctx),
      Decimal::from_string("0").unwrap().scaleb_ctx(Decimal::from_int(380), ctx),
      zero.to_integral_exact(ctx),
    ]
    for result in results {
      assert_eq(result.0.to_string(), "0E+369")
      assert_true(result.1.clamped)
    }
  }
}
