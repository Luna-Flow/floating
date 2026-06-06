# FLOATING

[![img](https://img.shields.io/badge/Maintainer-KCN--judu-violet)](https://github.com/KCN-judu) [![img](https://img.shields.io/badge/License-MIT-blue)](https://github.com/Luna-Flow/floating/blob/main/LICENSE) ![img](https://img.shields.io/badge/State-active-success)

## v0.1.0 - 初始包基线

本文档描述当前分支上的 **`v0.1.0`** 基线实现。

### 包定位

- **`def`**：共享的浮点分类、舍入模式与核心 `Floating` trait。
- **`bin_float`**：任意精度二进制浮点，采用 significand、二进制指数与工作精度表示。
- **`decimal`**：任意精度十进制浮点，采用 coefficient、十进制指数与工作精度表示。
- **`ball_float`**：基于 `bin_float` 的球浮点，语义是 `center +/- radius`。
- **`internal`**：共享的规范化、因子剥离、舍入与十进制解析辅助逻辑。
- **`consistency`**：覆盖规范化、算术、转换与跨包语义对齐的仓库测试。

### 当前版本特征

- 提供最小但稳定的 `Floating` trait 基线。
- `bin_float` 与 `decimal` 都支持构造、规范化、精度调整、基础四则与特殊值。
- `ball_float` 支持精确嵌入、包含、重叠、分离判断与基础球算术。
- `decimal` 与 `bin_float` 支持双向转换。
- 仓库包含 correctness-first 的 whitebox 测试。

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
