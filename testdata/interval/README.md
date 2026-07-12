# IEEE 1788 test data

`smoke.itl` is the committed minimal suite. The complete corpus is fetched from
`nehmeier/ITF1788` at the revision and SHA-256 recorded in `corpora.json`.
The upstream corpus is Apache-2.0 licensed and remains ignored after download.

The staged runner treats supported operations strictly and reports all other
operations as unsupported. Phases that share an ITL file select disjoint
operations, so an unfiltered run evaluates every ITL instruction exactly once;
the runner rejects any overlapping configuration. The strict baseline also includes
arithmetic, numeric observations,
cancellation, elementary-core, exponentials/logarithms, FMA, integer powers,
and extrema. General power and trigonometric functions are included as strict
phases; reverse operations remain unsupported.

`just interval-ci` is the strict baseline (and accepts an optional worker count): 20 set cases, 567 relation cases,
124 numeric observation cases, 242 cancellation cases, 539 add/sub/mul/div
cases, 107 elementary-core cases, 131 exponential/logarithmic cases, 1,428
general-power cases, 176 trigonometric cases, 567 FMA cases, and 174
integer-power cases.
The extrema phase adds 38 min/max cases. Every selected case must be executable;
unsupported and diagnostic classifications fail the gate.

The `general-power` phase contains 1,428 `pow` cases and passes all cases on
the native strict run. The `trigonometric` phase contains 176 `sin`, `cos`, and
`tan` cases; it also passes the strict baseline. Reverse operations remain
unsupported.
