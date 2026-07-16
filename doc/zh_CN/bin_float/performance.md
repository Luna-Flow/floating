# `bin_float` 性能

<!-- historical-performance-baseline: 0.6.1 -->

## 合同

性能阈值、limb layout、NTT primes、scratch storage 和 fallback 选择都是实现细节。不同算法与 target 必须产生完全相同的公开结果、flags 和 interchange bits。

## 表示

非 JS target 使用 inline 64/128-bit 系数与 little-endian 32-bit limbs；JavaScript 使用隐藏的宿主 `bigint` adapter。公开 `BinCoeff` 使 backend 选择不可观察。

## 乘法

平衡乘法在 96 limbs 以下使用 schoolbook，随后依次考虑 Karatsuba、Toom-3，以及满足 transform bound 时的双质数 Montgomery NTT + CRT。不平衡输入使用 block multiplication 或 overlap-add。native/LLVM 当前在 2,048 limbs 选择 Toom-3/NTT multiply，在 768 选择 NTT square；Wasm/Wasm-GC 分别使用 4,096 和 3,072。native 平方分派在 512 limbs 从专用 schoolbook 切换到递归乘法，其他 target 保持原有 768-limb 边界。

## 除法、开方与 GCD

除法使用单 limb 路径、48 divisor limbs 以下的 Knuth、48 起的 Burnikel–Ziegler，以及 1,024 起的 Newton reciprocal。平方根在 512 bits 内使用 fixed-width kernel，以上使用 divide-and-conquer；大数 GCD 使用 Lehmer batching。

## 测量

统一的 `bench/bin_float` Maremark harness 使用平衡 block 比较系数核、数值核心、checked 全路径与语义等价的平方候选。auto-tune 输出版本化的逐尺度 policy，并且只把阈值应用到实际测量的 target；所有阈值变更仍须通过全 target 正确性测试。

elementary 发布门禁会分别归档不可变的 `0.6.1` commit 与当前 dirty candidate，
向两者注入完全相同的 add/mul/div/sqrt workload，并在 53、128、512 bit 收集十组
交替 AB/BA native 配对样本。只有 candidate 至少慢 3%，且 Maremark 95% bootstrap
区间下界为正时才阻断发布。`0.7.1` 首次新增的函数只运行 candidate workload；
本版本将成为它们的首个合法 baseline，不能为 `0.6.1` 中不存在的 API 伪造耗时。

## 取舍

schoolbook 降低初始化和分配，递归算法减少渐近工作，NTT 改善超大平衡输入但需要 transform 与临时存储。所有快路径保留精确 fallback，因此性能调度不能改变语义。
