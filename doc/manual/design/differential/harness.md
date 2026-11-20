# differential/harness design

## Design goal

The harness has behaviour worth testing (batch splitting, directive handling,
failure text), so it lives in a library package with white-box tests. The main
package `differential` keeps only the entry point: it calls `run` with
`@env.args()`. A main package that holds test inputs (`.mbt.md` files) is
deprecated by the toolchain: main packages will stop generating blackbox tests.

## Mathematical background

None of its own. A batch is valid when every row reproduces the expected value
and flags of its oracle (MPFR, libmpdec); the rounding and flag semantics are those
of the frontends it calls, and the statistics of the run are those of
mare_mark (see the [differential design page](../../design/differential.md)).

## Design decisions

### One public function

`run` is the only public item; the options, batches and the experiment
specification stay private to the package. The behaviour, the command line and
the record are those of the [`differential` design page](../../design/differential.md)
and are unchanged by the split.

## Correctness and invariants

- The exit status is `2` for a bad command line or corpus, `1` when a batch
  disagrees with its oracle, and `0` otherwise.
- It does not implement or alter arithmetic: every row goes through a frontend.

## Alternatives rejected

- **Keep `run` in the main package.** A main package that holds test inputs
  (`.mbt.md` files) is deprecated by the toolchain, and the batching tests would
  live in an executable.
- **Several public functions.** Options and batches are details of one command
  line; exposing them would promise a stability they do not have.

## Boundaries

- Native, JavaScript, Wasm and LLVM only (`moonbitlang/async`).
