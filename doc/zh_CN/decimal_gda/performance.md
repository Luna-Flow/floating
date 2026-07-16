# `decimal_gda` 性能

## 测量边界

`just bench decimal-gda --target native` 运行 `src/bench/decimal_gda` 中当前的 Maremark
suite，并写入 `.tmp/bench/decimal-gda.jsonl` 及其 analysis 文件。独立 quick fixture 可用
`python3 tools/run_gda_benchmark.py` 运行，写入 `.tmp/bench/gda-quick-native.json`，每个
cell 使用三个 native run。两个 artifact 都不是通用速度声明，也不能替代 conformance gate。

## 工作负载

Maremark suite 在 1、9、18、34、128 位十进制数字上测量 add、subtract、multiply、divide、
FMA 和 parse。它比较核心 `GdaContext` 路径与完整 checked 路径，并在报告分层开销前将两者
与 core result 做验证。

## 读取结果

`MAREMARK_JSONL` 是原始事件流，`MAREMARK_HOTSPOT` 报告 core 与 checked 的成对开销。
quick fixture 还记录每个 operation 的 median 和 dispersion。结果只适用于记录的 target、
toolchain、fixture 和 workload，不能证明跨 target threshold 或固定 latency bound。

## 复现

```sh
just bench decimal-gda --target native
python3 tools/run_gda_benchmark.py
just bench all --target native
```

比较 artifact 时保持 target 和 toolchain 相同。普通 benchmark test 只编译 plan 而跳过计时，
因此必须显式运行 benchmark command 才会产生测量。

## 语义门禁

计时路径只有与独立的 GDA 状态模型和固定合法标量语料一起验证后才可接受：0.7.1 审计中的
当前 64,986/64,986 行与 legacy 16,124/16,124 行全部通过。参见[一致性说明](./conformance.md)、
[设计](./design.md)和[0.7.1 性能与语义审计](../performance_audit.md)。
