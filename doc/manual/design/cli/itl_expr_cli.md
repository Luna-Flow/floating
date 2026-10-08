# cli/itl_expr_cli design

## Design goal

Expose [`frontend/itl_expr`](../frontend/itl_expr.md) as a process whose JSON
report lists every case by outcome, so the interval tooling can check a phase
claim ("all cases of these operations in these files are executable and
pass") from one invocation.

## Mathematical background

A phase is a pair (files $F$, operations $O$). The runner executes the set
$\{ c \in \operatorname{cases}(F) : O = \emptyset \vee \operatorname{op}(c) \in O \}$
and reports the partition of that set into passed, failed, unsupported and
diagnostic cases (see the [itl_expr design](../frontend/itl_expr.md)). The
strict verdict of a phase is "failed, diagnostic and unsupported are empty".

## Design decisions

### Its own small option parser

The runner does not use the shared `parse_common_options`: it has neither
sharding nor a text mode, because ITF1788 files are small and the tooling runs
phases in parallel instead. It parses
`--strict-supported`, repeatable `--operation` and paths itself, and rejects
every other option, so a mistyped option never silently changes a phase.

### JSON lists, not only counts

Besides counters the report lists `failedIds` with messages,
`unsupportedIds` and `diagnosticIds`. Interval failures are usually few and
need the exact case to reproduce; listing them makes the report
self-contained.

### Diagnostics always fail

The frontend's `success()` already fails on diagnostic cases; the runner adds
only the strict check on unsupported cases. Unreadable data in a pinned corpus
is never an acceptable exclusion. The frontend also classifies an unknown
operation with a non-interval operand as a diagnostic, so a phase that runs a
whole file without `--operation` (`sets`, `relations` and `reverse` in
`interpreter_stages.json`) would fail on a file containing such an
operation; the reverse operations take interval operands and are reported as
unsupported.

## Correctness and invariants

- Exit `0` implies no failed and no diagnostic case, and in strict mode no
  unsupported case.
- `totalCases = executableCases + unsupportedCases + diagnosticCases` and
  `executableCases = passedCases + failedCases`.
- The listed ids are exactly the cases in each class, in execution order.

## Alternatives rejected

- **Sharding.** Not needed for a corpus of a few thousand cases.
- **Directory expansion.** Phases name files explicitly
  (`interpreter_stages.json`), which keeps the claim precise.

## Boundaries

- Precision is fixed at the frontend default (53 bits).
- No reverse operations, string conversions or signals (frontend
  boundaries apply).
- No text output mode.
