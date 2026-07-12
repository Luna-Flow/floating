# `frontend/itl_expr` API

`parse_itl(text)` は `ItlCase` または diagnostic、`execute_case(case, precision?)` は `ItlResult`、`summarize_results` は件数と各行を返します。`ItlDisposition` で executable/unsupported/diagnostic を区別します。

現在の parser/executor が実装する operation と期待値形式だけを受け入れ、strict subset は `testdata/interval/README.md` に定義します。
