# `bin_float` 教程

## 构造和规范化 dyadic 值

```moonbit
let raw = @bin_float.BinFloat::make(
  @bin_float.BinCoeff::from_uint64(12UL),
  0,
  32,
)
inspect(raw.coefficient().to_string(), content="3")
inspect(raw.exponent2().to_string(), content="2")
```

`12 * 2^0` 规范化为 `3 * 2^2`。

## 以 IEEE context 计算

当格式范围和状态标志重要时，使用 `BinaryContext` 与 interchange 位，而不是 host
float：

```moonbit
let format = @bin_float.BinaryInterchangeFormat::Binary16
let context = @bin_float.BinaryContext::binary16()
let x = @bin_float.BinaryInterchange::from_hex("3C00", format).unwrap().to_bin_float()
let y = @bin_float.BinaryInterchange::from_hex("4000", format).unwrap().to_bin_float()
let (sum, flags) = x.add_ctx(y, context)
let (bits, encoding_flags) = sum.to_interchange(format)
inspect(bits.to_hex(), content="4200")
inspect(flags.combine(encoding_flags).to_testfloat_bits(), content="0")
```

`*_ctx` 返回一次正确舍入后的值和 IEEE 状态。普通运算符使用无界
nearest-even context，不能替代 format conformance。

## 特殊值

`negative_zero`、`quiet_nan`、`signaling_nan` 是显式构造器；用
`is_negative_zero`、`is_quiet_nan`、`is_signaling_nan` 与 `nan_payload` 观察其
表示状态。不要对 NaN 使用有序 `compare`。

## 重新调整精度

`with_precision` 显式舍入到新的工作 precision；它不等于选择 binary16/32/64/128。

## 使用 ulp 观察间距

`ulp()` 描述当前表示的间距，适合分析粒度而不是替代 context 误差界。

## 比较与状态

有限值使用 `compare`；遇到 NaN 时先使用 `classify` 和专用谓词，不要假设全序。

## Context 状态

当 flags 属于结果时，保留 `*_ctx` 返回的 `(value, BinaryFlags)`，不要只读取最终值。

## Signed Zero 与 NaN payload

负零、qNaN/sNaN 和 payload 是可观察表示；使用专用构造器和 predicate，不要用普通比较推断它们。
