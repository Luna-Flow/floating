# `internal/runner_cli` 教程

## 快速开始

原生 conformance 命令 adapter 共享的副作用边界。

## 工作流

通过仓库 wrapper 运行本包，使依赖和 target 处理与 CI 一致：

```sh
sh tools/run_moon_clean_exec.sh test -p Luna-Flow/floating/internal/runner_cli --target native
```

把失败理解为仓库维护信号；本包不是独立的最终用户产品。

## 失败与范围

文件系统读取与渲染有意集中在这里，conformance model 和数值 frontend 保持纯。 不要把本包当作其所支撑数值包的替代入口。

## 继续阅读

完整生成接口见 [API](./api.md)，职责与取舍见[设计](./design.md)。
