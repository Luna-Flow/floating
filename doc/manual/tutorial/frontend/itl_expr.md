# `frontend/itl_expr` Tutorial

Use the repository smoke gate for an end-to-end check:

```sh
just conformance smoke interval
```

Library callers parse text, iterate cases through `execute_case`, then call
`summarize_results`. Treat `Unsupported` separately from executable failures;
enable strict behavior at the CLI/tooling layer when unsupported rows must fail.
