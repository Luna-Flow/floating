///|
/// `quantize` and `rescale` of a zero under `clamp` (issue 419). decNumber's
/// `decQuantizeOp` gives a zero operand the exponent asked for, refuses only an
/// exponent above `emax - digits + 1` (the bound of a one-digit zero, `e_max`),
/// and then calls `decFinalize`, whose clamp branch folds an exponent above
/// `emax - precision + 1` down to it and raises Clamped; every other zero
/// result of the package already does that.

///|
/// (context, zero, target quantum, expected result, clamped)
let issue419_rows : Array[(String, String, String, String, Bool)] = [
  ("decimal32", "0", "1E+96", "0E+90", true),
  ("decimal32", "0", "1E+91", "0E+90", true),
  ("decimal32", "0", "1E+90", "0E+90", false),
  ("decimal32", "-0", "1E+96", "-0E+90", true),
  ("decimal32", "0E+5", "1E+96", "0E+90", true),
  ("decimal32", "0", "1E+97", "NaN", false),
  ("decimal64", "0", "1E+380", "0E+369", true),
  ("decimal64", "-0", "1E+380", "-0E+369", true),
  ("decimal64", "0E-3", "1E+384", "0E+369", true),
  ("decimal64", "0", "1E+369", "0E+369", false),
  ("decimal64", "0", "1E+368", "0E+368", false),
  ("decimal64", "0", "1", "0", false),
  ("decimal64", "-0", "1E-398", "-0E-398", false),
  ("decimal64", "0", "1E+385", "NaN", false),
  ("decimal128", "0", "1E+6144", "0E+6111", true),
  ("decimal128", "0", "1E+6112", "0E+6111", true),
  ("decimal128", "0", "1E+6111", "0E+6111", false),
  ("decimal128", "-0", "1E+6144", "-0E+6111", true),
  ("not clamped", "0", "1E+380", "0E+380", false),
  ("not clamped", "-0", "1E+384", "-0E+384", false),
  ("subset", "0", "1E+380", "0E+369", true),
  ("subset", "-0", "1E+380", "0E+369", true),
  ("subset", "0", "1E+369", "0E+369", false),
]

///|
fn issue419_parameters(name : String) -> (Int32, Int32, Int32, Bool, Bool) {
  match name {
    "decimal32" => (7, -95, 96, true, true)
    "decimal64" => (16, -383, 384, true, true)
    "decimal128" => (34, -6143, 6144, true, true)
    "not clamped" => (16, -383, 384, false, true)
    "subset" => (16, -383, 384, true, false)
    _ => abort("unexpected context \{name}")
  }
}

///|
fn issue419_text(value : Decimal) -> String {
  if value.is_nan() {
    "NaN"
  } else {
    value.to_string()
  }
}

///|
test "quantize and rescale of a zero fold down under clamp and raise Clamped (issue 419)" {
  for row in issue419_rows {
    let (name, zero, quantum, expected, clamped) = row
    let (precision, e_min, e_max, clamp, extended) = issue419_parameters(name)
    let ctx = DecimalContext::new(precision~, e_min~, e_max~, clamp~, extended~)
    let gda = GdaContext::new(precision~, e_min~, e_max~, clamp~, extended~)
    let x = Decimal::from_string(zero).unwrap()
    let q = Decimal::from_string(quantum).unwrap()
    let label = "\{name} quantize \{zero} \{quantum}"
    let (value, flags) = x.quantize(q, ctx)
    assert_eq((label, issue419_text(value)), (label, expected))
    assert_eq((label, flags.clamped), (label, clamped))
    let outcome = quantize(x, q, gda)
    assert_eq(
      (label + " adapter", issue419_text(outcome.value())),
      (label + " adapter", expected),
    )
    assert_eq(
      (label + " adapter", outcome.raised().clamped),
      (label + " adapter", clamped),
    )
    if !value.is_nan() {
      let exponent = Decimal::from_int(q.exponent10)
      let (by_rescale, rescale_flags) = x.rescale(exponent, ctx)
      assert_eq(
        (label + " rescale", issue419_text(by_rescale)),
        (label + " rescale", expected),
      )
      assert_eq(
        (label + " rescale", rescale_flags.clamped),
        (label + " rescale", clamped),
      )
      let adapter = rescale(x, exponent, gda)
      assert_eq(
        (label + " rescale adapter", issue419_text(adapter.value())),
        (label + " rescale adapter", expected),
      )
      assert_eq(
        (label + " rescale adapter", adapter.raised().clamped),
        (label + " rescale adapter", clamped),
      )
    }
  }
}

///|
test "a non-zero quantize result is not changed by the zero fold (issue 419)" {
  let ctx = DecimalContext::new(precision=16, e_min=-383, e_max=384, clamp=true)
  let d = fn(s : String) { Decimal::from_string(s).unwrap() }
  let (small, flags) = d("5").quantize(d("1E+380"), ctx)
  assert_eq(small.to_string(), "0E+369")
  assert_true(flags.clamped && flags.inexact && flags.rounded)
  let (value, flags) = d("123.456").quantize(d("1E-2"), ctx)
  assert_eq(value.to_string(), "123.46")
  assert_false(flags.clamped)
}
