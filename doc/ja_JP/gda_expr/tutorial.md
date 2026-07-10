# `gda_expr` チュートリアル

## リポジトリ手順

追跡済み fixture には `just smoke`、Decimal 意味論の修正には `just pr phase=... --cases ...`、PR 前には完全な `just pr` を使います。詳細は[適合性データ手順](../../../testdata/decimal/README.md)を参照してください。

## CLI を直接使う

```sh
sh tools/run_moon_clean_exec.sh run --release --target native src/gda_expr_cli -- \
  --cases quax1010..quax1015 --json \
  testdata/decimal/official/quantize.decTest
```

直接実行は `moon check` と `moon info` を省略します。非 strict モードでは diagnostic、legacy、unsupported を数値不一致と分けて集計します。
