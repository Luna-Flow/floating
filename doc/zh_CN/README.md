# FLOATING

[![img](https://img.shields.io/badge/Maintainer-KCN--judu-violet)](https://github.com/KCN-judu) [![img](https://img.shields.io/badge/License-Apache%202.0-blue)](https://github.com/Luna-Flow/floating/blob/main/LICENSE) ![img](https://img.shields.io/badge/State-active-success)

## v0.2.0 - arithmetic capability integration 基线

本文档描述当前分支上的 **`v0.2.0`** 基线实现。

### 包定位

- **`def`**：提供 `Sign`、`PartialOrder`、窄化后的 `Floating` trait，以及 arithmetic 边界类型的兼容 reexport。
- **`bin_float`**：任意精度二进制浮点，采用 significand、二进制指数与工作精度表示。
- **`decimal`**：任意精度十进制浮点，采用 coefficient、十进制指数与工作精度表示。
- **`ball_float`**：基于 `bin_float` 的区间/球浮点，采用向外舍入的上下界表示。
- **`internal`**：共享的规范化、因子剥离、舍入与十进制解析辅助逻辑。
- **`consistency`**：覆盖规范化、算术、转换与跨包语义对齐的仓库测试。

### 当前版本特征

- 依赖 `Luna-Flow/arithmetic` 提供 checked capability boundary。
- `bin_float` 与 `decimal` 实现 checked scalar traits。
- `ball_float` 实现 enclosure relations 与 checked division / checked integer power。
- `decimal` 与 `bin_float` 支持双向转换。
- 本轮不会重新引入超越函数层、微积分、矩阵、复数或特殊函数。
- 仓库包含 correctness-first 的 whitebox 测试，覆盖 checked error path 与 enclosure 边界。

### 快速开始

```moonbit
let x = @bin_float.BinFloat::make(3N, -1, 32)
let y = @bin_float.BinFloat::make(5N, -1, 32)
let sum = x + y

let dec = @decimal.Decimal::from_string("12.34", precision=32).unwrap()
let as_bin = dec.to_bin_float(precision=32)
let ball = @ball_float.BallFloat::exact(as_bin)

inspect(sum.to_string(), content="1p2")
inspect(ball.contains(as_bin).to_string(), content="true")
```

### 文档

多语言文档：

- 🇺🇸 [README.md](../../README.md)
- 🇨🇳 [README.md](./README.md)
- 🇯🇵 [README.md](../ja_JP/README.md)

包文档入口：

- [文档标准](./doc_standard.md)
- [正确性审计台账](./correctness_audit.md)
- [@def API](./def/api.md)
- [@bin_float API](./bin_float/api.md)
- [@decimal API](./decimal/api.md)
- [@ball_float API](./ball_float/api.md)

## 开发

常用命令：

```bash
moon fmt
moon check
moon test
moon test --enable-coverage
```

## 发布清单

1. 先更新 `moon.mod` 中的目标版本号。
2. 更新 `README.md` 与多语言文档，确保内容和当前实现一致。
3. 运行 `moon check` 与 `moon test`。
4. 触发 `publish-package` workflow。

贡献说明见 [CONTRIBUTING.md](../../CONTRIBUTING.md)。
