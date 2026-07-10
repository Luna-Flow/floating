# `semantic` チュートリアル

## 共通境界で表現を比較する

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

意味値は表現横断テスト、プロトコル境界、診断に適します。precision、quantum、表示動作は元の具体値に保持します。
