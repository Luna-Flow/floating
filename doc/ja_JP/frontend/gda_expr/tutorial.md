# `frontend/gda_expr` チュートリアル

## リポジトリ手順

追跡済み fixture には `just conformance smoke decimal_gda`、Decimal 意味論の修正には `just conformance run decimal_gda --phase ... --cases ...`、PR 前には高速な `just pr`、公開前には完全な `just ci` を使います。詳細は[適合性データ手順](../../../../testdata/decimal/README.md)を参照してください。

## CLI を直接使う

```sh
sh tools/run_moon_clean_exec.sh run --release --target native src/cli -- \
  --backend gda --cases quax1010..quax1015 --json \
  testdata/decimal/official/quantize.decTest
```

直接実行は `moon check` と `moon info` を省略します。公式 corpus の diagnostic は `#` placeholder/non-scalar の不正入力だけです。合法な GDA 行はすべて実行・通過し、legacy/unsupported は regression として扱います。
