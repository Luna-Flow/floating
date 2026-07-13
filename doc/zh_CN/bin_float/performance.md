# `bin_float` 性能

## 合同

性能阈值、limb layout、NTT primes、scratch storage 和 fallback 选择都是实现细节。不同算法与 target 必须产生完全相同的公开结果、flags 和 interchange bits。

## 表示

非 JS target 使用 inline 64/128-bit 系数与 little-endian 32-bit limbs；JavaScript 使用隐藏的宿主 `bigint` adapter。公开 `BinCoeff` 使 backend 选择不可观察。

## 乘法

平衡乘法在 96 limbs 以下使用 schoolbook，随后依次考虑 Karatsuba、Toom-3，以及满足 transform bound 时的双质数 Montgomery NTT + CRT。不平衡输入使用 block multiplication 或 overlap-add。native/LLVM 当前在 2,048 limbs 选择 Toom-3/NTT multiply，在 768 选择 NTT square；Wasm/Wasm-GC 分别使用 4,096 和 3,072。

## 除法、开方与 GCD

除法使用单 limb 路径、48 divisor limbs 以下的 Knuth、48 起的 Burnikel–Ziegler，以及 1,024 起的 Newton reciprocal。平方根在 512 bits 内使用 fixed-width kernel，以上使用 divide-and-conquer；大数 GCD 使用 Lehmer batching。

## 测量

被跳过的 white-box bench 会在 crossover 周围强制各算法，并比较 dense、sparse、square 与 unbalanced shape。阈值变更必须通过全 target differential correctness test 和可复现 release 测量；单机结果不是可移植常数。

## 取舍

schoolbook 降低初始化和分配，递归算法减少渐近工作，NTT 改善超大平衡输入但需要 transform 与临时存储。所有快路径保留精确 fallback，因此性能调度不能改变语义。
