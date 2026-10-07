# `decimal_gda` Conformance

The implementation target is General Decimal Arithmetic Specification 1.70;
the pinned executable corpus is the General Decimal Arithmetic testcase suite
2.62.

## Published Result

The pinned official corpus passes 64,986/64,986 legal executable scalar rows with zero failed, unsupported, or legacy rows. The remaining 141 rows are `#` placeholder or non-scalar invalid inputs and are reported as diagnostics outside the legal denominator.

## Legacy Corpus

The pinned `official0` corpus passes 16,124/16,124 legal executable rows with zero failures. It is retained for historical compatibility checks, not as the definition of the current surface.

## State Semantics

Each operation returns a `GdaOutcome` containing the defined result, flags raised by that operation, and the next context with accumulated sticky status. Enabling a trap changes the outcome variant but does not erase the defined result.

## Runner Model

Documents are parsed once, directive state is snapshotted per case, and
deterministic shards execute disjoint case positions through the public
`GdaContext`/`GdaOutcome` operation surface. Executable, diagnostic,
unsupported, legacy, passed, and failed counts remain separate.

## Boundaries

The claim covers legal scalar rows in the pinned corpora. Placeholder/non-scalar invalid rows, future directives, unpinned revisions, and an unbounded universe of decimal strings remain outside it.

## Isolation And Native Benchmark

Production dependency scans require `decimal_gda`, `decimal_gda_checked`, and
`frontend/gda_expr` to contain no IEEE `decimal` import or GDA profile bridge.
IEEE tests and its independent conformance corpus are run separately.

The quick benchmark builds only the current engine in an isolated snapshot and
runs three native samples per cell. It reports arithmetic, parser, context, and
elementary timing observations without treating performance as a conformance
requirement or comparing against a historical adapter.

## Reproduction

```sh
just conformance smoke decimal_gda
just gate decimal_gda 8
just conformance run decimal_gda --corpus official0 --strict-supported
python3 tools/run_gda_benchmark.py
```

See [the decimal data guide](../../../testdata/decimal/README.md) for manifests, filters, phases, JSON output, and failure triage.
