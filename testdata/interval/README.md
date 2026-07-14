# IEEE 1788 test data

The user-facing finite claim is summarized in
[`doc/en_US/ball_float/conformance.md`](../../doc/en_US/ball_float/conformance.md);
this page owns the pinned corpus, phase planner, and operational workflow.

`smoke.itl` is the committed minimal suite. The complete corpus is fetched from
`nehmeier/ITF1788` at the revision and SHA-256 recorded in `corpora.json`.
The upstream corpus is Apache-2.0 licensed and remains ignored after download.

## Commands

```sh
just conformance smoke interval
just conformance fetch interval itf1788
just conformance plan interval --phase sets --phase relations
just conformance run interval --phase sets --phase relations --strict-supported
just gate interval 8
```

`smoke` never downloads data. `fetch` verifies the manifest before installing the
ignored corpus. `plan` prints the selected phase/task partition. `run` executes
the selected phases. `--strict-supported` makes unsupported or diagnostic cases
fail the command rather than merely reporting them.

The staged runner treats supported operations strictly and reports all other
operations as unsupported. Phases that share an ITL file select disjoint
operations, so an unfiltered run evaluates every ITL instruction exactly once;
the runner rejects any overlapping configuration. The strict baseline also includes
arithmetic, numeric observations,
cancellation, elementary-core, exponentials/logarithms, FMA, integer powers,
and extrema. General power and trigonometric functions are included as strict
phases; reverse operations remain unsupported.

`just gate interval` is the strict baseline (and accepts an optional worker count): 20 set cases, 567 relation cases,
124 numeric observation cases, 242 cancellation cases, 539 add/sub/mul/div
cases, 107 elementary-core cases, 131 exponential/logarithmic cases, 1,428
general-power cases, 176 trigonometric cases, 567 FMA cases, and 174
integer-power cases.
The extrema phase adds 38 min/max cases. Every selected case must be executable;
unsupported and diagnostic classifications fail the gate.

The phase planner is part of the contract. A phase declares its operation set,
input files, and strictness; the runner rejects overlapping operation sets and
does not silently execute a case twice. This keeps per-phase counts additive and
makes sharded summaries comparable with an unfiltered run.

The `general-power` phase contains 1,428 `pow` cases and passes all cases on
the native strict run. The `trigonometric` phase contains 176 `sin`, `cos`, and
`tan` cases; it also passes the strict baseline. Reverse operations remain
unsupported.

## Interpreting Results

An executable failure means the parsed operation was in the declared support
set but the enclosure, relation, or status did not match the expected row. An
unsupported result means the grammar was understood but the implementation has
not claimed that operation. A diagnostic result means the row itself could not
be treated as a valid scalar ITL case. These categories must not be merged when
reporting a conformance claim.

The ITL backend compares interval behavior through set relations and certified
containment, not scalar string equality. A wider interval can be valid when the
operation contract permits a conservative fallback; strict phase support still
requires every selected row to execute.

## Provenance And Scope

The manifest records the upstream revision and checksum. The published strict
claim covers only the listed phases and endpoint precision used by the runner.
It does not claim reverse interval operations, every IEEE 1788 decoration rule,
arbitrary endpoint formats, or unpinned upstream revisions.

For a failure, record the ITL file, case ID, phase, operation, endpoint values,
expected relation, actual relation, target, and manifest revision before changing
the support table or fixture.
