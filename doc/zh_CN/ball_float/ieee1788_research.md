# IEEE 1788 实现调研与语义基线

本文记录 `BallFloat` 的 IEEE 1788 set-based flavor 实现依据。目标不是复刻某个测试实现，而是先确定数学集合语义，再用 ITF1788 验证该语义。

## 权威资料

1. IEEE Std 1788-2015, *IEEE Standard for Interval Arithmetic*。这是 bare interval、decorated interval、集合关系、overlap 分类与异常语义的规范来源。
2. IEEE Std 1788.1-2017, *IEEE Standard for Interval Arithmetic (Simplified)*。用于交叉核对常用 inf-sup 运算的最小实现边界。
3. R. E. Moore, R. B. Kearfott, M. J. Cloud, *Introduction to Interval Analysis*, SIAM, 2009。用于集合扩张、包含单调性和外向舍入的数学背景。
4. S. M. Rump, “Verification methods: Rigorous results using floating-point arithmetic,” *Acta Numerica*, 2010。用于浮点误差界、定向舍入与可靠数值计算的算法依据。
5. F. Johansson, “Arb: Efficient Arbitrary-Precision Midpoint-Radius Interval Arithmetic,” *IEEE Transactions on Computers*, 2017，arXiv:1611.02831。用于任意精度 ball 的中点-半径误差传播和实现质量参考。
6. `nehmeier/libieeep1788`，提交 `1f10b896ff532e95818856614ab3073189e81199`。其 MPFR set-based flavor 是关系公式和 decoration 行为的可执行参考。
7. `nehmeier/ITF1788`，提交 `e0e0d7e7335e261e0dff547d15f2bfd3d1a612fa`。其 `.itl` corpus 是互操作测试输入，不替代标准定义。
8. L. Fousse, G. Hanrot, V. Lefèvre, P. Pélissier, P. Zimmermann, “MPFR: A Multiple-Precision Binary Floating-Point Library with Correct Rounding,” *ACM TOMS* 33(2), 2007。用于超越函数端点的正确舍入参考与差分 oracle。
9. A. Ziv, “Fast Evaluation of Elementary Mathematical Functions with Correctly Rounded Last Bit,” *ACM TOMS* 17(3), 1991。用于自适应提高工作精度，直到误差区间能唯一确定目标舍入结果。
10. J.-M. Muller et al., *Handbook of Floating-Point Arithmetic*, 2nd ed., Birkhäuser, 2018。用于 range reduction、正确舍入、table maker's dilemma 与验证策略。
11. M. Payne, R. Hanek, “Radian Reduction for Trigonometric Functions,” *ACM SIGNUM Newsletter* 18(1), 1983, DOI: 10.1145/1008908.1008910。用于大参数 `π/2` 约简的高位常数、商区间与象限唯一性策略。
12. W. J. Cody, W. Waite, *Software Manual for the Elementary Functions*, Prentice-Hall, 1980。用于小参数核、象限映射、极值检测及多项式/级数的工程划分。
13. D. Defour et al., “CRlibm: A Library of Correctly Rounded Elementary Functions in Double-Precision,” *ACM TOMS* 33(2), 2007, DOI: 10.1145/1236463.1236466。用于 Ziv 重试、hard-to-round 输入和正确舍入验证流程。
14. V. Lefèvre, “The Table Maker’s Dilemma,” 2001. 用于 guard bits 不能固定化的反例，以及按区间唯一落入目标 rounding bin 停止的判据。
15. R. P. Brent, P. Zimmermann, *Modern Computer Arithmetic*, 2010, chapters 4 and 12。用于 Newton 平方根、binary splitting、反函数级数与任意精度复杂度选择。
16. D. Goldberg, “What Every Computer Scientist Should Know About Floating-Point Arithmetic,” *ACM Computing Surveys* 23(1), 1991。用于浮点异常、ulp、定向舍入与测试边界的可读性基线。

## 表示选择

`BallFloat` 的公开中心与半径观察接口保留，但规范语义以 inf-sup 集合表示为准：

- Empty 是独立状态，不伪装成非法端点。
- 非空区间满足 `lo <= hi`，允许有限端点和 `±∞`。
- Entire 是 `[-∞,+∞]`。
- 有界区间的中心和半径从端点精确导出。
- sets 与 relations 只比较或选择已有端点，不进行数值近似。

这种结构避免中心-半径表示在 Empty、半无限区间和精确集合关系上的歧义；后续算术仍可使用 ball 算法计算候选包络，但最终必须存为合法的外向舍入 inf-sup 区间。

## 基础算术算法

当前 add/sub/mul/div 采用 MPFI 与 libieeep1788 同类的 inf-sup tight enclosure 路径：

- `add([a,b],[c,d]) = [roundDown(a+c), roundUp(b+d)]`。
- `sub([a,b],[c,d]) = [roundDown(a-d), roundUp(b-c)]`。
- 乘法对四个扩展实数端点积取 min/max；`0 * infinity` 在端点候选中按集合极限取零，避免宿主 NaN 污染。
- 除法不经由已舍入 reciprocal 再乘，以避免二次外向舍入；非零分母直接对端点商取界，含零分母按符号拓扑生成 Empty、半无限或 Entire。
- arbitrary-precision 默认运算与 bounded-exponent flavor 分离；`BallContext::binary32/binary64` 负责 IEEE 指数溢出和 directed endpoint clipping。
- cancellation 仅在两个区间有界且被消去项宽度不大于目标宽度时收紧：`cancelPlus=[a+d,b+c]`，`cancelMinus=[a-c,b-d]`；否则按标准返回 Entire。
- FMA 直接对四个精确乘积端点取范围后与 addend 端点相加，只在最终结果执行一次定向舍入。

该设计遵循 Rump 对可靠浮点计算的定向舍入要求，也采用 Johansson Arb 强调的“内部可用 ball 技巧、公开结果必须保留严格误差界”的工程原则。对于 IEEE 1788 的 set-based flavor，tight inf-sup 端点公式优先于会产生额外宽化的 center-radius 中间结果。

## 初等函数后端路线

初等函数不能用宿主 `Double` 或未经证明的 Decimal 近似充当端点算法。当前选定的最高标准路线是：

1. 纯 MoonBit 实现 arbitrary-precision fixed-point / dyadic ball 核，所有多项式、级数和 range reduction 同时返回显式误差界。
2. 对单调区间先做定义域裁剪和关键点分析，再分别计算 lower/upper directed endpoint；周期函数额外检测极值点与整周期覆盖。
3. 使用 Ziv 策略逐步增加 guard bits；只有当认证结果区间在目标 rounding bin 内唯一时才停止。
4. native 测试后端调用 MPFR 4.2.x 作为差分 oracle，并与 ITF1788 预期端点交叉验证；MPFR 不进入 wasm/js 公共运行时依赖。
5. 每个函数先通过单点正确舍入、定义域、无穷、subnormal/overflow 与 decoration 测试，再开放对应 interval/reverse phase。

这条路线比直接复用现有 Decimal 初等函数更严格：十进制舍入结果转换为 binary 并不能自动证明 binary directed endpoint；同样，固定 guard bits 也无法解决 table maker's dilemma。

当前的 `exp`、`exp2`、`exp10`、`log`、`log2`、`log10` 已作为 correctness-first
认证实现落地，并通过 ITF1788 binary64 指数/对数 phase。生产级数内核采用
`BinCoeff` 上的有向 dyadic 区间运算和显式余项界；`BigInt` 只作为 white-box differential oracle。更高精度与三角函数的
后续工作仍需以 coefficient-native 性能门禁决定算法阈值，设计与边界见
[`binary_kernel_research.md`](./binary_kernel_research.md)。

### `pow`、三角与反函数的具体内核

| 函数族 | 认证核心 | 区间提升 | 关键反例/停止条件 |
| --- | --- | --- | --- |
| `pow(x,y)` | 在非负底定义域上以 `exp(y * ln(x))` 求连续实幂扩张；整数指数继续由独立的 `pown` 承担 | 先把底区间与 `[0,+∞]` 相交，再按 `x` 相对 0/1 与 `y` 的符号提升；单点零底按标准单独处理 | 不把负底的偶然整数指数混入通用 `pow`；`0^0`、零底负指数和部分定义域必须遵循 set-based flavor |
| `sin` / `cos` | Machin `π = 16 atan(1/5) - 4 atan(1/239)` 产生认证 `π`；缩小后的交错 Taylor 级数 | 先以 `π/2` 商区间确定象限；商不唯一或区间跨越驻点时显式加入 `±1` | 商区间无法唯一确定时不猜象限；直接返回覆盖全部可能象限的包络 |
| `tan` / `atan2` | `tan = sin/cos`，`atan` 用交错幂级数与倒数/半角变换 | 检测 `π/2 + kπ` 的可能相交；相交即 Entire；`atan2` 先分象限再合并 | 极点或原点对不能通过端点相除伪装成有限值 |
| `asin` / `acos` / hyperbolic | `asin = atan(x/sqrt(1-x²))`，双曲函数复用认证 `exp` / `ln` / `sqrt` | 先裁剪定义域，端点 `±1`、`0`、无穷单独处理 | 先处理定义域和单调性，再计算有限端点，避免负平方根或 `∞-∞` |

实现遵循 Ziv：工作精度随不确定象限、尾界或目标 rounding bin 的重叠而上调；若表示范围不能容纳所需商或结果指数，则返回规范允许的保守包络，而不产生不可靠数值。

当前实现与资料的逐项对照如下：

- `libieeep1788` 的 `pow` 先与 `[0,+∞]` 相交，并按底数位于 `<=1`、`>=1` 或跨越 1，以及指数为非负、非正或跨越 0 的九种单调区域选择端点。本实现用同一个数学事实把它写成认证的 `ln` 区间、精确双线性区间乘积和认证 `exp`，同时保留零底分支。
- `π` 由 Machin 恒等式和外向舍入的交错 `atan` 级数生成 dyadic 上下界；同一次区间运算共享该包络。端点先用 `2x/π` 的商区间证明最近 `π/2` 倍数唯一，再在 `[-π/4,π/4]` 上用外向舍入的交错 `sin/cos` Taylor 级数和下一项余项界求值。中间量限制在工作精度加 guard bits，避免完全既约有理分母随项数爆炸。
- 区间 `sin/cos` 不只比较端点，还检查区间内所有 `kπ/2` 的模 4 类并显式加入 `±1`；`tan` 若可能包含奇数倍 `π/2` 就返回 Entire，否则利用同一分子、分母认证界求单调端点商。
- Johansson 证明 `|x|≈2^n` 的三角约化通常需要约 `n+p` 位内部精度，并建议极大参数采用保守 cutoff。实现按该精度预算启动并倍增；超过 `max(65536,4p)` 的参数直接让 `sin/cos` 返回 `[-1,1]`、`tan` 返回 Entire。
- ITF runner 已增加独立 `general-power`（1,428 cases）和 `trigonometric`（176 cases）phase；它们在完整零失败验证前不会并入 `interval-ci` 基线。

## Set operations

对非空 `X=[x_lo,x_hi]` 与 `Y=[y_lo,y_hi]`：

- `intersection(X,Y) = [max(x_lo,y_lo), min(x_hi,y_hi)]`；若下端点大于上端点则为 Empty。
- `convexHull(X,Y) = [min(x_lo,y_lo), max(x_hi,y_hi)]`。
- `intersection(Empty,X) = Empty`。
- `convexHull(Empty,X) = X`。

decorated intersection 与 convex hull 对有效非 NaI 输入返回 `trv`；任一输入为 NaI 时返回 NaI。

## Relations

以下公式直接对应 IEEE set-based flavor 和 libieeep1788 的 MPFR 实现：

- `equal(X,Y)`：两者都 Empty，或对应端点相等。
- `subset(X,Y)`：`X` 为 Empty，或 `y_lo <= x_lo && x_hi <= y_hi`。
- `less(X,Y)`：两者都 Empty，或 `x_lo <= y_lo && x_hi <= y_hi`。
- `precedes(X,Y)`：任一为 Empty，或 `x_hi <= y_lo`。
- `strictPrecedes(X,Y)`：任一为 Empty，或 `x_hi < y_lo`。
- `disjoint(X,Y)`：任一为 Empty，或 `x_hi < y_lo || y_hi < x_lo`。
- `interior(X,Y)`：`X` 为 Empty；否则两个端点都严格位于内部，但共同的 `-∞` 下端点和共同的 `+∞` 上端点按规范视为满足内部条件。
- `strictLess(X,Y)`：两者都 Empty；否则两个端点严格小于，但共同的同号无穷端点按规范视为满足严格关系。

`overlap` 使用 Allen interval algebra 的 16 个有效分类，并为 Empty 增加 `bothEmpty`、`firstEmpty`、`secondEmpty` 三种标准状态。实现按端点决策树分类，而不是依赖测试名称或 case 顺序。

decorated 关系忽略 decoration 等级，只比较 underlying bare interval；任一输入为 NaI 时，布尔关系返回 false，`isNaI` 返回 true。

## ITF1788 输入模型

ITF1788 的 C++ 插件把 `[a,b]` 生成为目标类型构造 `I<double>(a,b)`，端点首先按宿主 binary64 字面量规则舍入，而不是调用精确十进制 `textToInterval`。因此当前 runner 明确实例化 binary64 flavor：

- 有限十进制和十六进制端点统一按 53-bit、nearest-even 转换。
- Empty、Entire、infinity 和 decorations 独立解析。
- sets 与 relations 的结果只选择这些 binary64 端点，不发生第二次数值舍入。

未来测试 arbitrary-precision 文本区间构造时，应建立独立的 `textToInterval` 测试路径，不能复用 ITL native-literal 输入规则。

## 验证策略

- 所有已声明 strict phase 必须零失败、零 unsupported、零 diagnostic。
- `arithmetic` 从共享 elementary corpus 中按 operation 精确筛选 add/sub/mul/div，固定覆盖 539 个 bare/decorated binary64 cases。
- `observations` 覆盖 124 个 inf/sup/mid/rad/wid/mag/mig cases，并单独验证 binary64 midpoint 的 subnormal tie-to-even 行为。
- `cancellation` 覆盖 242 个 bare/decorated cancelPlus/cancelMinus cases。
- `elementary-core` 覆盖 107 个 pos/neg/abs/recip/sqr/sqrt cases。
- `fma` 覆盖 567 个 bare/decorated fused multiply-add cases。
- `integer-power` 覆盖 174 个 pown cases，包括负指数与 subnormal 边界。
- `exponential-logarithmic` 覆盖 131 个 `exp`、`exp2`、`exp10`、`log`、`log2`、`log10` cases，包括 binary64 overflow、subnormal 与 decorated 边界。
- `extrema` 覆盖 38 个 bare/decorated min/max cases。
- 库内性质测试覆盖 Empty、Entire、半无限端点、集合包含、共同无穷端点和 overlap 对称分类。
- ITL backend 只负责解析、调用公开 API 和比较结果；IEEE 关系公式必须存在于 `BallFloat`，禁止在 runner 中复制或修补语义。
