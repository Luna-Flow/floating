# `consistency` 教程

## 快速开始

用于跨包定律与公开面审计的 white-box 包。

## 工作流

通过仓库 wrapper 运行本包，使依赖和 target 处理与 CI 一致：

```sh
sh tools/run_moon_clean_exec.sh test -p Luna-Flow/floating/consistency --target native
```

把失败理解为仓库维护信号；本包不是独立的最终用户产品。

## 失败与范围

本包没有运行时 API 或 IO；失败通过测试断言指出合同不一致。 不要把本包当作其所支撑数值包的替代入口。

## 继续阅读

完整生成接口见 [API](./api.md)，职责与取舍见[设计](./design.md)。
