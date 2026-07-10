# `gda_expr` 教程

## 仓库流程

仓库内 fixture 使用 `just smoke`；修复 Decimal 语义时使用定向的 `just pr phase=... --cases ...`；提交前运行完整 `just pr`。完整参数见[一致性测试数据](../../../testdata/decimal/README.md)。

## 直接使用 CLI

```sh
sh tools/run_moon_clean_exec.sh run --release --target native src/gda_expr_cli -- \
  --cases quax1010..quax1015 --json \
  testdata/decimal/official/quantize.decTest
```

直接 CLI 不执行 `moon check` 和 `moon info`。非 strict 模式会单独统计 diagnostic、legacy 与 unsupported，不把它们误报为数值结果错误。
