# `decimal` チュートリアル

## 文字列から作る

```moonbit
let amount = @decimal.Decimal::from_string("12.3400", precision=32).unwrap()
inspect(amount.to_string(), content="12.34")
```

## 10 進算術

```moonbit
let a = @decimal.Decimal::from_string("1.25", precision=20).unwrap()
let b = @decimal.Decimal::from_string("2.5", precision=20).unwrap()
inspect((a + b).to_string(), content="3.75")
```

## 2 進へ変換する

```moonbit
let d = @decimal.Decimal::from_string("0.1", precision=20).unwrap()
let x = d.to_bin_float(precision=24)
let back = @decimal.Decimal::from_bin_float(x, precision=10)
inspect(back.to_string(), content="0.09999999404")
```
