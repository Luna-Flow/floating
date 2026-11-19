# cli/dispatch tutorial

This tutorial calls the dispatcher of `floating-conformance` from MoonBit code
instead of starting the executable.

| I want to | Use |
| --- | --- |
| get the exit code of an invocation | [`@dispatch.dispatch`](#call-the-dispatcher) |
| run the executable itself | [the `cli` tutorial](../cli.md) |

## Call the dispatcher

The first element is the program name, as in `@env.args()`:

```moonbit nocheck
test "dispatcher rejects an empty backend value" {
  assert_eq(@dispatch.dispatch(["cli", "--backend="]), 2)
}
```

## Common pitfalls

- **Index 0 is skipped.** Pass a program name even when a test has none.
- **`--help` wins.** `["cli", "--backend", "gda", "--help"]` prints the usage
  line and returns `0` without running a runner.

## Next steps

- [cli/dispatch API](../../api/cli/dispatch.md) for the exact contract.
- [cli tutorial](../cli.md) for the executable.
