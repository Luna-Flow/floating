# `bin_float_bench` 教程

## 快速开始

用于测量代表性 `BinCoeff` 操作的专用 benchmark 包。

## 工作流

通过仓库 wrapper 运行本包，使依赖和 target 处理与 CI 一致：

```sh
sh tools/run_moon_clean_exec.sh test src/bin_float_bench --target native
```

把失败理解为仓库维护信号；本包不是独立的最终用户产品。

## 失败与范围

被跳过的 benchmark 测试只在本地分配和计时，不执行应用 IO。 不要把本包当作其所支撑数值包的替代入口。

## 继续阅读

完整生成接口见 [API](./api.md)，职责与取舍见[设计](./design.md)。
