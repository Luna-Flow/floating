# 二进制系数内核设计

## 动机

本文件的动机段描述迁移前的历史状态：当时 `BinFloat` 将 significand 保存为
MoonBit `BigInt`。当前实现已经完成 `BinCoeff` 公共边界和生产热路径迁移：非 JS
使用纯 inline/limb 内核，JS 在相同 API 后隐藏宿主 `bigint`。语义正确性仍由
BigInt differential oracle 与 IEEE 1788/TestFloat 语料验证。

## 算法依据

1. R. P. Brent, P. Zimmermann, *Modern Computer Arithmetic*, Cambridge University Press, 2010。用于多精度加减、schoolbook/Karatsuba 乘法、除法、平方根及复杂度边界。
2. GNU MP Manual, Low-level Functions。用于 normalized limb 表示、carry/borrow、shift、multiply 与 divide 的接口分层参考。
3. F. Johansson, “Arb: Efficient Arbitrary-Precision Midpoint-Radius Interval Arithmetic,” *IEEE Transactions on Computers*, 2017。用于 ball 热路径的临时精度、误差传播与避免不必要大整数转换。
4. J.-M. Muller et al., *Handbook of Floating-Point Arithmetic*, 2nd ed., 2018。用于 guard/sticky bits、定向舍入和正确舍入验证。

## 表示

生产版 `internal.Coeff` 使用三级规范化表示：

- `Small(UInt64)` 覆盖 0–64 bit，不分配 limb 数组；
- `Medium(UInt64, UInt64)` 覆盖 65–128 bit，使常见 53×53 bit 乘积仍保持 inline；
- `Large(Array[UInt])` 使用 little-endian、base `2^30` 的规范化 limbs；
- `SignedCoeff` 只包装符号和 magnitude，并保证零永远非负；
- 符号与二进制指数仍由上层管理，不混入非负 coefficient 算法。

large 路径选择 30-bit limb，使单 limb 乘积、结果 limb 与 carry 都能放入 `UInt64`。这减少了相同精度下的 limb 数；代价是必须分别验证 native、wasm、wasm-gc 和 JavaScript 的 `UInt64` lowering，不能只用 native 结果推断跨后端性能。

## 边界与热路径

当前允许使用 MoonBit `BigInt` 的位置：

- white-box differential oracle；
- benchmark 输入构造与结果对照；
- JS backend 的隐藏宿主适配器（不是 MoonBit 公共 API）。

禁止在最终热路径使用 MoonBit `BigInt`：

- normalize、compare、precision rounding；
- exponent alignment 与 add/sub；
- mul、div、sqrt、pown；
- `BallFloat` 的 endpoint add/sub/mul/div/FMA；
- 初等函数的 fixed-point range reduction 与 polynomial kernel。

## 迁移顺序

1. 完成 inline 64/128-bit 与 base `2^30` large coefficient 的 compare/add/sub/mul/shift。（已完成）
2. 用 Knuth-style normalized long division 替换逐 bit large division。（已完成）
3. 完成 BigInt differential tests，覆盖 30/64/128-bit 表示边界及 257-bit 商余。（已完成）
4. 将 `BallFloat` certified rational 的分子、分母、交叉约分和 dyadic rounding 迁移到 `SignedCoeff` / `Coeff`。（已完成）
5. `BinFloat`/`BallFloat` 的公开存储与端点算术切换到 `BinCoeff`。（已完成）
6. 为 128-bit 乘除、1024-bit large 路径和跨后端 end-to-end workload 继续调优，
   以 release benchmark 门槛决定后续算法阈值。（持续进行）

首版 base `2^15` + `Array[Int]` correctness-first 实现没有达到性能门槛：native 1024-bit add/mul 明显慢于 MoonBit BigInt，binary long division 慢三个数量级；JS 差距更大。因此生产存储切换已回滚。下一版必须至少包含 small-value allocation-free 表示和 Knuth/Burnikel-Ziegler 类除法，不能把当前 long division 当作生产实现。

首版 benchmark 的代表性 median 比值如下；每个样本批量执行 100 次 add 或 10 次 mul/div，仅用于算法选型，不作为跨机器绝对阈值：

| target | add / BigInt | mul / BigInt | div / BigInt |
| --- | ---: | ---: | ---: |
| native | 约 8.1x 慢 | 约 6.9x 慢 | 约 1287x 慢 |
| JavaScript | 约 20x 慢 | 约 566x 慢 | 约 66700x 慢 |

这组数据否定了“只要换成 Array limbs 就会更快”的假设。后续门槛必须分别覆盖常用 53/128-bit small path 和 1024-bit arbitrary-precision path，并同时比较 native、wasm 与 JavaScript。

第二版 native release 微基准显示 inline 路径已经改变结论，但 large 路径仍未全面胜出。下表是 `Coeff / BigInt` 的近似 median 比值，小于 1 表示 `Coeff` 更快：

| width | add / BigInt | mul / BigInt | div / BigInt |
| --- | ---: | ---: | ---: |
| 53 bit | 约 0.66x | 约 0.53x | 约 0.23x |
| 128 bit | 约 0.66x | 约 3.3x | 约 2.3x |
| 1024 bit | 约 2.8x | 约 1.3x | 约 1.7x |

因此当前生产范围已覆盖 BinFloat 与 BallFloat certified rational；它消除了热循环
对通用 `BigInt` API 的耦合，但历史数据仍显示所有位宽尚未自动快于 MoonBit `BigInt`。
下一优先级是 inline 128×128 乘法、large Karatsuba 阈值、减少 Knuth division 的
临时数组，以及端到端级数中 numerator/denominator 的峰值位宽统计。

任何迁移阶段都必须保持四后端单元测试、BigInt 差分 oracle 和 ITF1788 strict corpus 同时通过。
