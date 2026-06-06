# `bin_float` 教程

## 构造二进制值

```moonbit
let x = @bin_float.BinFloat::make(3N, -1, 32)
let y = @bin_float.BinFloat::make(5N, -1, 32)
inspect((x + y).to_string(), content="1p2")
```

这里的 `1p2` 表示 `1 * 2^2`。

## 看规范化效果

```moonbit
let raw = @bin_float.BinFloat::make(12N, 0, 32)
inspect(raw.significand().to_string(), content="3")
inspect(raw.exponent2().to_string(), content="2")
```

`12 * 2^0` 会被规范化成 `3 * 2^2`。

## 调整精度

```moonbit
let x = @bin_float.BinFloat::make(7N, -2, 32)
let short = x.with_precision(4, @def.RoundingMode::ToNearestEven)
```

## 特殊值与比较

`compare` 只适用于有序值；如果可能出现 `NaN`，先看 `classify()`。
