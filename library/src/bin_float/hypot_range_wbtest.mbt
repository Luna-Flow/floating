// `hypot` of operands whose exponent is beyond 2^29 in magnitude (#275). The
// exact sum of squares was built with a doubled exponent, which leaves the
// implementation range of `BinFloat::make`, so it came out as 0 or infinity
// with no flags (or as an error when the doubled exponent left the Int range).
//
// Clauses, quoted from the text of IEEE Std 754-2019 (pdftotext of the PDF):
//
//   [9.2]   Table 9.1: hypot(x, y) = √(x2 + y2), exceptions "overflow;
//           underflow"; "For the hypot operation, hypot(±0, ±0) is +0,
//           hypot(±∞, qNaN) is +∞, and hypot(qNaN, ±∞) is +∞."
//   [9.2]   "A conforming operation shall return results correctly rounded for
//           the applicable rounding direction for all operands in its domain."
//   [7.5]   underflow "when a tiny non-zero result is detected" (both
//           tininess rules), [7.4] overflow, [7.6] inexact.
//
// Model: hypot is homogeneous of degree one, so scaling both operands by an
// exact power of two scales the correctly rounded result by the same power as
// long as no range limit is involved. The reference scales the operands to the
// middle of the range, takes the hypot there with 200 extra bits, scales the
// value back exactly and rounds it with `round_ctx`, which owns the range
// rules (subnormal, overflow, both tininess modes).

///|
fn hypot_operand(
  coefficient : UInt64,
  exponent : Int32,
  negative : Bool,
) -> BinFloat {
  BinFloat::make(BinCoeff::from_uint64(coefficient), exponent, 64, negative~)
}

///|
fn hypot_reference(
  a : (UInt64, Int32),
  b : (UInt64, Int32),
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  let shift = Int32::min(a.1, b.1)
  let wide = BinaryContext::unbounded(context.precision + 200)
  let near_a = hypot_operand(a.0, a.1 - shift, false)
  let near_b = hypot_operand(b.0, b.1 - shift, false)
  let (middle, _) = near_a.hypot_ctx(near_b, wide)
  // Scale back by 2^shift exactly: same coefficient, shifted exponent.
  let scaled = BinFloat::make(
    middle.coefficient(),
    middle.exponent2() + shift,
    middle.coefficient().bit_length(),
  )
  let (value, flags) = scaled.round_ctx(context)
  // The result of these operands is never exact: inexact for every row.
  (value, { ..flags, inexact: true, })
}

///|
test "hypot of operands beyond 2^29 in exponent is correctly rounded" {
  let rows : Array[((UInt64, Int32), (UInt64, Int32))] = [
    ((1UL, -600000000), (1UL, -600000000)),
    ((1UL, -540000000), (1UL, -540000001)),
    ((1UL, 600000000), (1UL, 600000000)),
    ((3UL, -1073741780), (5UL, -1073741785)),
    ((1UL, -1073741700), (1UL, -1073741720)),
    ((1UL, -1073741780), (1UL, -1073741860)),
    ((7UL, -1073741800), (1UL, -1073741790)),
    ((3UL, -1073741860), (3UL, -1073741860)),
    ((1UL, 1073741000), (1UL, 1073740990)),
  ]
  let mut cases = 0
  for row in rows {
    let (a, b) = row
    let x = hypot_operand(a.0, a.1, false)
    let y = hypot_operand(b.0, b.1, true)
    for p in [2, 53, 100] {
      for mode in e2s_modes() {
        for
          tininess in [
            TininessDetection::AfterRounding,
            TininessDetection::BeforeRounding,
          ] {
          let ctx = BinaryContext::new(p, rounding=mode, tininess~)
          let (value, flags) = x.hypot_ctx(y, ctx)
          let (expected, expected_flags) = hypot_reference(a, b, ctx)
          let label = "hypot(\{a.0}p\{a.1}, \{b.0}p\{b.1}) p=\{p} \{e2s_mode_name(mode)} \{e2s_tininess_name(tininess)}"
          assert_eq(
            "\{label} => \{value} \{e2s_flags(flags)}",
            "\{label} => \{expected} \{e2s_flags(expected_flags)}",
          )
          cases += 1
        }
      }
    }
  }
  assert_eq(cases, 9 * 3 * 6 * 2)
}

///|
test "hypot with a zero operand is the other magnitude, exact, at any exponent" {
  for
    exponent in [-1073741860, -1073741823, -600000000, 0, 600000000, 1073741000] {
    let x = hypot_operand(5UL, exponent, true)
    for zero in [BinFloat::zero(), BinFloat::negative_zero()] {
      for swapped in [false, true] {
        let (value, flags) = if swapped {
          zero.hypot_ctx(x, BinaryContext::unbounded(53))
        } else {
          x.hypot_ctx(zero, BinaryContext::unbounded(53))
        }
        assert_eq(value.to_string(), "5p\{exponent}")
        assert_eq(e2s_flags(flags), "---")
      }
    }
  }
  let (value, flags) = BinFloat::negative_zero().hypot_ctx(
    BinFloat::zero(),
    BinaryContext::unbounded(53),
  )
  assert_eq(value.to_string(), "0")
  assert_eq(e2s_flags(flags), "---")
}
