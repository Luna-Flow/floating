# `ball_float` 性能

## 测量边界

`just bench ball-float --target native` 运行 `src/bench/ball_float` 中当前的 Maremark
suite，并写入 `.tmp/bench/ball-float.jsonl` 及其 analysis 文件。artifact 测量当前 target
上的分层成本，不是 IEEE 1788 完整性声明，也不是 release-wide latency guarantee。

## 工作负载

suite 在 53、128、512、2,048 bit 上测量 add、multiply、divide。每个 cell 比较 binary
kernel、核心 `BallFloat` 和完整 checked 路径。期望值是精确 binary result；在接受计时观察
前，ball 与 checked 输出必须都与该值匹配为 singleton enclosure。

## 读取结果

`MAREMARK_JSONL` 是原始事件流，`MAREMARK_HOTSPOT` 报告 kernel-to-core 与 core-to-checked
的成对开销。分层成本更低不代表 enclosure 更紧；directed rounding、decoration、pole
和 conservative fallback 仍由核心路径负责。

## 复现

```sh
just bench ball-float --target native
just bench all --target native
```

只有在 target、toolchain、workload 和 benchmark protocol 相同的情况下才比较 artifact。
普通 benchmark test 只编译 plan 而跳过计时。

## 语义门禁

性能证据从属于 enclosure correctness。0.7.1 interval gate 通过 4,656/4,656 条固定的
strict ITF1788 case，其中包括 integer-power regression boundary。参见[一致性说明](./conformance.md)、
[设计](./design.md)和[0.7.1 性能与语义审计](../performance_audit.md)。
