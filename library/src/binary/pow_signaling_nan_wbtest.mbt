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
) -> Binary {
  let coefficient = BinCoeff::from_uint64(payload)
  match kind {
    "+qnan" => Binary::quiet_nan(payload=coefficient, precision~)
    "-qnan" => Binary::quiet_nan(payload=coefficient, negative=true, precision~)
    "+snan" => Binary::signaling_nan(payload=coefficient, precision~)
    "-snan" =>
      Binary::signaling_nan(payload=coefficient, negative=true, precision~)
    _ => abort("unknown NaN kind " + kind)
  }
}

///|
fn pow_contexts() -> Array[BinaryContext] {
  [
    BinaryContext::new(precision=53),
    BinaryContext::new(precision=2),
    BinaryContext::binary64(),
    BinaryContext::new(precision=24, e_max=7),
    BinaryContext::new(
      precision=113,
      rounding=BinaryRoundingMode::RoundTowardZero,
      e_max=16383,
    ),
  ]
}

///|
// oracle: A, S
// source: written out: pow(qNaN, 0) = 1 and pow(+1, qNaN) = 1 without a flag (IEEE 754-2019 9.2.1), any other quiet NaN case returns a quiet NaN with the sign kept and no flag, a signaling NaN gives a quiet NaN with invalid and no other flag (6.2); the payload expected is nan_payload_in, which calls binary_convert_nan, so the payload truncation is a consistency claim (S)
// shares: nan_payload_in (calls binary_convert_nan, the NaN conversion that the code under test also uses), pow_nan_operand builds the operands, Binary::to_string, the flag accessors
test "pow signals a signaling NaN base or exponent in every shortcut" {
  let others : Array[(String, Binary)] = [
    ("0", Binary::zero()),
    ("-0", Binary::negative_zero()),
    ("+1", Binary::one()),
    ("2", Binary::from_int(2)),
    ("-3", Binary::from_int(-3)),
    ("1/2", Binary::make(BinCoeff::one(), -1, 53)),
    ("+inf", Binary::inf()),
    ("-inf", Binary::inf(negative=true)),
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
            result.is_sign_minus(),
            snan.is_sign_minus(),
            msg=label + " sign",
          )
          assert_eq(
            result.nan_payload().to_string(),
            nan_payload_in(snan.nan_payload(), context.precision()),
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
// oracle: A, S
// source: written out: pow(qNaN, 0) = 1 and pow(+1, qNaN) = 1 without a flag (IEEE 754-2019 9.2.1), any other quiet NaN case returns a quiet NaN with the sign kept and no flag, a signaling NaN gives a quiet NaN with invalid and no other flag (6.2); the payload expected is nan_payload_in, which calls binary_convert_nan, so the payload truncation is a consistency claim (S)
// shares: nan_payload_in (calls binary_convert_nan, the NaN conversion that the code under test also uses), pow_nan_operand builds the operands, Binary::to_string, the flag accessors
test "pow keeps its quiet NaN shortcuts and propagation" {
  let q = pow_nan_operand("-qnan", 9UL, 53)
  for context in pow_contexts() {
    // pow(qNaN, 0) = 1 and pow(+1, qNaN) = 1, without a flag.
    for zero in [Binary::zero(), Binary::negative_zero()] {
      let (result, flags) = q.try_pow_ctx(zero, context).unwrap()
      assert_eq(result.to_string(), "1p0")
      assert_eq(flags, BinaryFlags::new())
    }
    let (result, flags) = Binary::one().try_pow_ctx(q, context).unwrap()
    assert_eq(result.to_string(), "1p0")
    assert_eq(flags, BinaryFlags::new())
    // Every other quiet NaN case propagates the NaN, sign and payload kept,
    // with no flag.
    for
      other in [
        Binary::from_int(2),
        Binary::from_int(-3),
        Binary::inf(negative=true),
      ] {
      for swapped in [false, true] {
        let (result, flags) = if swapped {
          other.try_pow_ctx(q, context).unwrap()
        } else {
          q.try_pow_ctx(other, context).unwrap()
        }
        assert_true(result.is_quiet_nan())
        assert_true(result.is_sign_minus())
        assert_eq(
          result.nan_payload().to_string(),
          nan_payload_in(BinCoeff::from_uint64(9UL), context.precision()),
        )
        assert_eq(flags, BinaryFlags::new())
      }
    }
  }
}

///|
// oracle: A
// source: written out from IEEE Std 754-2019 9.2 and 7.2 a): a signaling NaN operand gives a quiet NaN with invalid, also where pow(x, +-0) and pow(+1, y) would otherwise be 1, in the pow_ctx and the pow forms
// shares: pow_nan_operand builds the signaling NaN with Binary::signaling_nan; pow_ctx and pow are the code under test; is_quiet_nan and invalid_operation read the result
test "pow_ctx and pow agree with try_pow_ctx on a signaling NaN" {
  let snan = pow_nan_operand("+snan", 3UL, 53)
  let context = BinaryContext::new(precision=53)
  let (value, flags) = snan.pow_ctx(Binary::zero(), context)
  assert_true(value.is_quiet_nan())
  assert_true(flags.invalid_operation())
  let (value, flags) = Binary::one().pow_ctx(snan, context)
  assert_true(value.is_quiet_nan())
  assert_true(flags.invalid_operation())
  assert_true(snan.pow(Binary::zero()).is_quiet_nan())
  assert_true(Binary::one().pow(snan).is_quiet_nan())
}
