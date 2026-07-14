# `bin_float` Conformance

This page records the `0.6.1` binary floating-point semantic and test
boundary. It is evidence for a stated, finite corpus; it is not a proof that
any implementation can be correct for every real input.

## Normative And Research Sources

- IEEE, *IEEE Standard for Floating-Point Arithmetic*, IEEE 754-2019:
  interchange formats, rounding-direction attributes, NaNs/infinities/signed
  zeros, exceptions, and tininess detection.
- S. Fousse, G. Hanrot, V. Lefèvre, P. Pélissier, and P. Zimmermann,
  [MPFR: A Multiple-Precision Binary Floating-Point Library with Correct Rounding](https://doi.org/10.1145/1236463.1236468),
  ACM TOMS 33(2), 2007. MPFR supplies the exact-result-then-one-rounding model
  used for arbitrary precisions.
- John Hauser's Berkeley [SoftFloat](https://www.jhauser.us/arithmetic/SoftFloat.html)
  and [TestFloat](https://www.jhauser.us/arithmetic/TestFloat.html), release
  3e, provide the independently generated IEEE result/flag vectors.

## Mathematical Model

A finite nonzero `BinFloat` denotes the dyadic real

`(-1)^negative * coefficient * 2^exponent2`, where `coefficient` is a
non-negative `BinCoeff`.

The finite coefficient is normalized by removing factors of two, while the
sign of zero remains observable. Infinity, qNaN, sNaN, NaN payload, and NaN
sign are explicit states rather than sentinel finite values.

For `add_ctx`, `sub_ctx`, `mul_ctx`, `div_ctx`, `sqrt_ctx`, and `pow_int_ctx`:

1. IEEE special cases are resolved before finite arithmetic.
2. Finite addition, subtraction, and multiplication use their exact dyadic
   result; division uses an exact integer quotient/remainder decision; square
   root brackets the exact real root with integer-square-root bounds.
3. The exact result is rounded once to the requested precision and rounding
   direction, then exponent-range/subnormal quantization is applied.
4. The returned `BinaryFlags` is derived from that mathematical result:
   inexact, underflow, overflow, division-by-zero, and invalid-operation.

This order matters. For example, binary16 `0x0400 * 0x3BFF` produces
`0x0400` with `inexact | underflow`; after-rounding tininess is determined from
the precision-rounded unbounded value, not merely from the final normal
interchange encoding.

No operation branches on test identifiers, test values, or corpus format.
The corpus interpreter is an adapter around the public contextual operations.

## Interchange And Context

`BinaryInterchange` decodes and encodes IEEE binary16, binary32, binary64, and
binary128 bit patterns. `BinaryContext` carries precision, rounding direction,
paired exponent limits, and before/after tininess detection. Encoding and
contextual arithmetic both return status flags; ordinary operators use an
unbounded nearest-even context and intentionally do not expose those flags.

NaN comparisons in the TestFloat adapter are class-based only when an expected
result is NaN. This is not a weakened finite-value comparison: non-NaN encoded
bits and all exception bits must match exactly. It reflects IEEE's permitted
choice of a newly generated NaN payload. The implementation itself preserves
the selected input NaN's sign/payload and quiets signaling NaNs.

## Declared Corpus And Results

The pinned full gate is documented in
[`testdata/bin_float/README.md`](../../../testdata/bin_float/README.md).

| Source | Scope | Result |
| --- | --- | --- |
| TestFloat 3e level 1, seed 1 | 4 formats × 5 operations × 5 rounding directions × 2 tininess modes | 7,461,360 / 7,461,360 |
| MPFR 4.2.2 `tests/data/sqrt` | all executable hexadecimal sqrt rows | 1,055 / 1,055 |
| MPFR 4.2.2 `pow_si` fixture | 4 precisions × 5 supported roundings × 6 inputs | 120 / 120 |
| Committed smoke | TestFloat, sqrt, and `pow_si` witnesses | 183 / 183 |
| TestFloat 3e level 2 | binary16, all declared operations/directions/tininess modes | 50,205,600 / 50,205,600 |

The level-2 binary16 result is additional streaming stress evidence, not a
claim for the much larger binary32/64/128 level-2 suites. The archives/files
and digests are pinned in
[`testdata/bin_float/corpora.json`](../../../testdata/bin_float/corpora.json).
The runner streams TestFloat level 2 in verified bounded chunks, but level 2
is an optional stress suite and is not included in the result claim above.

## Scope Of The Claim

## Stability Of The Evidence

The pinned matrix is the release evidence boundary; adding a new operation requires a new corpus contract and independent oracle.

The results cover contextual add, subtract, multiply, divide, and square root
for the four IEEE interchange formats and stated rounding/tininess modes.
They do not claim TestFloat conformance for fused multiply-add, remainder,
conversions, comparisons, min/max, total ordering, decimal formats, or every
IEEE 754 operation. The MPFR `pow_si` fixture independently covers values and
inexact for `pow_int_ctx`; nearest-away, before/after tininess, and complete
flags use the exact dyadic/rational oracle because MPFR explicitly forbids
using `MPFR_RNDNA` as a general `pow_si` rounding argument.

Run `just conformance smoke binary` for the checked-in gate and `just gate binary` for the full
pinned gate.
