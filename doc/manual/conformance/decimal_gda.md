# decimal_gda conformance

The implementation target is General Decimal Arithmetic Specification 1.70;
the pinned executable corpus is the General Decimal Arithmetic testcase suite
2.62.

## Published result

The pinned official corpus passes 64,986/64,986 legal executable scalar rows with zero failed, unsupported, or legacy rows. The remaining 141 rows are `#` placeholder or non-scalar invalid inputs and are reported as diagnostics outside the legal denominator.

## Legacy corpus

The pinned `official0` corpus passes 16,124/16,124 legal executable rows with zero failures. It is retained for historical compatibility checks, not as the definition of the current surface.

## State semantics

Each operation returns a `GdaOutcome` containing the defined result, flags raised by that operation, and the next context with accumulated sticky status. Enabling a trap changes the outcome variant but does not erase the defined result.

## Runner model

Documents are parsed once, directive state is snapshotted per case, and
deterministic shards execute disjoint case positions through the public
`GdaContext`/`GdaOutcome` operation surface. Executable, diagnostic,
unsupported, legacy, passed, and failed counts remain separate.

## Boundaries

The claim covers legal scalar rows in the pinned corpora. Placeholder/non-scalar invalid rows, future directives, unpinned revisions, and an unbounded universe of decimal strings remain outside it.

## Known deviations outside the corpus

A passing corpus is a finite claim. Review of the implementation found these
behaviours, none of which has a pinned row:

- `divide` can misround in the half modes when its first, scaled rounding
  manufactures a tie; at precision 1, `1/2222` gives `0.0004` instead of
  `0.0005` ([design](../design/decimal_gda.md#division)).
- `to_integral_exact` and `to_integral_value` round an integer longer than
  the precision (`12345` at precision 3 becomes `1.23E+4`) and return NaN with
  `InvalidOperation` when the integral part of a fractional operand is longer
  than the precision (`12345.6` at precision 3), where the reference
  implementation returns `12345` and `12346`
  ([API](../api/decimal_gda.md#to_integral_exact-to_integral_value)).
- A non-integer `power` with an exactly representable value, such as
  $4^{1.5}$, does not finish in reasonable time in the directed rounding
  modes ([API](../api/decimal_gda.md#power)).
- Integer `power` is accurate to about 0.55 units in the last place (0.6 for
  negative exponents), not correctly rounded, as the specification allows.

## Isolation and native benchmark

Production dependency scans require `decimal_gda`, `decimal_gda_checked`, and
`frontend/gda_expr` to contain no IEEE `decimal` import or GDA profile bridge.
IEEE tests and its independent conformance corpus are run separately.

The quick benchmark builds only the current engine in an isolated snapshot and
runs three native samples per cell. It reports arithmetic, parser, context, and
elementary timing observations without treating performance as a conformance
requirement or comparing against a historical adapter.

## Reproduction

```bash
just conformance smoke decimal_gda
just gate decimal_gda 8
just conformance run decimal_gda --corpus official0 --strict-supported
python3 tools/run_gda_benchmark.py
```

See [the decimal data guide](../../../testdata/decimal/README.md) for manifests, filters, phases, JSON output, and failure triage.
