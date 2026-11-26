///|
/// A zero `quantize` result above `e_max - precision + 1` (90, 369 and 6111 for
/// decimal32, decimal64 and decimal128) (issue 234). Every finite result of an
/// IEEE format has `q <= e_max - p + 1` (IEEE 754-2019 3.3), so the delivered
/// zero is a member of the format: its exponent is folded down to
/// `e_max - precision + 1`. This package has no Clamped condition (IEEE 754 has
/// none), so the `clamped` column of the rows is NOT asserted here: it is the
/// GDA expectation, asserted by the same rows in
/// `decimal_gda/zero_fold_issue234_wbtest.mbt`. The expected rows are the rule
/// applied by hand: a target above the top folds, a target at or below it and a
/// target above `e_max` (invalid) do not.

///|
let issue234_contexts : Array[(String, Int32, Int32)] = [
  ("decimal32", 7, 96),
  ("decimal64", 16, 384),
  ("decimal128", 34, 6144),
  ("small", 5, 3),
]

///|
/// (context, zero, target quantum, delivered result, clamped)
let issue234_rows : Array[(String, String, String, String, Bool)] = [
  ("decimal64", "0", "1E+380", "0E+369", true),
  ("decimal64", "-0", "1E+380", "-0E+369", true),
  ("decimal64", "0E+5", "1E+380", "0E+369", true),
  ("decimal64", "0E-3", "1E+370", "0E+369", true),
  ("decimal64", "0", "1E+384", "0E+369", true),
  ("decimal64", "0", "1E+369", "0E+369", false),
  ("decimal64", "0", "1E+368", "0E+368", false),
  ("decimal64", "0", "1", "0", false),
  ("decimal64", "-0", "1E-398", "-0E-398", false),
  ("decimal64", "0", "1E+385", "NaN", false),
  ("decimal32", "0", "1E+96", "0E+90", true),
  ("decimal32", "0", "1E+91", "0E+90", true),
  ("decimal32", "0", "1E+90", "0E+90", false),
  ("decimal128", "0", "1E+6144", "0E+6111", true),
  ("decimal128", "-0", "1E+6112", "-0E+6111", true),
  ("decimal128", "0", "1E+6111", "0E+6111", false),
  ("small", "0", "1E+3", "0.0", true),
  ("small", "0", "1E+0", "0.0", true),
  ("small", "0", "1E-1", "0.0", false),
  ("small", "0", "1E-2", "0.00", false),
]

///|
fn issue234_context(name : String) -> DecimalContext {
  let mut found : (String, Int32, Int32)? = None
  for entry in issue234_contexts {
    if entry.0 == name {
      found = Some(entry)
    }
  }
  let (_, precision, e_max) = found.unwrap()
  DecimalContext::new(precision~, e_max~)
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
// oracle: A
// source: IEEE 754-2019 3.3 (every finite result of a format has q <= e_max - p + 1) and CPython decimal quantize with clamp = 1 (re-run 2026-11-26: the 20 rows agree in value, 0E+369 for decimal64 above the top, 0E+90 and 0E+6111, 0.0 for the small context, NaN with invalid operation for a target above e_max); the clamped column is not asserted here
// shares: Decimal::from_string (builds the operands), issue234_context and issue234_text (build the context and print), quantize_ctx and the other operations (the code under test)
test "a zero quantize result above the top exponent folds down (issue 234)" {
  for row in issue234_rows {
    let (name, zero, quantum, result, _) = row
    let x = Decimal::from_string(zero).unwrap()
    let q = Decimal::from_string(quantum).unwrap()
    let label = "\{name} quantize \{zero} \{quantum}"
    let ctx = issue234_context(name)
    let (folded, flags) = x.quantize_ctx(q, ctx)
    assert_eq((label, issue234_text(folded)), (label, result))
    assert_false(flags.inexact, msg=label)
  }
}

///|
// oracle: A
// source: arithmetic: 123.456 quantized to 1E-2 is 123.46 and 0.5 quantized to 1 is 0 (half-even); CPython agrees
// shares: Decimal::from_string (builds the operands), issue234_context and issue234_text (build the context and print), quantize_ctx and the other operations (the code under test)
test "the fold does not change a non-zero result (issue 234)" {
  let ctx = DecimalContext::decimal64()
  for pair in [("123.456", "1E-2", "123.46"), ("0.5", "1", "0")] {
    let x = Decimal::from_string(pair.0).unwrap()
    let q = Decimal::from_string(pair.1).unwrap()
    let (a, _) = x.quantize_ctx(q, ctx)
    assert_eq(issue234_text(a), pair.2)
  }
}

///|
// oracle: A
// source: IEEE 754-2019 3.3: a zero of exponent 380 is not a member of decimal64 (the top exponent is 369), so every operation that delivers it gives 0E+369; CPython decimal (clamp = 1) agrees for plus, add, multiply, divide and scaleb; its to_integral_exact does not apply the context to the exponent, so that row rests on 3.3 alone
// shares: Decimal::from_string (builds the operands), issue234_context and issue234_text (build the context and print), quantize_ctx and the other operations (the code under test); also read through to_string and inspect (print the result) (they read the operands and results, not the code under test)
test "other operations that produce such a zero fold as well (issue 234)" {
  let ctx = DecimalContext::decimal64()
  let zero = Decimal::from_string("0E+380").unwrap()
  let one = Decimal::from_string("1").unwrap()
  let results = [
    zero.apply_ctx(ctx),
    zero.plus_ctx(ctx),
    zero.add_ctx(zero, ctx),
    zero.mul_ctx(one, ctx),
    zero.div_ctx(one, ctx),
    Decimal::from_string("0").unwrap().scaleb_ctx(Decimal::from_int(380), ctx),
    zero.to_integral_exact_ctx(ctx),
  ]
  for result in results {
    assert_eq(result.0.to_string(), "0E+369")
  }
}
