# `decimal_result` チュートリアル

## 解析して計算する

```moonbit check
///|
test "checked decimal pipeline" {
  let result = @decimal_result.DecimalResult::parse("2.25", precision=40)
    .sqrt()
    .mul(@decimal_result.DecimalResult::from_int(2, precision=40))
  inspect(result.result().unwrap().to_string(), content="3.0")
}
```

通常の checked スカラーパイプラインには `DecimalResult` を使います。丸め flags、指数境界、GDA condition が結果の一部なら `Decimal::*_ctx` を直接使います。
