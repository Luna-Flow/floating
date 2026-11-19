# differential/harness tutorial

The harness is run through the `just random-diff` tooling; this page only
says where its code lives.

| I want to | Use |
| --- | --- |
| run a campaign | [the `differential` tutorial](../differential.md) |
| change the batching or the record | `tooling/src/differential/harness` |

## Where the code is

The files `batch.mbt` (corpus splitting and batch execution) and
`harness.mbt` (options, experiment specification and `run`) live in
`tooling/src/differential/harness`, with their white-box tests in
`differential_wbtest.mbt`. Test them with:

```bash
moon test tooling/src/differential/harness --target native
```

## Common pitfalls

- **No wasm-gc build.** `moonbitlang/async` has no wasm-gc runtime, so the
  package declares `supported_targets = "all-wasm-gc"`.

## Next steps

- [differential/harness API](../../api/differential/harness.md).
- [differential tutorial](../differential.md) for the workflow.
