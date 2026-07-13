# `bin_float_bench` チュートリアル

## クイックスタート

代表的な `BinCoeff` 操作を測定する benchmark 専用 package です。

## ワークフロー

dependency と target handling を CI と一致させるため、repository wrapper 経由で実行します。

```sh
sh tools/run_moon_clean_exec.sh test src/bin_float_bench --target native
```

failure は repository maintenance signal として扱います。この package は standalone end-user product ではありません。

## 失敗と範囲

skip された benchmark test は local allocation と計時だけを行い、application IO は実行しません。 この package を、支援対象 numeric package の代替として import しないでください。

## 次に読む文書

完全な生成 interface は [API](./api.md)、責務と trade-off は[設計](./design.md)を参照してください。
