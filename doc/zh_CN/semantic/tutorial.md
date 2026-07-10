# `semantic` 教程

## 在公共边界比较表示

```moonbit check
///|
test "semantic scalar projection" {
  let b = @bin_float.BinFloat::from_int(3, precision=32)
  let d = @decimal.Decimal::from_int(3, precision=32)
  inspect(
    @semantic.SemanticScalar::from_bin_float(b) ==
      @semantic.SemanticScalar::from_decimal(d),
    content="true",
  )
}
```

语义值适合跨表示测试、协议边界和诊断。precision、quantum 与格式行为仍应从原始具体值读取。
