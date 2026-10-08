# internal/runner_cli design

## Design goal

The conformance runners are invoked thousands of times by `tools/*.py`, in
parallel shards, and their output is parsed by scripts. They must therefore
agree on option syntax, exit codes, diagnostic format and JSON shape, and
produce the same output for the same input on any machine.
`internal/runner_cli` is the single place where these conventions are
implemented, so each runner in `cli/` only adds its own options and calls a
frontend.

## Mathematical background

There is little mathematics here; the one property that matters is
determinism. A run is a function of (argument vector, file contents): the
file list is sorted, documents are parsed in that order, cases are numbered in
that order, and shard $(n, i)$ selects ordinals $k$ with $k \bmod n = i$
([internal/conformance design](conformance.md)). Hence the set of executed
cases, and every counter in the output, is independent of directory listing
order and of how many processes run in parallel.

## Design decisions

### Full argument vectors

Every runner receives the whole argument vector, program name included, and
`parse_common_options` skips element 0. The dispatcher in `cli/` forwards the
program name followed by the arguments it did not consume, so a runner behaves
the same whether it is reached through the dispatcher or called directly from
a test.

### Common options first, the rest in order

`parse_common_options` consumes only `--json` and the shard options and keeps
everything else in order. Runner-specific options and paths are parsed
afterwards from `remaining()`. This keeps the common syntax identical across
runners while letting each runner reject options it does not know.

### Validated shards

Shard options are validated with `ShardSpec::try_new`, so an invalid pair is a
usage error (exit code 2) instead of an abort in a frontend.

### Sorted, non-recursive file collection

`collect_files` sorts the expanded list and does not descend into
subdirectories. Sorting makes case ordinals, and thus shards, reproducible.
Not recursing keeps the selected corpus explicit: the Python tooling passes
the exact files of each corpus phase.

### Small JSON layer

The helpers wrap the core `Json` type: `json_int` stores the exact decimal
representation so counts print as integers, and `json_object` keeps insertion
order so reports are stable and diff-friendly.

## Correctness and invariants

- **Option round trip.** For an argument vector without common options,
  `remaining()` equals `arguments[1:]`.
- **Shard validity.** A successful `parse_common_options` always returns
  `shard_count() > 0` and `0 <= shard_index() < shard_count()`.
- **Deterministic file list.** `collect_files(paths, s)` is sorted and
  contains exactly the existing non-directory paths named in `paths` that end
  in `s`, plus the direct entries of named directories whose names end in `s`
  (entries are not checked to be files). Duplicates are kept, so the list is a
  function of the argument vector and the directory contents, not of the
  listing order.
- **Diagnostic positions.** `format_diagnostic_at` never prints a line or
  column below 1.

## Alternatives rejected

- **A generic argument-parsing library.** The runners need four options; a
  dependency would add more surface than it removes.
- **Recursive directory walks.** They would pull in unrelated files placed in
  subdirectories and make the selected corpus implicit.
- **Free-form text output for tools.** Scripts would have to parse prose; the
  JSON objects are the stable interface, text output is for humans.

## Boundaries

- No corpus parsing or numeric semantics: frontends own them.
- No process exit: runners return an exit code; only `cli` calls `exit`.
- No recursive file search, globbing or encoding detection.
- Internal: not importable outside `Luna-Flow/floating`, no stability promise.
