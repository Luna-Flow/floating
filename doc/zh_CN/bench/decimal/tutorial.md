# `bench/decimal` 教程

## 快速开始

```sh
just bench decimal
```

## 读取结果

把 `MAREMARK_JSONL` 作为版本化原始 artifact，使用 `MAREMARK_HOTSPOT` 查看成对分层开销，使用 `MAREMARK_TUNE` / `MAREMARK_CROSSOVER` 查看确认后的调优决策。普通测试只编译计划并跳过计时。

## 延伸阅读

阅读 [API](./api.md) 查看生成接口，阅读 [设计](./design.md) 了解职责与不变量。

