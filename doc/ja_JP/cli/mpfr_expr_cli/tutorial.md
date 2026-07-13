# `cli/mpfr_expr_cli` チュートリアル

## クイックスタート

二つの固定 MPFR witness grammar 用 command adapter です。

## ワークフロー

dependency と target handling を CI と一致させるため、repository wrapper 経由で実行します。

```sh
sh tools/run_moon_clean_exec.sh run --release --target native src/cli -- --backend mpfr --help
```

failure は repository maintenance signal として扱います。この package は standalone end-user product ではありません。

## 失敗と範囲

file read と rendering が effect で、MPFR format parse と binary comparison は `frontend/mpfr_expr` に残ります。 この package を、支援対象 numeric package の代替として import しないでください。

## 次に読む文書

完全な生成 interface は [API](./api.md)、責務と trade-off は[設計](./design.md)を参照してください。
