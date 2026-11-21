// `rootn(x, 0)` is an invalid operation for every x, including a quiet NaN and
// +-0, and it is not divideByZero (#294, decided).
//
// Clauses, quoted from the text of IEEE Std 754-2019 (pdftotext of the PDF):
//
//   [Table 9.1] rootn(x, n): "n = 0: invalid operation;" (beside
//               "x = 0 and n < 0: divideByZero").
//   [7.3]       "The divideByZero exception shall be signaled if and only if an
//               exact infinite result is defined for an operation on finite
//               operands." An infinite result is defined for rootn(+-0, n)
//               with n < 0, not for n = 0.
//   [9.2.1]     "rootn (±0, n) is ±∞ and signals the divideByZero exception for
//               odd n < 0" and "rootn (±0, n) is +∞ and signals the
//               divideByZero exception for even n < 0".

///|
test "rootn with degree zero is invalid for every operand and never divideByZero" {
  let operands : Array[(String, BinFloat)] = [
    ("qNaN", BinFloat::quiet_nan()),
    ("-qNaN", BinFloat::quiet_nan(negative=true)),
    ("sNaN", BinFloat::signaling_nan()),
    ("+0", BinFloat::zero()),
    ("-0", BinFloat::negative_zero()),
    ("1", BinFloat::one()),
    ("-8", BinFloat::from_int(-8)),
    ("2", BinFloat::from_int(2)),
    ("+inf", BinFloat::inf(Sign::Positive)),
    ("-inf", BinFloat::inf(Sign::Negative)),
  ]
  let contexts = [
    BinaryContext::new(precision=53),
    BinaryContext::new(precision=2),
    BinaryContext::binary64(),
    BinaryContext::new(precision=24, e_max=7),
  ]
  let mut cases = 0
  for context in contexts {
    for operand in operands {
      let label = "rootn(\{operand.0}, 0)"
      // S4: the try_ form returns the value too, a NaN with invalid_operation.
      match operand.1.try_rootn_ctx(0, context) {
        Ok((nan, nan_flags)) => {
          assert_true(nan.is_nan(), msg=label)
          assert_true(nan_flags.invalid_operation(), msg=label)
          assert_false(nan_flags.not_computed(), msg=label)
        }
        Err(_) => abort(label + ": a domain case must not be an Err")
      }
      // The contextual form delivers a quiet NaN with invalid only.
      let (value, flags) = operand.1.rootn_ctx(0, context)
      assert_true(value.is_quiet_nan(), msg=label + " is a quiet NaN")
      assert_true(flags.invalid_operation(), msg=label + " is invalid")
      assert_false(flags.division_by_zero(), msg=label + " is not divideByZero")
      assert_false(flags.inexact() || flags.overflow() || flags.underflow())
      cases += 1
    }
  }
  assert_eq(cases, 4 * 10)
}

///|
test "rootn of zero with a negative degree is the divideByZero case" {
  for context in [BinaryContext::new(precision=53), BinaryContext::binary64()] {
    for degree in [-1, -2, -3, -4, -1000001] {
      for zero in [BinFloat::zero(), BinFloat::negative_zero()] {
        let (value, flags) = zero.rootn_ctx(degree, context)
        let odd = degree % 2 != 0
        let negative = zero.is_negative() && odd
        let label = "rootn(\{zero}, \{degree})"
        assert_eq(value.classify(), FpClass::Infinity, msg=label)
        assert_eq(value.is_negative(), negative, msg=label)
        assert_true(flags.division_by_zero(), msg=label)
        assert_false(flags.invalid_operation(), msg=label)
      }
    }
  }
}
