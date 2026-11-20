///|
/// `decimal` and `decimal_gda`
/// agree on a zero `quantize` and `rescale` result under `clamp`: the exponent
/// asked for is folded down to `e_max - precision + 1` with `clamped` when it is
/// above it, and kept otherwise, and a target above `e_max` is invalid in both
/// (issue 234; `decimal_gda` folds since issue 419).

///|
let clamp_fold_contexts : Array[(String, Int32, Int32, Int32)] = [
  ("decimal32", 7, -95, 96),
  ("decimal64", 16, -383, 384),
  ("decimal128", 34, -6143, 6144),
  ("small", 5, -2, 3),
]

///|
fn clamp_fold_flags(f : @decimal.DecimalFlags) -> String {
  (if f.inexact() { "x" } else { "." }) +
  (if f.rounded() { "r" } else { "." }) +
  (if f.invalid_operation() { "i" } else { "." }) +
  (if f.overflow() { "o" } else { "." }) +
  (if f.underflow() { "u" } else { "." }) +
  (if f.subnormal() { "s" } else { "." }) +
  (if f.clamped() { "c" } else { "." })
}

///|
fn clamp_fold_gda_flags(f : @decimal_gda.GdaFlags) -> String {
  (if f.inexact() { "x" } else { "." }) +
  (if f.rounded() { "r" } else { "." }) +
  (if f.invalid_operation() { "i" } else { "." }) +
  (if f.overflow() { "o" } else { "." }) +
  (if f.underflow() { "u" } else { "." }) +
  (if f.subnormal() { "s" } else { "." }) +
  (if f.clamped() { "c" } else { "." })
}

///|
fn clamp_fold_text(is_nan : Bool, text : String) -> String {
  if is_nan {
    "NaN"
  } else {
    text
  }
}

///|
test "decimal and decimal_gda agree on a zero quantize and rescale" {
  for entry in clamp_fold_contexts {
    let (name, precision, e_min, e_max) = entry
    let top = e_max - precision + 1
    let ieee = @decimal.DecimalContext::new(precision~, e_max~)
    let gda = @decimal_gda.GdaContext::new(
      precision~,
      e_min~,
      e_max~,
      clamp=true,
    )
    // generated zero cases: every target around the top and up to e_max + 1,
    // both signs, cohorts of the operand, and the smallest targets
    let targets : Array[Int32] = [
      e_min - precision + 1,
      -1,
      0,
      1,
      top - 2,
      top - 1,
      top,
      top + 1,
      top + 2,
      (top + e_max) / 2,
      e_max - 1,
      e_max,
      e_max + 1,
    ]
    for zero in ["0", "-0", "0E+5", "0E-3", "-0E+2"] {
      for target in targets {
        let label = "\{name} quantize \{zero} to exponent \{target}"
        let quantum = "1E" +
          (if target < 0 { "" } else { "+" }) +
          target.to_string()
        let a = @decimal.Decimal::from_string(zero)
          .unwrap()
          .quantize_ctx(@decimal.Decimal::from_string(quantum).unwrap(), ieee)
        let b = @decimal_gda.quantize(
          @decimal_gda.Decimal::from_string(zero).unwrap(),
          @decimal_gda.Decimal::from_string(quantum).unwrap(),
          gda,
        )
        assert_eq(
          (
            label,
            clamp_fold_text(a.0.is_nan(), a.0.to_string()),
            clamp_fold_flags(a.1),
          ),
          (
            label,
            clamp_fold_text(b.value().is_nan(), b.value().to_string()),
            clamp_fold_gda_flags(b.raised()),
          ),
        )
        let c = @decimal.Decimal::from_string(zero)
          .unwrap()
          .rescale_ctx(@decimal.Decimal::from_int(target), ieee)
        let d = @decimal_gda.rescale(
          @decimal_gda.Decimal::from_string(zero).unwrap(),
          @decimal_gda.Decimal::from_int(target),
          gda,
        )
        assert_eq(
          (
            label + " rescale",
            clamp_fold_text(c.0.is_nan(), c.0.to_string()),
            clamp_fold_flags(c.1),
          ),
          (
            label + " rescale",
            clamp_fold_text(d.value().is_nan(), d.value().to_string()),
            clamp_fold_gda_flags(d.raised()),
          ),
        )
      }
    }
  }
}
