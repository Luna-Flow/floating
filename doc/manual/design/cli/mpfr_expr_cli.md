# cli/mpfr_expr_cli design

## Design goal

Run one MPFR reference file through
[`frontend/mpfr_expr`](../frontend/mpfr_expr.md) with a single command, so
that the binary conformance tooling can add MPFR evidence next to the
TestFloat matrix without knowing the three file formats.

## Mathematical background

Each row asserts $\hat y = \circ_{p,\rho}(f(x))$ (and flags), as described in
the [mpfr_expr design](../frontend/mpfr_expr.md). The runner adds nothing to
the semantics; its summary is the frontend summary of the whole file.

## Design decisions

### Format detection from content

The formats have no common header, so the runner looks for a marker: the
elementary generator writes `mpfr-elementary-v1`, the power data has a header
naming `input_coefficient_hex`, and MPFR's own `tests/data/sqrt` has neither.
Content-based detection lets the pinned upstream file be used unchanged.

### No shards

MPFR files have at most a few thousand rows; `parse_common_options` is called
with `allow_shard=false` so that shard options are rejected instead of being
silently ignored.

### Corpus names in JSON

The JSON `corpus` field names the detected format and the MPFR release the
data was produced with, so aggregated reports state their evidence source.

## Correctness and invariants

- Exactly one parser runs per invocation, determined by the file content.
- Exit `0` iff every row passed; `totalCases = passedCases + failedCases`.
- Parse errors exit with `2` before any row is executed.
- The one exception to "every outcome is an exit code" is the frontend's
  abort on an elementary `pow`, `hypot` or `atan2` row without a second
  operand.

## Alternatives rejected

- **A `--format` option.** Redundant with the markers already present in the
  data and a source of mismatches.
- **Accepting several files.** The formats differ per file; one file per
  process keeps the report unambiguous.

## Boundaries

- No sharding, no filtering of rows.
- Only the three formats of `frontend/mpfr_expr`.
