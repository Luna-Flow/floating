# `cli/mpfr_expr_cli` 教程

## 快速开始

两种固定 MPFR witness 语法的命令 adapter。

## 工作流

通过仓库 wrapper 运行本包，使依赖和 target 处理与 CI 一致：

```sh
sh tools/run_moon_clean_exec.sh run --release --target native src/cli -- --backend mpfr --help
```

把失败理解为仓库维护信号；本包不是独立的最终用户产品。

## 失败与范围

文件读取和输出是副作用；MPFR 格式解析与二进制比较留在 `frontend/mpfr_expr`。 不要把本包当作其所支撑数值包的替代入口。

## 继续阅读

完整生成接口见 [API](./api.md)，职责与取舍见[设计](./design.md)。
