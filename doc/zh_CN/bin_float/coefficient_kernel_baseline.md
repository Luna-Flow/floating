# `bin_float` 系数内核基线与算法调研

本文记录 2026-07-12 的 coefficient white-box benchmark、正确性基线与算法资料。
文中的早期比率是历史选型证据，不是当前实现的 API 描述。当前工作树已经完成
`BinFloat`/`BallFloat` 的 `BinCoeff` 公共迁移；本文件保留 BigInt 对照数据，用于
回归性能门禁，不应理解为生产热路径仍依赖 BigInt。

## 当前实现边界

最初的 base `2^15`、`Array[Int]` correctness-first 原型已经不是当前工作树的实现。
历史 benchmark 使用的 `internal.Coeff` 是三级规范化表示：

- `Small(UInt64)`：0–64 bit；
- `Medium(UInt64, UInt64)`：65–128 bit；
- `Large(Array[UInt])`：little-endian、base `2^30`；
- large division 已经是 normalized Knuth-style division，并直接写入预分配 quotient
  buffer；不能再把“替换逐 bit division”和“消除 `set_bit` 复制”列为尚未开始的工作；
- 当前生产二进制栈使用 `BinCoeff`：非 JS 为 inline/limb 内核，JS 为隐藏的宿主
  `bigint` 适配器。`BinFloat` 的 contextual add/mul/div/sqrt/pow 与 `BallFloat`
  endpoint/rational 路径都不再调用 MoonBit `BigInt`。
- `BigInt` 仅保留在 white-box differential oracle、benchmark 输入构造，以及 JS
  适配器的宿主实现中。

比较对象也不是朴素大整数。当前 MoonBit non-JS `BigInt` 使用 base `2^32`、
`FixedArray[UInt] + len`、单 limb 特化、Knuth division，并在 50 limbs 后切换
Karatsuba；JS 后端直接使用宿主 `BigInt`。因此 large `Coeff` 必须靠浮点专用信息流、
更少分配或经实测的算法阈值取胜，而不能假定 Array limbs 天然更快。

## 测量方法

直接基准位于：

- `src/internal/coeff_bench_wbtest.mbt`：转换、compare/add/sub/shift、exact multiply、
  quotient/remainder、组合式 round-shift、full-product-then-round、rounded division、
  Newton integer sqrt，以及表示/算法边界；
- `src/bin_float/bin_float_bench_wbtest.mbt`：私有 BigInt round/div/sqrt oracle 与当前
  `add_ctx`、`mul_ctx`、`div_ctx`、`sqrt_ctx`、`pow_int_ctx`；
- `tools/run_bin_coeff_bench.py`：release 执行、marker 合并、环境记录、至少五轮校验、
  `Coeff / BigInt` median 比率和 Markdown/JSON 输出。

主位宽为 53、113、256、1024、4096 bit；另测 63/64/65、127/128/129 的 inline
边界和 1536/1600/1632 的 MoonBit BigInt Karatsuba 邻域。输入覆盖 dense、sparse、
全 1、2 的幂边界、巨大 shift、单 limb divisor、近等除数与宽商。

MoonBit core `Bench` 先把每个 closure 自动校准到约 100 ms，再采集五轮并报告 median、
MAD 与 batch size。输入构造和 `BigInt ↔ Coeff` 转换均在被测 primitive 外完成；转换
另设独立项目。时间单位是每次 benchmark closure 的微秒。

复现命令：

```sh
just bin-bench
just bin-bench js
python3 tools/run_bin_coeff_bench.py --target native
```

## 本机基线

| 字段 | 值 |
| --- | --- |
| Git | `3d076ccd9de3f876c5505f771c6c484f41bd6483`，dirty worktree |
| MoonBit | `moon 0.1.20260703`；`moonc v0.10.3+16975d007` |
| 构建 | native、release、no-parallelize |
| 硬件 | MacBook Air `Mac16,12`；Apple M4；10 cores（4P + 6E）；16 GB |
| 系统 | Darwin 25.5.0、arm64 |
| 样本 | 418 条 coefficient、65 条 BinFloat；每条 5 runs |
| 原始结果 | `.tmp/bin-coeff-bench/bin-coeff-bench-20260712T003533922216Z-native.json` |
| 完整表 | `.tmp/bin-coeff-bench/bin-coeff-bench-20260712T003533922216Z-native.md` |

dirty worktree 下只记录 commit 不足以复现。本轮关键输入文件 SHA-256 为：

| 文件 | SHA-256 |
| --- | --- |
| `src/internal/coeff.mbt` | `8cca30112bca7033da9289778fbef90481321857f32dff47abcb49dbd204f075` |
| `src/internal/coeff_bench_wbtest.mbt` | `3b4d5c2c0d0bec8153b780b7af11b3ce905342d5ebcc83525acce256ece22f46` |
| `src/bin_float/context_arithmetic.mbt` | `9b20fca9b04f73c69a6e36dba3d7deed3ad48bad19d50ade0d3de8646e574a1c` |
| `src/bin_float/bin_float_bench_wbtest.mbt` | `866a77ff1646cbe18bf70c8720770a59f19ca7b2de9ceec77e08648379f6ae24` |
| `tools/run_bin_coeff_bench.py` | `c0b3bd5f06129592ca841394eee86fbe7737673a0dfdb22b9d5068dfefbe4ede` |
| `moon.mod` | `b1d9e37e1c5eebd711d7029b7e781fc6a736272479e6750bdd2ed0f4a41f3dcf` |

### Dense primitive 比率

下表为 `Coeff / BigInt` median；小于 1 表示 `Coeff` 更快。

| 操作 | 53 | 113 | 256 | 1024 | 4096 |
| --- | ---: | ---: | ---: | ---: | ---: |
| compare | 0.999 | 0.956 | 2.449 | 1.370 | 2.533 |
| add | 0.781 | 0.678 | 2.904 | 3.043 | 2.188 |
| sub | 0.832 | 0.699 | 3.061 | 2.374 | 1.887 |
| shift left | 0.883 | 5.338 | 3.509 | 3.082 | 1.935 |
| shift right | 0.727 | 0.906 | 2.630 | 2.068 | 1.653 |
| exact multiply | 0.761 | 2.565 | 1.496 | 1.339 | 1.836 |

53-bit `Small` 在 add/sub/shift/multiply 上有效；113-bit `Medium` 的 add/sub/right shift
有效，但 left shift 和乘法已经退回临时 limbs。256 bit 以上除个别 division shape 外，
通用 primitives 大多慢于 BigInt。

### Division 形状

| 形状 | 53 | 113 | 256 | 1024 | 4096 |
| --- | ---: | ---: | ---: | ---: | ---: |
| near equal | 0.167 | 1.067 | 0.766 | 0.996 | 0.694 |
| single-limb divisor | 0.399 | 1.475 | 1.500 | 0.938 | 0.638 |
| wide quotient | 0.430 | 1.032 | 1.095 | 0.790 | 0.614 |

当前 Knuth division 在 4096-bit 三种形状上均快于 BigInt，wide quotient 约为 1.63×
加速；但 1024-bit wide quotient 只有约 1.27×，113/256-bit 仍有退化。因此它尚未满足
“1024 bit 以上至少 1.5×”的统一接线门槛，也不需要先重写成另一份 Knuth D。

### 浮点组合原语

这些项目使用现有 primitives 组合出正确语义，不代表已经实现 fused/high-product
生产原语。

| 操作 | 53 | 113 | 256 | 1024 | 4096 |
| --- | ---: | ---: | ---: | ---: | ---: |
| round-shift composed | 0.538 | 0.540 | 2.425 | 2.648 | 1.875 |
| full multiply + round | 0.596 | 2.525 | 2.248 | 1.495 | 1.703 |
| rounded division | 0.452 | 0.932 | 1.338 | 0.921 | 0.647 |
| Newton integer sqrt | 0.814 | 1.997 | 2.486 | 1.615 | 1.314 |

结果直接支持 fused shift/guard/sticky 优先：large composed round-shift 慢 1.88–2.65×，
当前实现会构造 quotient、shift-back value、remainder 和 half。full-product-then-round 在
113 bit 以上也明显浪费低位。coefficient Newton sqrt 在 1024/4096 bit 分别慢约 1.62×
和 1.31×，未达到大数 sqrt 门槛。

## 后续优化：fused round-shift

第一项候选已经按 Berkeley SoftFloat `shiftRightJam` / `roundPack` 和 Go
`math/big.nat.sticky` 的信息流实现为 package-private ties-to-even 原语。它直接从原表示
读取 round bit 与 sticky，不构造 shift-back、remainder 或 half；`Large` 在生成保留
limbs 时直接传播舍入进位，并且只执行一次 normalization。生产 dispatch 仍未改变。

下表是同机 native release、每项五轮 median，单位为微秒：

| bits | composed | fused | composed / fused | fused / BigInt |
| ---: | ---: | ---: | ---: | ---: |
| 53 | 0.03958 | 0.01595 | 2.48× | 0.244× |
| 113 | 0.04021 | 0.01583 | 2.54× | 0.220× |
| 256 | 0.22847 | 0.04732 | 4.83× | 0.585× |
| 1024 | 0.38314 | 0.05504 | 6.96× | 0.386× |
| 4096 | 0.72883 | 0.10174 | 7.16× | 0.258× |

因此 fused round-shift 本身通过“至少提升 25%”门槛，并且五个目标位宽都快于 BigInt。
把它放在 full exact multiply 之后，整体 multiply+round 只提升约 1.05–2.52×；113、
1024、4096 bit 仍受 exact multiplication 主导而慢于 BigInt，不能据此接入生产乘法。

正确性覆盖包括 `n < 2^12`、`shift=0..15` 穷举，30/64/128-bit 表示边界，
half−1/half/half+1、偶奇商 tie、全一 discarded bits、超大 shift，跨
`Small → Medium → Large` 舍入进位，以及固定 seed 到 1024-bit 的 BigInt differential。
四个 MoonBit 后端的 `internal` package tests 在 fused 版本均为 12/12；后续 Small carry
版本扩展到 14/14，见下一节。

## 后续优化：Small add carry

`Small + Small` 的 65-bit carry-out 已改为直接返回 `Medium(1UL, wrapped_sum)`。
两个 `UInt64` 的数学和小于 `2^65`，所以发生 wrap 时高 word 必然且只能为 1；旧路径
却把两个输入转换成 base-`2^30` arrays，再经过通用加法和 normalization。

benchmark 保留了旧通用路径作为 `legacy`，并在同一 native release 进程中测量
legacy/current/BigInt。下表是第二次完整运行的五轮 median，单位为微秒：

| 形状 | legacy | current | BigInt | legacy / current | current / BigInt |
| --- | ---: | ---: | ---: | ---: | ---: |
| 64-bit representation dense | 0.06261¹ | 0.01005 | 0.01305 | 6.23× | 0.770× |
| carry dense、low 非零 | 0.06338 | 0.01005 | 0.01295 | 6.31× | 0.776× |
| `MAX + 1`、low 为零 | 0.06471 | 0.01038 | 0.01297 | 6.24× | 0.800× |
| 最大无 carry | — | 0.00993 | 0.01262 | — | 0.787× |

¹ 该格是修改前的独立基线；其余 legacy/current/BigInt 为修改后的同进程结果。

两次完整运行中，carry dense 的 current median 为 0.01008 / 0.01005 µs，相差
0.32%；zero-low 相差 2.23%，no-carry 相差 0.62%。63-bit 与 65-bit add 的稳定复跑
分别比修改前快约 0.6% 和 2.7%，没有超过 5% 的相邻路径回归。该操作通过至少 3×、
`Coeff / BigInt ≤ 0.90` 和多轮稳定性门槛。

正确性新增 256×256 的 UInt64 wrap 边界窗口、固定 seed 64-bit 双向随机差分，以及
`Small` / `Medium(1, low)` / 禁止 `Large` 的表示不变量。`BinFloat` dispatch 与公开
API 均未改变；现有 coefficient 调用方会直接获得该精确加法快路径。四后端
`internal` tests 各 14/14，`bin_float + ball_float` 各 24/24，全部在
`--deny-warn` 下通过。

## 后续优化：BigInt → Medium

65–128 bit 的非负 `BigInt` 现在直接拆成 `Medium(high, low)`：`low` 取输入低 64 位，
`high` 取输入右移 64 位后的低 64 位。MoonBit `BigInt::to_uint64` 的公开语义就是返回
低 64 位；该分支已经先证明 bit length 大于 64 且不超过 128，因此 `high` 必非零且
不会丢失有效位。旧实现会先执行多轮 base-`2^30` 除法、分配 limbs，再由
`coeff_make` 重组回同一个 `Medium`。

benchmark 保留旧转换为 `legacy/from_bigint_medium`。下表为第二轮 native release、
dense 输入的五轮 median，单位为微秒：

| bits | legacy | current | legacy / current | 两轮 current 差异 |
| ---: | ---: | ---: | ---: | ---: |
| 65 | 0.14343 | 0.03209 | 4.47× | 0.27% |
| 113 | 0.19890 | 0.03185 | 6.25× | 0.66% |
| 127 | 0.25659 | 0.03262 | 7.87× | 1.24% |
| 128 | 0.24410 | 0.03364 | 7.26× | 2.94% |

修改前后 53、256、1024、4096-bit dense conversion 的差异分别约为 +1.2%、−0.4%、
−1.6%、−1.0%，均未触发 5% 回归门槛。正确性覆盖 64/65/127/128/129-bit 边界、
high/low 字段级断言、每个 65–128 bit 位宽的固定 seed 随机 roundtrip 和规范表示。
四后端 `internal` tests 各 15/15，`bin_float + ball_float` 各 24/24；公开接口与
`BinFloat` dispatch 均未改变。

这项优化显著降低 inline coefficient 的入口成本，但 256 bit 以上仍使用 limb 除法，
而且生产 workload 是否能持续停留在 `Coeff` 仍需端到端证明，因此不能单独据此设置
dispatch cutoff。

### 表示与算法边界

- 64-bit dense add 发生 `Small` 溢出并转为 `Medium`，约慢 4.10×；65-bit `Medium`
  add 恢复为约 0.79×。
- 128-bit dense add 发生 `Medium` 溢出并转为 `Large`，约慢 4.65×；129-bit large add
  仍慢约 3.41×。
- 64-bit exact multiply 为约 0.72×；65、127、128 bit multiply 分别约为
  3.07×、2.99×、3.09×，说明缺少 dedicated Medium multiplication。
- 1536/1600/1632-bit exact multiply 分别约慢 1.22×、1.22×、1.34×；当前 large
  schoolbook 在 BigInt Karatsuba 邻域没有优势。
- 全量运行出现两次单轮系统级长尾。129-bit division 定向复跑后 `Coeff` / `BigInt`
  median 为 0.139 / 0.176 µs（约 0.79×，MAD 0.94% / 3.00%）；结论不依赖异常样本。

### Conversion 成本

| bits | BigInt → Coeff（µs） | Coeff → BigInt（µs） |
| ---: | ---: | ---: |
| 53 | 0.022 | 0.013 |
| 113 | 0.280 | 0.054 |
| 256 | 0.697 | 0.327 |
| 1024 | 4.940 | 1.703 |
| 4096 | 60.415 | 16.421 |

4096-bit `BigInt → Coeff` 已比 dense exact multiply 慢约 3.4×，比 add 慢两个数量级。
任何生产 dispatch 若在每次操作前后转换，都会吞掉 primitive 收益；dispatch 必须让一段
计算持续停留在同一表示，或直接回退 BigInt。

### 当前端到端 BigInt 基线

以下为 dense `BinFloat` 当前生产路径的绝对 median（µs），供未来接线后同语义比较：

| bits | add_ctx | mul_ctx | div_ctx | sqrt_ctx | pow_int_ctx(7) |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 53 | 0.397 | 0.272 | 0.498 | 2.343 | 0.440 |
| 113 | 0.424 | 0.314 | 0.586 | 3.750 | 0.732 |
| 256 | 0.474 | 0.389 | 1.036 | 4.879 | 1.480 |
| 1024 | 0.843 | 1.373 | 6.053 | 32.602 | 19.580 |
| 4096 | 2.448 | 12.109 | 66.933 | 424.543 | 170.245 |

## 正确性证据

本轮实际执行：

| 门禁 | 结果 |
| --- | --- |
| benchmark composed/fused helper differential | 53/113/256-bit 全部通过 |
| `internal` package tests | wasm/wasm-gc/js/native 各 15/15 |
| `bin_float + ball_float` package tests | wasm/wasm-gc/js/native 各 24/24 |
| committed TestFloat smoke | 60/60 |
| committed MPFR sqrt smoke | 3/3 |

仓库已记录但本轮没有重新执行的全量证据：TestFloat level 1
7,461,360 / 7,461,360、MPFR sqrt 1,055 / 1,055、binary16 level 2
50,205,600 / 50,205,600。它们是当前语义 oracle 的既有基线，不应误写成本次 dirty
worktree 的新执行结果；生产接线前必须重新运行。

修复 `frontend/itl_expr` 的失效依赖后，Small carry 与 Medium conversion 已在当前
工作树直接复验：wasm、wasm-gc、JS、native 的 `internal + bin_float + ball_float`
package tests 均为 39/39，并启用 `--deny-warn`。这仍是相关 package 门禁，不误写成
全模块或外部语料验收。
这个当时存在的临时阻塞现已通过把 `BallFloatDecorated` 合并到 `ball_float` 包消除；
上述说明只保留为该轮复验环境的历史记录。

## 论文与成熟实现对照

1. Brent、Zimmermann，[*Modern Computer Arithmetic*](https://doi.org/10.1017/CBO9780511921692)：
   多精度乘除、SqrtInt、复杂度与递归算法边界。
2. Knuth，[*The Art of Computer Programming*, Vol. 2, §4.3.1](https://www-cs-faculty.stanford.edu/~knuth/taocp.html)：
   normalized long division / Algorithm D；当前 Coeff 与 MoonBit BigInt 都已采用这一类结构。
3. Burnikel、Ziegler，[*Fast Recursive Division*](https://pure.mpg.de/pubman/faces/ViewItemOverviewPage.jsp?itemId=item_1819444)：
   大数递归除法候选；阈值不能照抄 OpenJDK/GMP。
4. Mulders，[*On Short Multiplications and Divisions*](https://doi.org/10.1007/s002000050125)：
   short/truncated product 候选；正确舍入还必须精确处理 omitted low product 的 carry 与 sticky。
5. [GNU MP 6.3 Algorithms](https://gmplib.org/manual/Algorithms.html) 与
   [`mpn/generic`](https://gmplib.org/repo/gmp/file/tip/mpn/generic/)：basecase、
   Karatsuba/Toom/FFT、single-limb/basecase/divide-and-conquer division、`mullo_n` 与
   `sqrtrem` 的分层参考。
6. Berkeley [SoftFloat 3e](https://www.jhauser.us/arithmetic/SoftFloat-3/doc/SoftFloat-source.html)：
   `shiftRightJam` 只保留高位并把全部 discarded nonzero 信息压成 sticky；`roundPack`
   再统一处理 tie、方向与 flags。本仓库固定的 3e 源码也验证了 f128 mul/div/sqrt 只把
   目标 significand、extra 和 jam 信息交给 round-pack。
7. Go [`math/big`](https://go.dev/src/math/big/)：`nat.sticky` 扫描被丢弃 words，division
   原地覆盖 remainder，scratch stack 局部复用，SqrtInt 使用 Newton；其 40-word
   Karatsuba/recursive-division 阈值是经过 Go 校准的实现数据，不是 MoonBit 常量。
8. OpenJDK [`BigInteger`](https://github.com/openjdk/jdk/blob/master/src/java.base/share/classes/java/math/BigInteger.java)
   与 [`MutableBigInteger`](https://github.com/openjdk/jdk/blob/master/src/java.base/share/classes/java/math/MutableBigInteger.java)：
   Knuth/Burnikel-Ziegler dispatch 与 mutable scratch 的结构参考；阈值不可移植。

## 下一轮优先级

1. fused ties-to-even round-shift 候选已经达到独立性能门槛；接线前补齐其他舍入模式的
   语义策略，并证明调用链不会被 `BigInt ↔ Coeff` 转换成本抵消。
2. `Small + Small` 的 65-bit carry-out 已通过门禁；下一步为 `Medium` 补全 shift、
   128×128 multiply 和除法特化，并单独处理 128-bit
   carry-out，不让 inline 边界退回通用 arrays。
3. 把 full-product-then-round 作为 oracle，实验 truncated high product；只有 retained
   high bits、guard 和 exact sticky 全部差分一致后才允许接线。
4. 保留当前 Knuth division，先减少 normalization/copy 与 Medium/single-limb 开销；
   仅在 1024/4096 实测显示 crossover 后实验 Burnikel-Ziegler。
5. 对 sqrt 并行比较局部 scratch 的 Newton/division 与直接生成目标有效位；用
   `s² ≤ n < (s+1)²`、remainder 和 rounded result 同时验收。
6. 只在 allocation/copy profiling 证明收益后加入调用内 scratch；不使用跨调用全局池，
   对外继续返回不可变 `Coeff`。
7. `pow_int` 已接入单轨迹 Ziv：每轮近似值带保守 dyadic 误差半径，区间两端必须在
   目标舍入、无界舍入、overflow 与 tininess 分类上完全一致才返回；否则提高精度或
   回退 exact multiply + 最终一次舍入。真正 high-product 接线仍需独立证明 omitted-low
   carry 与 sticky，因此本轮继续使用完整中间乘积。

### `pow_int` 单轨迹 Ziv

非 2 次幂的大结果使用最高位起始的 addition chain/binary powering，不再同时维护
上下两条乘法链。正指数的保守误差半径按 exponent bit length 取整到工作 ulp；负指数
先做一次 reciprocal，并使用更宽的误差权重。误差区间不能唯一决定值和 flags 时不会
猜测，而是提高工作精度，最多 12 轮后进入精确 oracle。

小结果若预估完整系数不超过 2048 bit，直接走 exact-fast dispatch；这避免 53/113-bit
被 Ziv 区间构造固定成本拖慢。`BinCoeff::pow_nat` 同时改为最高有效位起始，消除
`1 * base`。固定 seed 的 white-box 差分覆盖六种舍入、正负指数和 before/after
tininess；MPFR 4.2.2 的五种通用舍入模式固定语料为 120/120。MPFR 明确禁止把
`MPFR_RNDNA` 当作通用 `pow_si` 参数，因此 nearest-away 只以精确 dyadic/rational
oracle 验收，不伪造 MPFR 证据。

native release 的绝对时间受同机负载影响较大；最终复跑中 4096-bit dense `pow(7)`
为 125.67 µs、同轮 `mul_ctx` 为 25.82 µs，即 4.87×，通过“约 6×”门槛。另一次低负载
复跑分别为 41.01 / 8.06 µs，比例为 5.09×。后续 benchmark 增加同进程
`pow_int_ctx_exact_oracle` 对照，避免跨运行绝对值误判。

同进程 oracle 对照复跑中，1024-bit candidate/exact 为 5.80/9.10 µs（快 36.2%），
4096-bit 为 59.92/257.72 µs（快 76.8%）。53-bit 为 0.274/0.268 µs（+2.2%）；
113-bit 两次复跑的 candidate/exact 比率分别为 0.95× 与 1.07×，方向随系统噪声变化，
没有形成稳定回归信号。大数收益在同进程对照下仍显著超过 35% 门槛。

## 当前门禁结论

| 指标 | 结论 |
| --- | --- |
| 正确性 | fused 定向差分与四后端包测通过；三组全量外部语料尚未在本轮重跑 |
| 小位宽回归 | 64-bit add carry 已修复且无相邻回归；113-bit multiply、128-bit carry boundary 仍明显退化 |
| 整体收益 | fused round-shift 单项通过；历史全矩阵几何平均仍为 `Coeff / BigInt = 1.485×`，尚无 workload-weighted 生产收益 |
| 大数 division/sqrt | 未通过：4096-bit division 部分形状达到 1.5×，1024-bit 与 sqrt 未统一达到 |
| 稳定性 | 大多数 MAD 低；异常样本已定向复跑，但 dispatch 前仍需多次完整 suite 复验 |
| 后端 | 四后端正确性通过；本报告只有 native 性能数据 |

结论：**暂不接入 `BinFloat` 生产路径，不设置 dispatch cutoff，继续使用 BigInt。**
fused round-shift、64-bit add carry 与 BigInt → Medium 优化均保留；下一项评估
`Medium` shift/add/multiply 专用路径，每项继续单独带 benchmark 与差分测试。
