# `decimal` 教程

## 从字符串构造

```moonbit
let amount = @decimal.Decimal::from_string("12.3400", precision=32).unwrap()
inspect(amount.to_string(), content="12.34")
```

输出会使用规范化后的十进制形式。

## 十进制算术

```moonbit
let a = @decimal.Decimal::from_string("1.25", precision=20).unwrap()
let b = @decimal.Decimal::from_string("2.5", precision=20).unwrap()
inspect((a + b).to_string(), content="3.75")
```

## 转成二进制

```moonbit
let d = @decimal.Decimal::from_string("0.1", precision=20).unwrap()
let x = d.to_bin_float(precision=24)
let back = @decimal.Decimal::from_bin_float(x, precision=10)
inspect(back.to_string(), content="0.09999999404")
```

这说明当前实现下，`0.1` 这样的非 dyadic 十进制在二进制里只能近似表示。
