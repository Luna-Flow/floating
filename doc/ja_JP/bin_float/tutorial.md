# `bin_float` チュートリアル

## 2 進値を作る

```moonbit
let x = @bin_float.BinFloat::make(3N, -1, 32)
let y = @bin_float.BinFloat::make(5N, -1, 32)
inspect((x + y).to_string(), content="1p2")
```

## 正規化を見る

```moonbit
let raw = @bin_float.BinFloat::make(12N, 0, 32)
inspect(raw.significand().to_string(), content="3")
inspect(raw.exponent2().to_string(), content="2")
```

## 精度を変える

```moonbit
let x = @bin_float.BinFloat::make(7N, -2, 32)
let short = x.with_precision(4, @def.RoundingMode::ToNearestEven)
```
