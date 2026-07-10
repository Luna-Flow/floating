# `ball_float` 教程

## 精确嵌入

```moonbit
let x = @bin_float.BinFloat::make(3N, -1, 32)
let ball = @ball_float.BallFloat::exact(x)
inspect(ball.to_string(), content="3p-1 +/- 0")
```

如果你请求的目标精度低于源值所需精度，`exact` 会自动放大半径，而不是悄悄丢掉包含关系。

## 从十进制近似嵌入

```moonbit
let d = @decimal.Decimal::from_string("12.34", precision=32).unwrap()
let ball = @ball_float.BallFloat::exact(d.to_bin_float(precision=32))
```

这里得到的是基于 `BinFloat` 中心值和误差半径的包络，不是假装十进制值被精确搬过去。

## 看关系判断

```moonbit
let a = @ball_float.BallFloat::new(
  @bin_float.BinFloat::from_int(10, precision=16),
  @bin_float.BinFloat::from_int(1, precision=16),
)
let b = @ball_float.BallFloat::new(
  @bin_float.BinFloat::from_int(15, precision=16),
  @bin_float.BinFloat::from_int(1, precision=16),
)
inspect(a.separated_from(b).to_string(), content="true")
```

可以优先这样理解这些关系：

- `contains` 用于点是否落在包络中
- `overlaps` 用于两个包络是否相交
- `definitely_lt` / `definitely_gt` 只在可证明时给出顺序结论

## 球算术

```moonbit
let c = a + b
let p = a * b
```

返回结果的目标是继续包住真实结果，而不是“精确实数外加一个装饰性误差标签”。中心值在降精度时产生的位移，也会被回收到半径里。
