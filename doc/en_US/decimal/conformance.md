# `decimal` Conformance

## Contract Split

`decimal` is the IEEE 754 arithmetic and interchange surface. General Decimal Arithmetic sticky status and traps belong to `decimal_gda`; passing the GDA corpus does not by itself establish the IEEE claim.

## Independent IEEE Corpus

The committed IEEE corpus covers decimal32/64/128 DPD and BID interchange, canonical and non-canonical encodings, special values, flags, total order, and core arithmetic. The DPD fixture exhaustively checks all 1,024 declets.

## Oracle Layers

Mandatory operation vectors use exact integer/rational construction and the documented DPD/BID bridge. Elementary families use independent high-precision or interval oracles when available. Values or encoded bits and IEEE flags are recorded independently so a numerically plausible result cannot hide a flag error.

## Targets

`just gate decimal` runs native, Wasm, Wasm-GC, and JavaScript. LLVM is excluded because the required local artifacts are not part of the repository. Target-specific coefficient dispatch must not change value, encoding, or flags.

## Boundaries

The checked matrix is finite and does not claim every IEEE 754 operation, every payload propagation policy, or every possible decimal input. The supplementary `dd*`/`dq*` decTest rows are diagnostics, not an IEEE oracle.

## Reproduction

```sh
just conformance smoke decimal
just gate decimal
just decimal-kernel-ci
```

See [the decimal data guide](../../../testdata/decimal/README.md) for corpus provenance, vector families, and failure records.
