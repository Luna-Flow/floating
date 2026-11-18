// `pown` near 2^e_min in a context that has no range of its own: the Ziv
// loop took the "unbounded" rounding of the after-rounding tininess test from
// a `BinaryContext::unbounded`, which still has the implementation subnormal
// range, so the value was rounded onto the subnormal grid and the underflow
// flag of a result that is tiny only before landing on 2^e_min was lost.
//
// Clause, quoted from the text of IEEE Std 754-2019 (pdftotext of the PDF):
//
//   [7.5.a] "after rounding — when a non-zero result computed as though the
//           exponent range were unbounded would lie strictly between ± b emin"
//
// Rows: 1.5^n at p = 2 has 2^q = 2^(e_min - 1) as its smallest positive value.
// For n = -1835573772 the exact value is 1.05 * 2^q and for n = -1835573771 it
// is 1.58 * 2^q. Rounded to 2 bits without a range these are 1.5 * 2^q, strictly
// below 2^e_min = 2 * 2^q: tiny after rounding, although the subnormal grid
// delivers 2^e_min (RTP, RAZ, and RNE for the second value).

///|
test "pown tininess after rounding at the implementation subnormal limit" {
  let base = BinFloat::make(BinCoeff::from_uint64(3UL), -1, 53)
  let mut cases = 0
  for n in [-1835573772, -1835573771] {
    // The reference: a 200-bit value rounded by `round_ctx`, which decides
    // tininess from the p-bit rounding of the exact value.
    let reference = base.pown_ctx(n, BinaryContext::unbounded(200)).0
    for mode in e2s_modes() {
      for
        tininess in [
          TininessDetection::AfterRounding,
          TininessDetection::BeforeRounding,
        ] {
        let ctx = BinaryContext::new(2, rounding=mode, tininess~)
        let (value, flags) = base.pown_ctx(n, ctx)
        let (expected, expected_flags) = reference.round_ctx(ctx)
        let label = "pown(1.5, \{n}) \{e2s_mode_name(mode)} \{e2s_tininess_name(tininess)}"
        assert_eq(
          "\{label} => \{value} \{e2s_flags(flags)}",
          "\{label} => \{expected} \{e2s_flags(expected_flags)}",
        )
        cases += 1
      }
    }
  }
  assert_eq(cases, 24)
}
