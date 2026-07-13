# `cli/gda_expr_cli` チュートリアル

## クイックスタート

GDA `.decTest` 実行の filesystem/rendering adapter です。

## ワークフロー

dependency と target handling を CI と一致させるため、repository wrapper 経由で実行します。

```sh
sh tools/run_moon_clean_exec.sh run --release --target native src/cli -- --backend gda --help
```

failure は repository maintenance signal として扱います。この package は standalone end-user product ではありません。

## 失敗と範囲

file read、argument handling、JSON rendering、exit status を pure frontend から隔離します。 この package を、支援対象 numeric package の代替として import しないでください。

## 次に読む文書

完全な生成 interface は [API](./api.md)、責務と trade-off は[設計](./design.md)を参照してください。
