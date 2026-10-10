///|
/// A sum with a zero operand is the nonzero operand at the smaller exponent.
/// Only the delivered result may be clamped, so moving the nonzero operand
/// towards that exponent must come before the clamp check, not after
/// clamping the operand at its own exponent. Expected values from Python
/// `decimal` in the same contexts.
test "a zero addend does not leak a clamp of the other operand" {
  let cases : Array[
    (Int, Int, Int, DecimalRoundingMode, String, String, String, String),
  ] = [
    (3, -5, 5, HalfUp, "7E+4", "-0E-20", "", "7.00E+4"),
    (9, -20, 20, ZeroFiveUp, "-0E+8", "-5E+19", "", "-5.00000000E+19"),
    (9, -20, 20, Up, "-0E-28", "-598E+17", "", "-5.98000000E+19"),
    (9, -20, 20, Up, "0E-19", "-8131E+16", "", "-8.13100000E+19"),
    (7, -95, 96, HalfEven, "1E+90", "1E+1", "-0E+80", "1.000000E+91"),
  ]
  for entry in cases {
    let (precision, e_min, e_max, mode, left, right, addend, expected) = entry
    let ctx = DecimalContext::new(
      precision~,
      decimal_rounding=mode,
      e_min~,
      e_max~,
      clamp=true,
    ).unwrap()
    let x = Decimal::from_string(left).unwrap()
    let y = Decimal::from_string(right).unwrap()
    let (value, flags) = if addend == "" {
      x.add_ctx(y, ctx)
    } else {
      x.fma_ctx(y, Decimal::from_string(addend).unwrap(), ctx)
    }
    assert_eq(value.to_string(), expected)
    assert_true(flags.rounded)
    assert_false(flags.clamped)
    assert_false(flags.inexact)
  }
}
