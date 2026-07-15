# `bin_float` 教程

适用于天然 dyadic、超出 host Float/Double 精度，或 binary16/32/64/128 rounding/status
属于结果契约的场景。本页基于 0.7.0。

## 选择入口

| 需求 | 推荐 API |
| --- | --- |
| 任意精度精确 dyadic | 普通构造与方法 |
| 固定 precision/exponent/rounding + flags | `*_ctx` + `BinaryContext` |
| 固定位模式 | `BinaryInterchange` |
| 可观察认证失败 | `try_*_ctx` |
| 首错即停组合 | `bin_float_checked` |

## 构造精确 Dyadic 值

```moonbit check
///|
test "construct an exact dyadic" {
  let x = @bin_float.BinFloat::make(
    @bin_float.BinCoeff::from_uint64(3UL),
    -1,
    32,
  )
  inspect(x.to_string(), content="3p-1")
  inspect(x.to_double(), content="1.5")
}
```

`make` 接收非负 coefficient、二进制 exponent 与工作 precision；sign 独立。Normalization
会把二因子移入 exponent：

```moonbit check
///|
test "binary normalization" {
  let x = @bin_float.BinFloat::make(
    @bin_float.BinCoeff::from_uint64(12UL),
    0,
    32,
  )
  inspect(x.coefficient().to_string(), content="3")
  inspect(x.exponent2(), content="2")
}
```

整数优先使用 `from_int/from_bigint`。只有 host binary64 本身是事实来源时才用
`from_double`；它不能恢复调用前已经丢失的十进制信息。

## 使用 Binary Context

需要指定格式、rounding、exponent 或 tininess 时使用 context：

```moonbit check
///|
test "binary16 contextual addition" {
  let format = @bin_float.BinaryInterchangeFormat::Binary16
  let context = @bin_float.BinaryContext::binary16(
    rounding=@bin_float.BinaryRoundingMode::RoundTiesToEven,
    tininess=@bin_float.TininessDetection::AfterRounding,
  )
  let x = @bin_float.BinaryInterchange::from_hex("3C00", format)
    .unwrap()
    .to_bin_float()
  let y = @bin_float.BinaryInterchange::from_hex("4000", format)
    .unwrap()
    .to_bin_float()
  let (sum, arithmetic_flags) = x.add_ctx(y, context)
  let (bits, encoding_flags) = sum.to_interchange(format)
  inspect(bits.to_hex(), content="4200")
  inspect(
    arithmetic_flags.combine(encoding_flags).to_testfloat_bits(),
    content="0",
  )
}
```

多步计算要显式 `combine` flags，并让 value/flags 一起跨过应用边界。Infinity/NaN
常是带 flag 的 defined result，不能自动当作“无结果”。

## 解码与编码 Interchange Bits

固定格式必须通过 `BinaryInterchange`，不要经 host `Double`：

```moonbit check
///|
test "binary32 round trip" {
  let format = @bin_float.BinaryInterchangeFormat::Binary32
  let encoded = @bin_float.BinaryInterchange::from_hex("3F800000", format)
    .unwrap()
  let value = encoded.to_bin_float()
  let (round_trip, flags) = value.to_interchange(format)
  inspect(round_trip.to_hex(), content="3F800000")
  inspect(flags.to_testfloat_bits(), content="0")
}
```

协议若区分 NaN sign/payload 或 signed zero，就应保留/检查对应位状态。普通 `compare`
不是 NaN total order。

## 调用认证初等函数

不可信或超大输入优先使用 `try_*_ctx`：

```moonbit check
///|
test "certified binary exponential" {
  let context = @bin_float.BinaryContext::binary64()
  let one = @bin_float.BinFloat::one(precision=53)
  match one.try_exp_ctx(context) {
    Ok((value, flags)) => {
      inspect(value.is_finite(), content="true")
      inspect(flags.invalid_operation(), content="false")
    }
    Err(error) => {
      // A caller can inspect error.certification_failure_detail() here.
      ignore(error)
      abort("binary exp could not be certified")
    }
  }
}
```

`exp_ctx/sin_ctx` 等 convenience API 使用相同 certificate，只是把证明失败视为不可恢复。

## 有意调整工作精度

`with_precision` 可能改变表示值，因此边界上必须指定 rounding：

```moonbit check
///|
test "retune binary precision" {
  let x = @bin_float.BinFloat::make(
    @bin_float.BinCoeff::from_uint64(7UL),
    -2,
    32,
  )
  let short = x.with_precision(2, @arithmetic.RoundingMode::ToNearestEven)
  inspect(short.to_string(), content="7p-2")
}
```

`ulp()` 是当前表示的 spacing，不是多步计算的认证 error bound。

## 显式处理特殊值

- 使用 `zero/negative_zero`、`quiet_nan/signaling_nan`；
- NaN 可能出现时，ordered comparison 前先 `classify()`；
- status 影响控制流时使用 context API；
- 协议关心 payload/signed zero 时保留 interchange bits。

## 推荐做法

1. 在算法边界一次确定工作 precision，避免反复缩放。
2. 固定格式用 interchange 解码，用一个 context 计算，最后一次编码。
3. 不要丢弃中间 flags。
4. 不可信 elementary input 使用 `try_*_ctx`。
5. 不依赖 limb layout、NTT threshold 或 target dispatch。

## 继续阅读

[Design](./design.md) 解释 kernel/certificate/tuning；[Conformance](./conformance.md)
列出 TestFloat/MPFR 证据；[`bin_float_checked`](../bin_float_checked/tutorial.md)
展示 closed `Result` pipeline。
