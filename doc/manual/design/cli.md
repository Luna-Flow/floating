# cli design

## Design goal

Conformance runs are driven by Python tooling that starts many native
processes in parallel. One executable with a `--backend` switch keeps the
build simple (one MoonBit package, one link step) while each backend keeps its
own option syntax. The dispatcher's job is only to choose a runner and turn its
return value into the process exit status.

## Mathematical background

None beyond the runners'. The only contract is functional: the exit status is
the runner's return value, and the runner's output depends only on its
arguments and the files it reads (see
[internal/runner_cli design](internal/runner_cli.md)).

## Design decisions

### Three layers

Parsing and execution of corpora live in pure `frontend/*` packages; argument
handling, file access and output live in `cli/*_expr_cli` runners, each a
library with `run(arguments) -> Int`; the process boundary (`@env.args()`,
`@sys.exit`) lives only in `cli`. Because runners are libraries, their usage
paths are unit-testable without spawning processes, and the frontends stay
usable on every target.

### Forward the program name

The dispatcher removes `--backend` and its value and forwards
`[program, rest…]`. Every runner skips element 0, so a runner behaves the
same when called from the dispatcher, from a test, or (in principle) as its
own executable.

### One binary, copied per backend

`tools/conformance_cli.py` builds `src/cli` into a backend-specific target
directory and copies it to `<backend>-conformance.exe`. Parallel builds for
different backends therefore never share a `_build` directory or lock, and
tools always invoke an executable whose name says what it runs.

### Dispatcher help wins

`--help` is handled while scanning arguments, before the backend is known, so
it prints the dispatcher usage and exits with `0` whatever backend is named.
The scan stops at the first error, so a malformed `--backend` before `--help`
still exits with `2`. Runner options are documented on their pages instead.

## Correctness and invariants

- Exactly one runner is called per invocation, or none when the arguments are
  invalid (exit `2`) or `--help` is given (exit `0`).
- The exit status equals the runner's return value: `0`, `1` or `2`.
- Arguments other than `--backend`, its value and `--help`/`-h` reach the
  runner unchanged and in order.
- "At most once" is checked on the stored value: an empty `--backend=` leaves
  it empty, so a later `--backend NAME` is still accepted.

## Alternatives rejected

- **Four executables.** Four packages with identical `main` functions and four
  link steps for no behavioural gain.
- **Subcommands (`floating-conformance gda …`).** A positional backend would
  collide with runner paths; an explicit option is unambiguous.
- **Exit codes from runners.** Calling `exit` inside a runner would make it
  untestable as a library.

## Boundaries

- Native target only (file access through `moonbitlang/x/fs`, exit through
  `moonbitlang/x/sys`).
- No corpus download, planning, parallelism or aggregation: those are in
  `tools/conformance.py` and the `tools/run_*_interpreter.py` scripts.
- No public MoonBit API.
