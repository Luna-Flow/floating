// `hypot` with an infinity beside a signaling NaN (#293). The infinity shortcut
// returned +inf (with invalid) for hypot(+-inf, sNaN); the value must be a quiet
// NaN.
//
// Clauses, quoted from the text of IEEE Std 754-2019 (pdftotext of the PDF):
//
//   [9.2]   "For the hypot operation, hypot(±0, ±0) is +0, hypot(±∞, qNaN) is
//           +∞, and hypot(qNaN, ±∞) is +∞." (quiet NaN only)
//   [9.2]   "An operation that returns a floating-point result shall return a
//           quiet NaN as a result if there is a signaling NaN among the
//           operation’s operands." and "invalid operation: For all operations,
//           signaling NaN operands shall signal the invalid operation
//           exception."
//   [7.2 a] invalid operation for "any general-computational operation on a
//           signaling NaN (see 6.2)".

///|
test "hypot of an infinity and a signaling NaN is a quiet NaN with invalid" {
  let contexts = [
    BinaryContext::unbounded(53),
    BinaryContext::unbounded(2),
    BinaryContext::binary64(),
    BinaryContext::new(24, e_min=-6, e_max=7),
  ]
  let mut cases = 0
  for context in contexts {
    for
      infinity in [BinFloat::inf(Sign::Positive), BinFloat::inf(Sign::Negative)] {
      for negative in [false, true] {
        let snan = BinFloat::signaling_nan(
          payload=BinCoeff::from_uint64(0x2bUL),
          negative~,
        )
        for swapped in [false, true] {
          let (value, flags) = if swapped {
            infinity.try_hypot_ctx(snan, context).unwrap()
          } else {
            snan.try_hypot_ctx(infinity, context).unwrap()
          }
          assert_true(value.is_quiet_nan())
          assert_eq(
            value.nan_payload().to_string(),
            nan_payload_in(BinCoeff::from_uint64(0x2bUL), context.precision()),
          )
          assert_eq(value.is_negative(), negative)
          assert_true(flags.invalid_operation())
          assert_false(flags.inexact() || flags.overflow() || flags.underflow())
          cases += 1
        }
      }
    }
    // A quiet NaN beside an infinity is still +inf with no flag.
    for
      infinity in [BinFloat::inf(Sign::Positive), BinFloat::inf(Sign::Negative)] {
      let qnan = BinFloat::quiet_nan(negative=true)
      for swapped in [false, true] {
        let (value, flags) = if swapped {
          infinity.try_hypot_ctx(qnan, context).unwrap()
        } else {
          qnan.try_hypot_ctx(infinity, context).unwrap()
        }
        assert_eq(value.to_string(), "inf")
        assert_eq(flags, BinaryFlags::new())
        cases += 1
      }
    }
    // Two infinities are +inf with no flag.
    let (value, flags) = BinFloat::inf(Sign::Negative)
      .try_hypot_ctx(BinFloat::inf(Sign::Negative), context)
      .unwrap()
    assert_eq(value.to_string(), "inf")
    assert_eq(flags, BinaryFlags::new())
    cases += 1
  }
  assert_eq(cases, 4 * (2 * 2 * 2 + 4 + 1))
}
