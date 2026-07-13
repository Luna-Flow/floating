# `ball_float` 设计

## 职责与表示

`ball_float` 的实际存储是外向舍入的 `lo_`、`hi_` 端点和 precision，不是中心/半径字段。`new(center, radius)` 只是构造器视图。非空区间满足 `lo <= hi` 且端点不含 NaN；Empty、Entire、装饰的 NaI 分别建模。

## 算法选择

加减使用单调端点公式，乘法取四个端点积的最小/最大；除法在分母不含零时使用倒数端点，单侧零产生半无限区间，内部穿零保守返回 Entire。`BallContext` 以负向/正向有向舍入，并返回 `inexact`、`overflow`、`underflow`。

初等函数基于 `BinCoeff` 上的有向 dyadic 区间证书：每步在有限工作精度下外向舍入，并以显式余项界覆盖截断级数。exp 用区间缩减+级数，ln 用 2 次幂缩减+单位区间级数，sin/cos 共享 Machin π 包络并执行象限缩减、交错级数和临界点检测，tan 额外检测极点，正底幂按 `exp(exponent*ln(base))` 加 guard precision 计算。证明失败时 sin/cos 回退 `[-1,1]`，tan 回退 Entire；这保证包络而不猜测标量。

## 装饰与关系

装饰按最小等级传播；关系操作是区间关系而非全序。ITF1788 严格门禁覆盖 `testdata/interval/README.md` 列出的全部阶段，包括通用幂与三角；反向操作不支持。

## 能力边界

当前固定语料 4,113/4,113 严格通过且零 unsupported。安全回退保证包含性，
但不承诺每个结果都是可表示的最紧区间。

## 包含性不变量

若输入是 `X=[x_lo,x_hi]`，加法下端向负无穷、上端向正无穷舍入；乘除选择全部
端点候选极值。无法证明紧界时扩大到安全包络，不能返回遗漏精确结果的假精度。
Empty、Entire 和装饰 NaI 是三个不同状态。

## 初等函数证书

区间缩减、级数和显式余项界共同提供 enclosure certificate；跨越极值或极点时
执行临界点检查。证明不足时 sin/cos 回退 `[-1,1]`、tan 回退 Entire，牺牲
tightness 但保持 inclusion。当前 strict baseline 已包含 general-power 和
trigonometric，reverse operations 仍不支持。

## 复杂度与取舍

基本区间运算只进行常数次端点运算，成本是底层精度 `p` 的 `O(M(p))`，存储为两
个端点。初等函数使用 `O(k)` 个有界级数项和 `O(p)` 工作精度。临界点检查和
Entire/`[-1,1]` 回退牺牲 tightness，换取不可妥协的包含性。

## 证据映射

本文记录耐久算法合同；固定有限声明与排除范围见[一致性说明](./conformance.md)。二进制系数 crossover 证据归入 [`bin_float` 性能](../bin_float/performance.md)，因为 `ball_float` 复用该内核而不维护第二套实现。
