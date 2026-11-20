// `expm1` just past its overflow threshold: the pre-check of the Ziv loop used
// log2(expm1 x) >= x log2(e) - 1, which certifies overflow only from
// x log2(e) >= e_max + 2. For x log2(e) in [e_max + 1, e_max + 2) the result is
// beyond the range, the working enclosures overflow, and the loop gave up with
// a certification failure (NaN with invalid) instead of the overflow result.
//
// Clauses, quoted from the text of IEEE Std 754-2019 (pdftotext of the PDF):
//
//   [9.2]   "A conforming operation shall return results correctly rounded for
//           the applicable rounding direction for all operands in its domain."
//   [7.4]   overflow: the rounded result that is delivered is infinity or the
//           largest finite value by the rounding direction, with inexact.
//
// Reference: for x >= 64, expm1(x) = exp(x) - 1 is within 2^-60 relative of
// exp(x), far less than the distance from any breakpoint that matters here
// (the arguments below are at least 2^-12 of a binade from the threshold), so
// `exp` gives the same value and flags.

///|
test "expm1 overflows from x log2(e) = e_max + 1 on, like exp" {
  // 744261117.95... = (e_max + 1) ln 2; the arguments lie between
  // x log2(e) = e_max + 1.05 and e_max + 1.77.
  let mut cases = 0
  for numerator in [744261118 * 2, 744261118 * 2 + 1, 744261118 * 2 + 2] {
    let x = BinFloat::make(BinCoeff::from_uint64(numerator.to_uint64()), -1, 64)
    for p in [2, 24, 53] {
      for mode in e2s_modes() {
        let ctx = BinaryContext::new(precision=p, rounding=mode)
        let (value, flags) = binary_defined_or_nan(x.try_expm1_ctx(ctx), ctx)
        let (expected, expected_flags) = x.exp_ctx(ctx)
        let label = "expm1(\{x}) p=\{p} \{e2s_mode_name(mode)}"
        assert_eq(
          "\{label} => \{value} \{e2s_flags(flags)}",
          "\{label} => \{expected} \{e2s_flags(expected_flags)}",
        )
        cases += 1
      }
    }
  }
  assert_eq(cases, 45)
}
