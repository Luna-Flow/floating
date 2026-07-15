# `ball_float` チュートリアル

Rounded point ではなく mathematically possible な全 real value を包む必要がある場合に使います。
Bare interval、IEEE 1788 decoration、outward context、certified elementary を提供します。

## Entry Point の選択

| 要件 | 推奨 API |
| --- | --- |
| exact dyadic point | `exact` |
| measured/uncertain range | `from_bounds` / `new` |
| constructor failure as data | `try_from_bounds/try_exact` |
| endpoint limits + flags | `*_ctx` + `BallContext` |
| observable proof failure | `try_*_interval` |
| decoration/NaI | `BallFloatDecorated` |
| first-error composition | `ball_float_checked` |

## Exact Dyadic Point の埋込み

```moonbit check
///|
test "exact dyadic interval" {
  let x = @bin_float.BinFloat::make(
    @bin_float.BinCoeff::from_uint64(3UL),
    -1,
    32,
  )
  let interval = @ball_float.BallFloat::exact(x)
  inspect(interval.is_singleton(), content="true")
  inspect(interval.contains(x), content="true")
}
```

`exact` は supplied `BinFloat` に対して exact。Lower precision 指定時は bounds を outward に丸めます。

## Valid Range の構築

```moonbit check
///|
test "bounded interval" {
  let interval = @ball_float.BallFloat::try_from_bounds(
    @bin_float.BinFloat::from_int(1, precision=32),
    @bin_float.BinFloat::from_int(2, precision=32),
    precision=32,
  ).unwrap()
  inspect(interval.contains_zero(), content="false")
  inspect(interval.width().to_string(), content="1p0")
}
```

Endpoint order/finiteness が untrusted なら `try_from_bounds`。`new(center,radius)` も storage は bounds です。

## Decimal Real を正しく包む

Nearest decimal-to-binary point + `exact` はその point だけを包みます。Original decimal は二方向変換します。

```moonbit check
///|
test "outward decimal embedding" {
  let decimal = @decimal.Decimal::from_string("0.1", precision=20).unwrap()
  let lower = decimal.to_bin_float(
    precision=32,
    mode=@arithmetic.RoundingMode::TowardNegative,
  )
  let upper = decimal.to_bin_float(
    precision=32,
    mode=@arithmetic.RoundingMode::TowardPositive,
  )
  let interval = @ball_float.BallFloat::from_bounds(lower, upper, precision=32)
  inspect(interval.is_empty(), content="false")
  inspect(interval.lower_bound().compare(interval.upper_bound()) <= 0, content="true")
}
```

Representation boundary 後は interval domain 内で計算を続けます。

## Set Relation の読み方

```moonbit check
///|
test "interval relations" {
  let a = @ball_float.BallFloat::from_bounds(
    @bin_float.BinFloat::from_int(9, precision=32),
    @bin_float.BinFloat::from_int(11, precision=32),
  )
  let b = @ball_float.BallFloat::from_bounds(
    @bin_float.BinFloat::from_int(14, precision=32),
    @bin_float.BinFloat::from_int(16, precision=32),
  )
  inspect(a.disjoint(b), content="true")
  inspect(a.definitely_lt(b), content="true")
  inspect(a.overlaps(b), content="false")
}
```

`contains/subset/interior/overlap_state/definitely_lt` など set semantics を使い、scalar sort しません。

## Outward-Rounded Arithmetic

Ordinary `+ - * /` は enclosure を保持。Denominator が interior zero crossing なら Entire、one-sided
zero なら half-infinite。Endpoint precision/exponent/flags が必要なら `BallContext` と `*_ctx`。

## Total / Checked Elementary の選択

```moonbit check
///|
test "certified interval sine" {
  let input = @ball_float.BallFloat::from_bounds(
    @bin_float.BinFloat::zero(precision=64),
    @bin_float.BinFloat::one(precision=64),
  )
  match input.try_sin_interval() {
    Ok(result) => {
      inspect(result.is_empty(), content="false")
      inspect(result.is_bounded(), content="true")
    }
    Err(_) => abort("sine enclosure could not be certified"),
  }
}
```

Proof/resource failure を観測するなら `try_*`、conservative range で続けるなら total API。
Correctness と tightness は別に `is_entire/width` で判定します。

## Domain Quality に Decoration を使用

```moonbit check
///|
test "decorated interval" {
  let bare = @ball_float.BallFloat::from_int(4, precision=32)
  let decorated = @ball_float.BallFloatDecorated::new(
    bare,
    decoration=@ball_float.Decoration::Com,
  )
  let root = decorated.sqrt_interval()
  inspect(root.is_nai(), content="false")
}
```

Domain clipping/discontinuity は decoration を下げます。NaI は invalid decorated operation、Empty は valid set。

## 推奨事項

1. Representation boundary は outward bounds。
2. Intermediate を BallFloat に保ち midpoint だけを抽出しない。
3. Set relations を使う。
4. Error または conservative range を明示選択。
5. Correctness 後に width/Entire を確認。
6. Contract が必要な場合だけ decorated interval。

## 次に読む

[Design](./design.md)、[Conformance](./conformance.md)、
[`ball_float_checked`](../ball_float_checked/tutorial.md) を参照してください。
