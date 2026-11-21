///|
/// The rows of `decimal/zero_fold_issue234_wbtest.mbt` through the public
/// `quantize` of the GDA package, with the `clamped` column asserted. A zero
/// quantize result above `e_max - precision + 1` is folded down and `Clamped` is
/// raised (GDA 1.70, Exceptional conditions, Clamped; decNumber's `decQuantizeOp`
/// sets the exponent of the zero and `decFinalize` lowers it to
/// `emax - digits + 1` and raises Clamped). Oracle: the rule applied by hand
/// (A-literal rows).

///|
let issue234_gda_rows : Array[(String, String, String, String, Bool)] = [
  ("decimal64", "0", "1E+380", "0E+369", true),
  ("decimal64", "-0", "1E+380", "-0E+369", true),
  ("decimal64", "0E+5", "1E+380", "0E+369", true),
  ("decimal64", "0E-3", "1E+370", "0E+369", true),
  ("decimal64", "0", "1E+384", "0E+369", true),
  ("decimal64", "0", "1E+369", "0E+369", false),
  ("decimal64", "0", "1E+368", "0E+368", false),
  ("decimal64", "0", "1", "0", false),
  ("decimal64", "-0", "1E-398", "-0E-398", false),
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
fn issue234_gda_context(name : String) -> GdaContext {
  match name {
    "decimal32" => GdaContext::decimal32()
    "decimal64" => GdaContext::decimal64()
    "decimal128" => GdaContext::decimal128()
    _ => GdaContext::new(precision=5, e_min=-2, e_max=3, clamp=true)
  }
}

///|
test "a zero quantize result above the top exponent folds down and raises Clamped (issue 234)" {
  for row in issue234_gda_rows {
    let (name, zero, quantum, result, clamped) = row
    let label = "\{name} quantize \{zero} \{quantum}"
    let outcome = quantize(
      Decimal::from_string(zero).unwrap(),
      Decimal::from_string(quantum).unwrap(),
      issue234_gda_context(name),
    )
    assert_eq((label, outcome.value().to_string()), (label, result))
    assert_eq((label, outcome.raised().clamped()), (label, clamped))
    assert_false(outcome.raised().inexact(), msg=label)
  }
}
