# `decimal` チュートリアル

Decimal quantum、IEEE context/flags、decimal32/64/128 DPD/BID が contract の場合に使います。
Sticky GDA status/trap は [`decimal_gda`](../decimal_gda/tutorial.md) を使用します。

## Entry Point の選択

| 要件 | 推奨 API |
| --- | --- |
| quantum-preserving parse | `parse/from_string` |
| bounded context + flags | `from_string_ctx` / `*_ctx` |
| canonical cohort | `normalized/reduce_ctx` |
| fixed decimal bits | `DecimalInterchange` |
| observable proof failure | `try_*_ctx` |
| accumulated IEEE pipeline | `decimal_checked` |

## Quantum を失わず Parse

```moonbit check
///|
test "decimal parsing preserves quantum" {
  let amount = @decimal.Decimal::from_string("12.3400", precision=10).unwrap()
  inspect(amount.to_string(), content="12.3400")
  inspect(amount.quantum(), content="-4")
  let reduced = amount.normalized()
  inspect(reduced.to_string(), content="12.34")
  inspect(reduced.quantum(), content="-2")
}
```

`normalized()` は cohort を変えますが数値は変えません。Scale が money/measurement/protocol に
意味を持つ場合は自動 normalize しないでください。

## Exact Decimal Arithmetic

```moonbit check
///|
test "exact decimal arithmetic" {
  let a = @decimal.Decimal::from_string("1.25", precision=20).unwrap()
  let b = @decimal.Decimal::from_string("2.5", precision=20).unwrap()
  inspect((a + b).to_string(), content="3.75")
  inspect((a * b).to_string(), content="3.125")
}
```

External precision/rounding/exponent がある場合は operand precision だけに依存せず context を使います。

## Context と Flags

```moonbit check
///|
test "decimal64 parse and divide" {
  let context = @decimal.DecimalContext::decimal64()
  let (value, parse_flags) = @decimal.Decimal::from_string_ctx(
    "1.234567890123456789",
    context,
  )
  let three = @decimal.Decimal::from_int(3, precision=context.precision())
  let (quotient, divide_flags) = value.div_ctx(three, context)
  let flags = parse_flags.combine(divide_flags)
  inspect(quotient.is_finite(), content="true")
  inspect(flags.contains(@decimal.DecimalSignal::Rounded), content="true")
}
```

Value と combined flags を一緒に保持し、必要に応じ個別 signal を確認します。

## Quantize を明示する

```moonbit nocheck
let context = @decimal.DecimalContext::decimal64()
let value = @decimal.Decimal::from_string("12.3456").unwrap()
let cents = @decimal.Decimal::from_string("0.00").unwrap()
let (rounded, flags) = value.quantize(cents, context)
// rounded has quantum -2; inspect Rounded/Inexact before accepting it.
```

Fit しない target exponent は invalid-operation となり別 scale を選びません。

## Decimal Interchange の Encode

```moonbit check
///|
test "decimal64 DPD round trip" {
  let value = @decimal.Decimal::from_string("1.25").unwrap()
  let (encoded, encode_flags) =
    @decimal.DecimalInterchange::from_decimal_with_encoding(
      value,
      @decimal.DecimalInterchangeFormat::Decimal64,
      @decimal.DecimalInterchangeEncoding::DPD,
    )
  let (decoded, decode_flags) = encoded.to_decimal_ctx()
  inspect(decoded.to_string(), content="1.25")
  inspect(encode_flags.combine(decode_flags).has_error(), content="false")
}
```

BID は external protocol が要求する場合だけ。GDA concrete interchange は別 DPD surface です。

## Certified Elementary Function

```moonbit check
///|
test "certified decimal logarithm" {
  let context = @decimal.DecimalContext::decimal64()
  let ten = @decimal.Decimal::from_int(10, precision=context.precision())
  match ten.try_log10_ctx(context) {
    Ok((value, flags)) => {
      inspect(value.to_string(), content="1")
      inspect(flags.has_error(), content="false")
    }
    Err(_) => abort("decimal log10 could not be certified"),
  }
}
```

Directed dyadic endpoints が同じ Decimal value/flags へ丸まる場合のみ採用されます。

## Decimal / Binary Conversion

```moonbit check
///|
test "binary decimal boundary" {
  let exact_binary = @bin_float.BinFloat::make(
    @bin_float.BinCoeff::from_uint64(3UL),
    -2,
    32,
  )
  let exact_decimal = @decimal.Decimal::from_bin_float(exact_binary, precision=20)
  inspect(exact_decimal.to_string(), content="0.75")

  let tenth = @decimal.Decimal::from_string("0.1", precision=20).unwrap()
  let approximate_binary = tenth.to_bin_float(precision=24)
  let back = @decimal.Decimal::from_bin_float(approximate_binary, precision=10)
  inspect(back.to_string(), content="0.09999999404")
}
```

Decimal real の interval は downward/upward 二回変換して bounds を作ります。Nearest point の
`BallFloat::exact` は original decimal を包む保証がありません。

## Special Value / Ordering

Signed zero、infinity、qNaN/sNaN、payload は explicit。`compare_total` は representation ordering、
`same_quantum` は cohort exponent を検査し numerical equality ではありません。

## 推奨事項

1. Explicit normalize/quantize まで parse quantum を保持。
2. One context と combined flags。
3. Interchange は IO boundary。
4. Untrusted elementary input は `try_*_ctx`。
5. IEEE pipeline と GDA pipeline を混ぜない。

## 次に読む

[Design](./design.md)、[Conformance](./conformance.md)、[Performance](./performance.md)、
[`decimal_checked`](../decimal_checked/tutorial.md) を参照してください。
