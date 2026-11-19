# cli/dispatch design

## Design goal

The dispatcher has behaviour worth testing (argument scanning, the at-most-once
rule, the empty value, `--help`), so it lives in a library package. The main
package `cli` keeps only the process boundary: it reads `@env.args()` and calls
`@sys.exit` with the returned code. A main package that holds test inputs
(`.mbt.md` files) is deprecated by the toolchain: main packages will stop
generating blackbox tests.

## Design decisions

### Return the exit code

`dispatch` returns an `Int32` and never calls `@sys.exit`, so a white-box test
checks an invocation without spawning a process. The semantics of the options
are those of the `cli` page and are unchanged by the split.

### Runners stay libraries

The four runners (`cli/gda_expr_cli` and its siblings) are imported here and
nowhere else; `cli` itself imports only this package and the process helpers.

## Correctness and invariants

- Exactly one runner is called per invocation, or none for invalid arguments
  or `--help`.
- The result equals the runner's return value, or `2` for an argument error,
  or `0` for `--help`.

## Boundaries

- No process exit, no file access of its own: those are in the runners and in
  `cli`.
