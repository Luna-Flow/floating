# cli/dispatch tutorial

This tutorial calls the dispatcher of `floating-conformance` from MoonBit code
instead of starting the executable, and shows how a new backend would be added
behind it.

| I want to | Use |
| --- | --- |
| get the exit code of an invocation | [`@dispatch.dispatch`](#quick-start) |
| see which arguments reach a runner | [forwarding](#everyday-tasks) |
| run the executable itself | [the `cli` tutorial](../cli.md) |
| add a backend | [going further](#going-further) |

## Quick start

The package ships inside the tools module `Luna-Flow/floating-tools` (directory
`tooling/` of the repository); there is nothing to install. Run its tests from the
repository:

```bash
sh tools/run_moon_clean_exec.sh test tooling/src/cli/dispatch --target native
```

Call the dispatcher with the program name first, as in `@env.args()`:

```moonbit
///|
test "dispatcher rejects an empty backend value" {
  inspect(@dispatch.dispatch(["cli", "--backend="]), content="2")
}
```

`dispatch` prints a message and returns the exit code; it never exits the
process.

## Everyday tasks

### Choose the exit code you expect

`0` after `--help` (even after a valid `--backend`), `2` for a missing,
repeated, empty or unknown backend, and otherwise the runner's own code:

```moonbit
///|
test "the dispatcher scans left to right and stops at the first error" {
  inspect(@dispatch.dispatch(["cli", "--help"]), content="0")
  inspect(@dispatch.dispatch(["cli"]), content="2")
  inspect(@dispatch.dispatch(["cli", "--backend", "nope"]), content="2")
  inspect(@dispatch.dispatch(["cli", "--backend=gda", "--backend", "mpfr"]), content="2")
}
```

### Forward arguments to a runner

Everything except `--backend` and its value is forwarded, in order, with the
program name first, so a runner sees the same vector as when it is called
directly (see [`cli/gda_expr_cli`](gda_expr_cli.md) for the options of one
runner).

## Going further

To add a backend, write a runner package `run(arguments) -> Int32`, import it in
`moon.pkg` of this package and add one arm to the `match backend` of
`dispatch` and name the backend in `usage()`; keep process exit in `cli`, which stays an entry point only.

## Common pitfalls

- **Index 0 is skipped.** Pass a program name even when a test has none.
- **`--help` wins.** `["cli", "--backend", "gda", "--help"]` prints the usage
  line and returns `0` without running a runner.
- **Relative paths.** The `gda` and `itl` runners read their default corpora relative to the
  working directory; the tests of the module run in `tooling/`.

## Next steps

- [cli/dispatch API](../../api/cli/dispatch.md) for the exact contract.
- [cli/dispatch design](../../design/cli/dispatch.md) for why it is a library.
- [cli tutorial](../cli.md) for the executable.
