# `ball_float_checked` チュートリアル

`BallFloatResult` は `Result[BallFloat,ArithmeticError]` を fluent pipeline に保持します。Invalid bounds、
non-finite exact source、checked elementary proof failure が後続 operation を止めます。

## Construction を一度 Validate

```moonbit check
///|
test "checked interval construction" {
  let x = @ball_float_checked.BallFloatResult::from_bounds(
    @bin_float.BinFloat::from_int(1, precision=32),
    @bin_float.BinFloat::from_int(2, precision=32),
    precision=32,
  )
  let y = @ball_float_checked.BallFloatResult::from_int(3, precision=32)
  let result = (x + y).result().unwrap()
  inspect(result.is_empty(), content="false")
}
```

Later operation は first error を short-circuit。Infallible は `map`、checked callback は `bind`。
`flat_map` は deprecated です。

## Wide Success と Failure の区別

Entire は valid enclosure success。Extract 後に `is_entire/width/boundedness` で application tightness
policy を適用します。`contains/subset/overlaps` は extraction 後の bare interval に呼びます。

## Decoration / Flags は Explicit

Wrapper は bare interval のみで `BallFloatDecorated`/`BallFlags` を保持しません。Decoration、NaI、
inexact/overflow/underflow が contract の場合は raw API を使います。

## 推奨事項

1. Untrusted construction の validation と first error に使う。
2. Entire は correct enclosure として受け、tightness を別判定。
3. Relation/decorated operation 前に一度 extract。
4. Structured certification detail は raw `try_*`。

[Design](./design.md) と [`ball_float` Tutorial](../ball_float/tutorial.md) を参照してください。
