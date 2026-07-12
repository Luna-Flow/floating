# `frontend/mpfr_expr` チュートリアル

同梱 fixture は共有 workflow で実行します。

```sh
just conformance smoke binary
```

直接利用では corpus 文法に対応する parser を選び、document を実行して `summary.success()` を確認します。parser diagnostic を unsupported arithmetic と解釈しません。
