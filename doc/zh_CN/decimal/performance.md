# `decimal` 性能

## 基线门禁

`just bench decimal` 将当前树与 `testdata/decimal/performance_baseline.json` 中的不可变 manifest 比较。它运行成对 AB/BA/AB 进程，每个 cell 至少需要九个有效 sample，拒绝不稳定 MAD，并在 paired median 回退超过 5% 时失败。

## 操作数模型

测量把 limb 数量与 dense、sparse、square、unbalanced shape 分开。内核存储 canonical little-endian base-1e9 limbs，而 NTT 转换为更小工作 digit。单一全局 digit 阈值无法描述 padding 和 shape crossover。

## Native 乘法校准

native 的 multiply 在 96 limbs 从 schoolbook 切到 Karatsuba，square 在 48 切换；Karatsuba→Toom-3 为 1,152。transform-band NTT multiply 从 1,728/2,816/4,608/7,680 limbs 起，square 从 640/1,040/1,824/3,648/7,296 起。其他 target 保留独立的保守值。

## 除法校准

native 的 Burnikel–Ziegler 阈值随 block band 为 2,816、5,120 和 10,240 limbs。Newton reciprocal division 仍用于 differential test，但因测量慢于 Burnikel–Ziegler，不在 native 自动选择。

## 统计方法

阈值实验使用 ABBA/BAAB 顺序，在进程间旋转 size 顺序，拒绝不稳定进程，拟合加权非增 isotonic regression，并按完整 process column bootstrap。生产边界必须同时满足 95% upper confidence threshold、`p <= 0.05` 的单侧 sign test 和至少 3% median 改善。

## 复现与解释

```sh
just bench decimal --target native
just bench decimal-threshold --model --transition mul-toom3-ntt-32k \
  --model-low 4096 --model-high 5120 --model-step 128 \
  --processes 5 --samples 9 --bootstrap-samples 5000
```

阈值是 target-specific 证据，不是 API 承诺。更快路径必须先通过系数 differential test 与 IEEE/GDA conformance。
