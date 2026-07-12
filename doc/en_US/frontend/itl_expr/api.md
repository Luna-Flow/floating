# `frontend/itl_expr` API

`parse_itl(text)` returns typed `ItlCase` values or diagnostics.
`execute_case(case, precision?)` returns an `ItlResult`; `summarize_results`
folds results into counts and retains individual rows. Callers inspect
`ItlDisposition` to distinguish executable, unsupported, and diagnostic cases.

The package accepts only the operations and expected-value forms implemented by
the current parser/executor. Consult `testdata/interval/README.md` for the strict
conformance subset.
