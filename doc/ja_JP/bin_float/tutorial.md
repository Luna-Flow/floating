# `bin_float` チュートリアル

自然な dyadic、host Float/Double を超える precision、または binary16/32/64/128 の
rounding/status が contract の場合に使用します。0.7.1 対応です。

## Entry Point の選択

| 要件 | 推奨 API |
| --- | --- |
| exact arbitrary-precision dyadic | ordinary constructor/method |
| bounded format + flags | `*_ctx` + `BinaryContext` |
| fixed bits | `BinaryInterchange` |
| observable certification failure | `try_*_ctx` |
| first-error composition | `bin_float_checked` |

## Exact Dyadic Value の構築

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

`make` は non-negative coefficient、binary exponent、working precision を受け、sign は別です。
Normalization は factor 2 を exponent に移します。

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

Integer は `from_int/from_bigint`。Host binary64 自体が source of truth の場合だけ
`from_double` を使用します。

## Binary Context の使用

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

Multi-step では flags を明示 combine し、value とともに保持します。Infinity/NaN はしばしば
flag 付き defined result です。

## Interchange Bits の Decode / Encode

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

Fixed format は host Double を経由しません。Protocol が NaN payload/sign や signed zero を区別する
場合は bit state を保持し、ordinary `compare` を NaN total order として使わないでください。

## Certified Elementary Function

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

Untrusted/large input は `try_*_ctx`。Convenience API も同じ certificate path を使いますが failure
を unrecoverable と扱います。

## Working Precision を意図的に変更

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

`with_precision` は値を変え得るため rounding を明示します。`ulp()` は representation spacing で、
multi-step certified error bound ではありません。

## Special Value を明示処理

Signed zero/NaN constructor と payload observer を使い、NaN 可能時は comparison 前に
`classify()`、status が control flow に影響する場合は context API を使います。

## 推奨事項

1. Algorithm boundary で working precision を一度決める。
2. Interchange decode → one context calculation → one encode。
3. Intermediate flags を捨てない。
4. Untrusted elementary input は `try_*_ctx`。
5. Limb/NTT threshold/target dispatch に依存しない。

## 次に読む

[Design](./design.md)、[Conformance](./conformance.md)、
[`bin_float_checked`](../bin_float_checked/tutorial.md) を参照してください。
