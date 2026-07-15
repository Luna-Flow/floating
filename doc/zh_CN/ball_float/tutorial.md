# `ball_float` 教程

需要包住所有可能数学实值而非单点近似时使用本包。它提供 bare interval、IEEE 1788
decoration、outward context 与认证初等函数。

## 选择入口

| 需求 | 推荐 API |
| --- | --- |
| 精确 dyadic point | `exact` |
| 测量/不确定范围 | `from_bounds` 或 `new` |
| 构造失败作为数据 | `try_from_bounds/try_exact` |
| endpoint bounds + flags | `*_ctx` + `BallContext` |
| 可观察 proof failure | `try_*_interval` |
| decoration/NaI | `BallFloatDecorated` |
| 首错组合 | `ball_float_checked` |

## 嵌入精确 Dyadic 点

```moonbit check
///|
test "exact dyadic interval" {
  let x = @bin_float.BinFloat::make(
    @bin_float.BinCoeff::from_uint64(3UL),
    -1,
    32,
  )
  let interval = @ball_float.BallFloat::exact(x)
  inspect(interval.is_singleton(), content="true")
  inspect(interval.contains(x), content="true")
}
```

`exact` 相对给定 `BinFloat` 精确；降低 interval precision 时两个 bounds 会外向舍入。

## 构造合法范围

```moonbit check
///|
test "bounded interval" {
  let interval = @ball_float.BallFloat::try_from_bounds(
    @bin_float.BinFloat::from_int(1, precision=32),
    @bin_float.BinFloat::from_int(2, precision=32),
    precision=32,
  ).unwrap()
  inspect(interval.contains_zero(), content="false")
  inspect(interval.width().to_string(), content="1p0")
}
```

Endpoint 顺序或 finiteness 不可信时用 `try_from_bounds`；`new(center,radius)` 只是一种
构造视图，集合运算仍基于 bounds。

## 正确包住 Decimal 实值

Nearest decimal-to-binary point + `exact` 只包住该 binary point。原 decimal 必须双向转换：

```moonbit check
///|
test "outward decimal embedding" {
  let decimal = @decimal.Decimal::from_string("0.1", precision=20).unwrap()
  let lower = decimal.to_bin_float(
    precision=32,
    mode=@arithmetic.RoundingMode::TowardNegative,
  )
  let upper = decimal.to_bin_float(
    precision=32,
    mode=@arithmetic.RoundingMode::TowardPositive,
  )
  let interval = @ball_float.BallFloat::from_bounds(lower, upper, precision=32)
  inspect(interval.is_empty(), content="false")
  inspect(interval.lower_bound().compare(interval.upper_bound()) <= 0, content="true")
}
```

在表示边界完成外向构造后，应继续留在 interval domain 中计算。

## 读取集合关系

```moonbit check
///|
test "interval relations" {
  let a = @ball_float.BallFloat::from_bounds(
    @bin_float.BinFloat::from_int(9, precision=32),
    @bin_float.BinFloat::from_int(11, precision=32),
  )
  let b = @ball_float.BallFloat::from_bounds(
    @bin_float.BinFloat::from_int(14, precision=32),
    @bin_float.BinFloat::from_int(16, precision=32),
  )
  inspect(a.disjoint(b), content="true")
  inspect(a.definitely_lt(b), content="true")
  inspect(a.overlaps(b), content="false")
}
```

使用 contains/subset/interior/overlap_state/definitely_lt 等集合关系，不要用 scalar
规则排序 interval。

## 执行外向舍入算术

普通 `+ - * /` 保持 enclosure。分母内部跨零时 division 返回 Entire；单侧零可得到
half-infinite。这些是合法集合结果。需要 endpoint precision/exponent/flags 时用
`BallContext` 与 `*_ctx`。

## 选择 Total 或 Checked 初等函数

```moonbit check
///|
test "certified interval sine" {
  let input = @ball_float.BallFloat::from_bounds(
    @bin_float.BinFloat::zero(precision=64),
    @bin_float.BinFloat::one(precision=64),
  )
  match input.try_sin_interval() {
    Ok(result) => {
      inspect(result.is_empty(), content="false")
      inspect(result.is_bounded(), content="true")
    }
    Err(_) => abort("sine enclosure could not be certified"),
  }
}
```

需要观察 proof/resource failure 时用 `try_*`；希望继续并接受保守范围时用 total API。
Correctness 与 tightness 分开判断，必要时检查 `is_entire()`/width。

## Domain Quality 需要时使用 Decoration

```moonbit check
///|
test "decorated interval" {
  let bare = @ball_float.BallFloat::from_int(4, precision=32)
  let decorated = @ball_float.BallFloatDecorated::new(
    bare,
    decoration=@ball_float.Decoration::Com,
  )
  let root = decorated.sqrt_interval()
  inspect(root.is_nai(), content="false")
}
```

Domain clipping/discontinuity 会降低 decoration。NaI 表示无效 decorated operation，
Empty 是合法空集。

## 推荐做法

1. 每个表示边界都用 outward bounds 构造。
2. 中间结果留在 `BallFloat`，不要只取 midpoint。
3. 使用集合关系。
4. 显式选择 failure error 或 conservative range。
5. Correctness 后再检查 width/Entire。
6. 只有契约需要 decoration/NaI 时才用 decorated interval。

## 继续阅读

[Design](./design.md)、[Conformance](./conformance.md) 与
[`ball_float_checked`](../ball_float_checked/tutorial.md)。
