// `pow` with a signaling NaN operand (#289). The two shortcuts "pow(x, +-0) is 1"
// and "pow(+1, y) is 1" returned 1 with no flags before any NaN handling, so
// pow(sNaN, 0) and pow(+1, sNaN) ignored the signaling NaN.
//
// Clauses, quoted from the text of IEEE Std 754-2019 (pdftotext of the PDF):
//
//   [9.2.1] "pow (x, ±0) is 1 if x is not a signaling NaN" and
//           "pow (+1, y) is 1 for any y (even a quiet NaN)".
//   [9.2]   "An operation that returns a floating-point result shall return a
//           quiet NaN as a result if there is a signaling NaN among the
//           operation’s operands." and "invalid operation: For all operations,
//           signaling NaN operands shall signal the invalid operation
//           exception."
//   [7.2 a] invalid operation for "any general-computational operation on a
//           signaling NaN (see 6.2)".
//   [9.2]   "An operation that returns a floating-point result shall return a
//           quiet NaN as a result if there is a quiet NaN among the
//           operation’s operands, except in the cases stated otherwise in this
//           subclause." (the quiet NaN rows below)

///|
fn pow_nan_operand(
  kind : String,
  payload : UInt64,
  precision : Int32,
) -> BinFloat {
  let coefficient = BinCoeff::from_uint64(payload)
  match kind {
    "+qnan" => BinFloat::quiet_nan(payload=coefficient, precision~)
    "-qnan" =>
      BinFloat::quiet_nan(payload=coefficient, negative=true, precision~)
    "+snan" => BinFloat::signaling_nan(payload=coefficient, precision~)
    "-snan" =>
      BinFloat::signaling_nan(payload=coefficient, negative=true, precision~)
    _ => abort("unknown NaN kind " + kind)
  }
}

///|
fn pow_contexts() -> Array[BinaryContext] {
  [
    BinaryContext::unbounded(53),
    BinaryContext::unbounded(2),
    BinaryContext::binary64(),
    BinaryContext::new(24, e_min=-6, e_max=7),
    BinaryContext::new(
      113,
      rounding=BinaryRoundingMode::RoundTowardZero,
      e_min=-16382,
      e_max=16383,
    ),
  ]
}

///|
test "pow signals a signaling NaN base or exponent in every shortcut" {
  let others : Array[(String, BinFloat)] = [
    ("0", BinFloat::zero()),
    ("-0", BinFloat::negative_zero()),
    ("+1", BinFloat::one()),
    ("2", BinFloat::from_int(2)),
    ("-3", BinFloat::from_int(-3)),
    ("1/2", BinFloat::make(BinCoeff::one(), -1, 53)),
    ("+inf", BinFloat::inf(Sign::Positive)),
    ("-inf", BinFloat::inf(Sign::Negative)),
  ]
  let mut cases = 0
  for context in pow_contexts() {
    for kind in ["+snan", "-snan"] {
      let snan = pow_nan_operand(kind, 0x5aUL, 53)
      for other in others {
        // sNaN as the base, then as the exponent: a quiet NaN with the sign
        // and payload of the signaling one, and invalid.
        for swapped in [false, true] {
          let (result, flags) = if swapped {
            other.1.try_pow_ctx(snan, context).unwrap()
          } else {
            snan.try_pow_ctx(other.1, context).unwrap()
          }
          let label = "pow(\{if swapped { other.0 } else { kind }}, \{if swapped { kind } else { other.0 }})"
          assert_true(result.classify() == FpClass::NaN, msg=label)
          assert_true(result.is_quiet_nan(), msg=label + " is quiet")
          assert_true(flags.invalid_operation(), msg=label + " raises invalid")
          assert_eq(
            result.is_negative(),
            snan.is_negative(),
            msg=label + " sign",
          )
          assert_eq(
            result.nan_payload().to_string(),
            snan.nan_payload().to_string(),
            msg=label + " payload",
          )
          assert_false(flags.inexact() || flags.overflow() || flags.underflow())
          cases += 1
        }
      }
      // Both operands NaN, one of them signaling: still a quiet NaN, invalid.
      for quiet in ["+qnan", "-qnan"] {
        let q = pow_nan_operand(quiet, 7UL, 53)
        for swapped in [false, true] {
          let (result, flags) = if swapped {
            q.try_pow_ctx(snan, context).unwrap()
          } else {
            snan.try_pow_ctx(q, context).unwrap()
          }
          assert_true(result.is_quiet_nan())
          assert_true(flags.invalid_operation())
          cases += 1
        }
      }
    }
  }
  assert_eq(cases, 5 * 2 * (8 * 2 + 4))
}

///|
test "pow keeps its quiet NaN shortcuts and propagation" {
  let q = pow_nan_operand("-qnan", 9UL, 53)
  for context in pow_contexts() {
    // pow(qNaN, 0) = 1 and pow(+1, qNaN) = 1, without a flag.
    for zero in [BinFloat::zero(), BinFloat::negative_zero()] {
      let (result, flags) = q.try_pow_ctx(zero, context).unwrap()
      assert_eq(result.to_string(), "1p0")
      assert_eq(flags, BinaryFlags::new())
    }
    let (result, flags) = BinFloat::one().try_pow_ctx(q, context).unwrap()
    assert_eq(result.to_string(), "1p0")
    assert_eq(flags, BinaryFlags::new())
    // Every other quiet NaN case propagates the NaN, sign and payload kept,
    // with no flag.
    for
      other in [
        BinFloat::from_int(2),
        BinFloat::from_int(-3),
        BinFloat::inf(Sign::Negative),
      ] {
      for swapped in [false, true] {
        let (result, flags) = if swapped {
          other.try_pow_ctx(q, context).unwrap()
        } else {
          q.try_pow_ctx(other, context).unwrap()
        }
        assert_true(result.is_quiet_nan())
        assert_true(result.is_negative())
        assert_eq(result.nan_payload().to_string(), "9")
        assert_eq(flags, BinaryFlags::new())
      }
    }
  }
}

///|
test "pow_ctx and pow agree with try_pow_ctx on a signaling NaN" {
  let snan = pow_nan_operand("+snan", 3UL, 53)
  let context = BinaryContext::unbounded(53)
  let (value, flags) = snan.pow_ctx(BinFloat::zero(), context)
  assert_true(value.is_quiet_nan())
  assert_true(flags.invalid_operation())
  let (value, flags) = BinFloat::one().pow_ctx(snan, context)
  assert_true(value.is_quiet_nan())
  assert_true(flags.invalid_operation())
  assert_true(snan.pow(BinFloat::zero()).is_quiet_nan())
  assert_true(BinFloat::one().pow(snan).is_quiet_nan())
}
