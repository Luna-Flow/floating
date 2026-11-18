// Regression tests for the same defect as #271 in `pow`: an exact power of two
// below 2^e_min came out of `binary_pow_exactness` as +0 with no flags, because
// the exact result was built with a one-bit `BinFloat::make`, which flushes it
// before the context rounds it.
//
// Clauses, quoted from the text of IEEE Std 754-2019 (pdftotext of the PDF):
//
//   [9.2]   "A conforming operation shall return results correctly rounded for
//           the applicable rounding direction for all operands in its domain."
//   [7.5.f] "if the rounded result is inexact — that is, it differs from what
//           would have been computed were both exponent range and precision
//           unbounded — the underflow flag shall be raised and the inexact (see
//           7.6) exception shall be signaled. If the rounded result is exact,
//           no flag is raised and no inexact exception is signaled."
//
// For a positive base 2^(-2j) and the exponent m / 2 (m odd) the exact result
// is 2^(-j m), the dyadic case of `binary_pow_exactness`. The expectation comes
// from the independent model of `exp2_subnormal_wbtest.mbt`.

///|
test "pow of a power of two with a half-integer exponent rounds the exact result" {
  let mut cases = 0
  for p in [1, 2, 3, 53, 300] {
    let q = binary_implementation_e_min - (p - 1)
    for mode in e2s_modes() {
      for
        n in [
          q - 2,
          q - 1,
          q,
          q + 1,
          binary_implementation_e_min - 1,
          binary_implementation_e_min,
          -1073741825,
          -1073741827,
          -2147483647,
        ] {
        // n = -j * m with m odd and j a power of two, base 2^(-2 j).
        let magnitude = -n
        let mut j = 1
        while magnitude / j % 2 == 0 {
          j = j * 2
        }
        let m = magnitude / j
        if 2 * j <= 1073741824 && m >= 3 {
          let base = BinFloat::make(BinCoeff::one(), -2 * j, 53)
          let exponent = BinFloat::make(
            BinCoeff::from_uint64(m.to_uint64()),
            -1,
            64,
          )
          let ctx = BinaryContext::new(p, rounding=mode)
          let (value, flags) = base.pow_ctx(exponent, ctx)
          let (expected, expected_flags) = e2s_model(
            n, p, mode, binary_implementation_e_min, binary_implementation_e_max,
          )
          let label = "pow(2^\{-2 * j}, \{m}/2) p=\{p} \{e2s_mode_name(mode)}"
          assert_eq("\{label} => \{value}", "\{label} => \{expected}")
          assert_eq(
            "\{label} => \{e2s_flags(flags)}",
            "\{label} => \{expected_flags}",
          )
          cases += 1
        }
      }
    }
  }
  assert_true(cases > 100)
}

///|
test "pow exact subnormal regression row" {
  // pow(1/4, 2^29 + 1/2) = 2^-(2^30 + 1), exactly representable at p = 3.
  let quarter = BinFloat::make(BinCoeff::one(), -2, 53)
  let exponent = BinFloat::make(BinCoeff::from_uint64(1073741825UL), -1, 64)
  let (value, flags) = quarter.pow_ctx(exponent, BinaryContext::unbounded(3))
  assert_eq("\{value} \{e2s_flags(flags)}", "1p-1073741825 ---")
}
