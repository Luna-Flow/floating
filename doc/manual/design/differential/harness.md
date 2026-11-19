# differential/harness design

## Design goal

The harness has behaviour worth testing (batch splitting, directive handling,
failure text), so it lives in a library package with white-box tests. The main
package `differential` keeps only the entry point: it calls `run` with
`@env.args()`. A main package that holds test inputs (`.mbt.md` files) is
deprecated by the toolchain: main packages will stop generating blackbox tests.

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

## Boundaries

- Native, JavaScript, Wasm and LLVM only (`moonbitlang/async`).
