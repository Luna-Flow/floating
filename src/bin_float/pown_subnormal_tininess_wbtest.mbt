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

///|
/// The Ziv interval of `pown` built its endpoints at their own bit length, so an
/// endpoint in the implementation subnormal range (3^n and 1.5^n near 2^(e_min -
/// p) at p = 40 to 43) was flushed to zero or to the smallest value of its
/// width, and directed rounding of a value between half and the whole smallest
/// subnormal came out on the wrong side. Rows from the range-boundary sweep,
/// with the reference rounded by `round_ctx` from a 300-bit `pown`.
test "pown directed rounding between half and the smallest subnormal" {
  // precision, base coefficient, base exponent, n
  let rows : Array[(Int32, Int64, Int32, Int32)] = [
    (40, 3L, 0, -677455689),
    (41, 3L, -1, -1835573840),
    (41, 3L, -1, -1835573839),
    (42, 3L, -1, -1835573839),
    (43, 0xb33333333333333L, -60, 2086665068),
  ]
  let mut cases = 0
  for row in rows {
    let (p, coefficient, exponent, n) = row
    let base = BinFloat::make(
      BinCoeff::from_uint64(coefficient.reinterpret_as_uint64()),
      exponent,
      64,
    )
    let reference = base.pown_ctx(n, BinaryContext::unbounded(300)).0
    for mode in e2s_modes() {
      let ctx = BinaryContext::new(p, rounding=mode)
      let (value, flags) = base.pown_ctx(n, ctx)
      let (expected, expected_flags) = reference.round_ctx(ctx)
      let label = "pown(\{base}, \{n}) p=\{p} \{e2s_mode_name(mode)}"
      assert_eq(
        "\{label} => \{value} \{e2s_flags(flags)}",
        "\{label} => \{expected} \{e2s_flags(expected_flags)}",
      )
      cases += 1
    }
  }
  assert_eq(cases, 30)
}
