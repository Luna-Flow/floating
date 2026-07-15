# `ball_float` 一致性说明

## 声明

当前 strict ITF1788 门禁执行 4,656/4,656 个选中 case，failed、unsupported 与 diagnostic 均为零。该声明只覆盖固定语料 revision、已选 operation phase 和 runner precision，不等于完整实现 IEEE 1788。

## 语义 Oracle

预期结果按集合意义比较：端点包含、集合关系、布尔关系、overlap state、数值观察和 decoration 分别使用操作专用比较器。合同允许放宽时，更宽区间可以正确；排除精确结果的包络永远错误。

## 支持 Phase

strict 矩阵覆盖 sets、relations、observations、cancellation、加减乘除、elementary core、指数/对数、general power、包含 `atan2` 的三角函数、FMA、整数幂与 extrema。各 phase 的 operation set 互不重叠，同一行不会重复计数。

## Decoration 与 Fallback

Empty、Entire 和 decorated NaI 是不同状态。初等函数内核使用有向 dyadic 证书；若无法证明 range reduction，`sin`/`cos` 返回 `[-1,1]`，`tan` 返回 Entire。这样保证包含性，但不承诺 tightness。

## 排除范围

reverse interval operation、选定 phase 以外的全部 decoration 规则、任意 endpoint format 和未固定的上游 revision 均不在声明内。

## 复现

```sh
just conformance smoke interval
just conformance fetch interval itf1788
just gate interval 8
```

语料来源、phase 计数、strict 模式和失败排查见[区间数据指南](../../../testdata/interval/README.md)。
