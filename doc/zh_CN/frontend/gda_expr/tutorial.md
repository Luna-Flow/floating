# `frontend/gda_expr` 教程

## 仓库流程

仓库内 fixture 使用 `just smoke`；修复 Decimal 语义时使用定向的 `just conformance run decimal --phase ... --cases ...`；PR 前运行快速 `just pr`，发布前运行完整 `just ci`。完整参数见[一致性测试数据](../../../../testdata/decimal/README.md)。

## 直接使用 CLI

```sh
sh tools/run_moon_clean_exec.sh run --release --target native src/cli -- \
  --backend gda --cases quax1010..quax1015 --json \
  testdata/decimal/official/quantize.decTest
```

直接 CLI 不执行 `moon check` 和 `moon info`。官方语料的 diagnostic 只对应 `#` 占位/非标量非法输入；合法 GDA 行全部执行并通过，任何 legacy/unsupported 都应视为回归。
