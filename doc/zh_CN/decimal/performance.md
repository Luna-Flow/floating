# `decimal` 性能

## 测量边界

`just bench decimal --target native` 运行 `src/bench/decimal` 中当前的
Maremark suite，并写入 `.tmp/bench/decimal.jsonl` 及其 analysis 文件。这是可复现的
测量 artifact，不是不可变的 release gate。0.7.1 没有 checked-in 的 decimal 性能
manifest 或 threshold 流程；当前指令使用下面的 Maremark suite。

## 工作负载

suite 在 9、34、128、512 位十进制数字上测量 add、multiply、divide。每个 cell 将
coefficient kernel、核心 `Decimal` 路径和完整 checked 路径与精确 `BigInt` reference
比较。输入构造和期望值构造不计入 timed payload。

## 读取结果

`MAREMARK_JSONL` 是带版本的原始事件流，`MAREMARK_HOTSPOT` 是成对的分层开销分析。
结果只描述当前 tree、toolchain 和 target，可用于定位 hotspot，但不能证明通用
crossover 或 release-wide latency bound。

## 复现

```sh
just bench decimal --target native
just bench all --target native
```

all-suite 运行也覆盖 binary、GDA 和 interval kernel。只有在 target、toolchain、workload
和 benchmark protocol 相同的情况下，artifact 才适合比较。

## 语义门禁

benchmark equivalence check 是必要条件，但不是充分条件。优化后的 decimal 路径还必须
通过 coefficient differential test 以及固定的 IEEE decimal、GDA conformance gate，才能
被接受。参见[一致性说明](./conformance.md)、[设计](./design.md)和[0.7.1 性能与语义审计](../performance_audit.md)。
