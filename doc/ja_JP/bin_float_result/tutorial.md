# `bin_float_result` チュートリアル

## checked パイプライン

```moonbit check
///|
test "checked binary pipeline" {
  let value = @bin_float_result.BinFloatResult::from_int(81, precision=48)
    .sqrt()
    .div(@bin_float_result.BinFloatResult::from_int(3, precision=48))
  inspect(value.result().unwrap().to_string(), content="3p0")
}
```

呼び出し側が `ArithmeticError` を扱う地点まで wrapper を保ちます。失敗しない変換には `map`、コールバックが失敗し得る場合は `bind` を使います。
