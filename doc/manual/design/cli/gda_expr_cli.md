# gda_expr_cli design

## Design goal

Provide a thin, scriptable process interface to
[`frontend/gda_expr`](../frontend/gda_expr.md): read files, pass options
through, print counters that the Python tooling can add up across shards, and
encode the verdict in the exit status.

## Mathematical background

The run is the composition
$\text{files} \xrightarrow{\text{sort}} \text{documents}
\xrightarrow{\text{filter, shard}} \text{rows}
\xrightarrow{\text{execute}} \text{summary}$. Row selection and the
additivity of counters over shards are proved in the
[gda_expr design](../frontend/gda_expr.md) and the
[internal/conformance design](../internal/conformance.md); this runner adds
only the deterministic file order that makes row ordinals well defined.

## Design decisions

### All files form one run

Sharding is applied to the concatenated, filtered rows of all files, not per
file. The tooling can therefore give every shard the same list of files and
get balanced shards even when one file dominates the corpus.

### Strictness at the process boundary

`--strict-supported` is evaluated here: the exit status is `1` when the
summary has failed rows, or, in strict mode, any legacy or unsupported row.
The frontend summary itself stays neutral, so in-process callers can apply
their own policy.

### Stable JSON keys

The JSON object uses fixed camelCase keys and puts execution counters in a
nested `execution` object together with the shard, matching what
`tools/run_dectest_interpreter.py` aggregates. `supportedCases` is the number
of executable rows.

### Stop at the first parse error

Corpora are pinned and expected to parse completely; a parse error is an
infrastructure failure (exit `2`), reported with its location, not a test
result.

## Correctness / invariants

- Exit `0` implies `failed_cases() == 0`, and in strict mode also no legacy or
  unsupported row.
- For a fixed argument vector and file contents the output is deterministic.
- `totalCases` is the same in every shard of one run, so the aggregate total
  is the common value, not the sum.

## Alternatives rejected

- **Per-file shards.** Uneven: one large file would bound the wall time.
- **Reporting every parse diagnostic.** Useful while editing a corpus, but
  the runner targets pinned corpora; the frontend API returns all diagnostics
  for tools that need them.

## Boundaries

- No corpus download or phase planning (Python tooling).
- No recursion into subdirectories.
- Only GDA `.decTest` semantics through `decimal_gda`; IEEE decimal vectors use
  a different runner.
