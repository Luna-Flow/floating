# `frontend/mpfr_expr` Tutorial

Run the committed binary fixture through the shared workflow:

```sh
just conformance smoke binary
```

For direct library use, select the parser matching the corpus grammar, execute
the returned document, and require `summary.success()`. Do not auto-reinterpret
parser diagnostics as unsupported arithmetic.
