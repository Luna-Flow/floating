# decimal conformance

## Contract split

`decimal` is the IEEE 754 arithmetic and interchange surface. General Decimal Arithmetic sticky status and traps belong to `decimal_gda`; passing the GDA corpus does not by itself establish the IEEE claim.

## Independent IEEE corpus

The committed IEEE corpus covers decimal32/64/128 DPD and BID interchange, canonical and non-canonical encodings, special values, flags, total order, and core arithmetic. The DPD fixture exhaustively checks all 1,024 declets.

## Oracle layers

Mandatory operation vectors use exact integer/rational construction and the documented DPD/BID bridge. Elementary families use independent high-precision or interval oracles when available. Values or encoded bits and IEEE flags are recorded independently so a numerically plausible result cannot hide a flag error.

The committed elementary layer contains 2,784 certified rows. MPFR 4.2.2
produces directed 768-bit dyadic endpoints; exact integer conversion rounds
both endpoints into decimal32/64/128 under every `DecimalRoundingMode`, and the
generator rejects a row unless result and flags are unique. Native, Wasm,
Wasm-GC, and JavaScript each pass 2,975/2,975 tests after these rows are
materialized; the full gate is 15,839/15,839. RDFP and Arb remain optional
secondary routes and are not counted when unavailable.

## Targets

`just gate decimal` runs native, Wasm, Wasm-GC, and JavaScript. LLVM is excluded because the required local artifacts are not part of the repository. Target-specific coefficient dispatch must not change value, encoding, or flags.

## Boundaries

The checked matrix is finite and does not claim every IEEE 754 operation, every payload propagation policy, or every possible decimal input. The supplementary `dd*`/`dq*` decTest rows are diagnostics, not an IEEE oracle.

The matrix passes on the current branch although the branch has the
deviations listed in
[decimal design: known deviations](../design/decimal.md#known-deviations)
(`inexact` or a certification failure for exact decimal results of
non-integral powers, no `division_by_zero` from $\ln 0$ and $\log_{10} 0$,
silently capped exponents in text, integral rounding of operands longer than
$p$ digits, BID NaN payloads, and the sign of a binary $-0$ in
`from_bin_float`; tracked in [#53](https://github.com/Luna-Flow/floating/issues/53),
[#94](https://github.com/Luna-Flow/floating/issues/94),
[#108](https://github.com/Luna-Flow/floating/issues/108),
[#118](https://github.com/Luna-Flow/floating/issues/118),
[#54](https://github.com/Luna-Flow/floating/issues/54) and
[#55](https://github.com/Luna-Flow/floating/issues/55)). Those cases are
therefore not covered by its rows, and passing the gate is evidence for the
covered rows only.

## Reproduction

```sh
just conformance smoke decimal
just gate decimal
just decimal-kernel-ci
```

See [the decimal data guide](../../../testdata/decimal/README.md) for corpus provenance, vector families, and failure records.
