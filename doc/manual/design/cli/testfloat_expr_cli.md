# testfloat_expr_cli design

## Design goal

Execute one TestFloat vector file per process with the exact configuration it
was generated under, so the tooling can stream hundreds of millions of vectors
through bounded files and parallel processes.

## Mathematical background

A TestFloat task is a tuple (format, operation, rounding, tininess,
exactness, level, seed). Its vectors are checked by the pass rule of the
[testfloat_expr design](../frontend/testfloat_expr.md). Splitting a task's
vector stream into chunks $V_1, V_2, \dots$ and each chunk into shards is a
partition of the vectors, and every vector's verdict is independent of the
others, so the task's counters are the sums over chunks and shards.

## Design decisions

### Configuration as options, vectors untouched

The function, rounding, tininess and exactness are command-line options that
mirror `testfloat_gen`'s own flags. Vector files stay exactly in TestFloat's
format, so the generator's output can be piped to a file and executed without
conversion.

### One file per invocation

A process handles one chunk. The Python driver
(`tools/run_binfloat_interpreter.py`) writes the generator stream into chunk
files, runs the runner on each, and adds the chunk offset to the reported
`FUNCTION:LINE` ids. Bounded chunks keep memory constant for the largest
`mulAdd` tasks.

### Shared options for JSON and shards

`--json` and the shard options come from
[internal/runner_cli](../internal/runner_cli.md), so they behave exactly as in
the GDA runner.

## Correctness / invariants

- Exit `0` iff no selected vector failed;
  `selectedCases = passedCases + failedCases`.
- A specification error (`TestFloatSpec::parse`) or parse error exits with `2`
  before any vector is executed.

## Alternatives rejected

- **Encoding the configuration in the vector file.** It would require
  rewriting TestFloat output.
- **Running `testfloat_gen` from MoonBit.** Process management belongs in the
  tooling; the runner stays portable and testable.

## Boundaries

- No vector generation, chunking or id remapping (Python tooling).
- Formats and operations are those of `frontend/testfloat_expr`.
