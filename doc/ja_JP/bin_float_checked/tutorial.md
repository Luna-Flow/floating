# `bin_float_checked` チュートリアル

`BinFloatResult` は `Result[BinFloat,ArithmeticError]` を fluent pipeline 内に保持します。
First construction/arithmetic error で後続を止める用途で、IEEE flag accumulator ではありません。

## Pipeline の構築

```moonbit check
///|
test "checked binary pipeline" {
  let value =
    @bin_float_checked.BinFloatResult::from_int(81, precision=48)
    .sqrt()
    .div(@bin_float_checked.BinFloatResult::from_int(3, precision=48))
  inspect(value.result().unwrap().to_string(), content="3p0")
}
```

Application boundary まで wrapper を保持し、`is_ok/is_err/error` で分岐、処理時に `result()`。

## First-Error Short-Circuit

Error state の transformation は identity、binary method は left error を優先します。`map` は infallible、
failure を返し得る callback は `bind`。`flat_map` は deprecated です。

## Context Operation は Flags を保持しない

`add_ctx/exp_ctx` は certification/arithmetic error を保持しますが wrapper は value/error のみ。
`BinaryFlags` が contract の場合は raw `BinFloat::*_ctx` tuple を使います。

## 推奨事項

1. First-error pipeline に使い status accumulation に使わない。
2. Binary operand は wrapped のまま。
3. Outer boundary で一度だけ extract。
4. Flags/interchange は raw `bin_float` API。

[Design](./design.md) と [`bin_float` Tutorial](../bin_float/tutorial.md) を参照してください。
