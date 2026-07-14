# Executable documentation examples

This test-only package is the canonical executable source for the public
numeric workflows shown in the localized tutorials.

```moonbit check
///|
test "binary context and interchange" {
  let value = @bin_float.BinFloat::make(
    @bin_float.BinCoeff::from_uint64(3UL),
    -1,
    53,
  )
  let context = @bin_float.BinaryContext::binary64()
  let (rounded, flags) = value.add_ctx(value, context)
  inspect(rounded.to_hex(), content="0x3p0")
  inspect(flags.inexact(), content="false")
  let (encoded, _) = rounded.to_interchange(@bin_float.Binary64)
  inspect(encoded.to_hex(), content="4008000000000000")
}
```

```moonbit check
///|
test "GDA context threads sticky status" {
  let context = @decimal_gda.GdaContext::decimal64()
  let parsed = @decimal_gda.parse("12.3400", context)
  inspect(parsed.value().to_string(), content="12.3400")
  let divided = @decimal_gda.divide(
    parsed.value(),
    @decimal_gda.Decimal::from_string("2").unwrap(),
    parsed.next_context(),
  )
  inspect(divided.value().to_string(), content="6.1700")
  inspect(
    divided.next_context().status().contains(@decimal_gda.GdaSignal::Inexact),
    content="false",
  )
}
```

```moonbit check
///|
test "decimal context preserves explicit status" {
  let context = @decimal.DecimalContext::decimal64()
  let (value, parse_flags) = @decimal.Decimal::from_string_ctx(
    "12.3400", context,
  )
  let (result, arithmetic_flags) = value.div_ctx(
    @decimal.Decimal::from_int(2),
    context,
  )
  inspect(parse_flags.has_error(), content="false")
  inspect(arithmetic_flags.has_error(), content="false")
  inspect(result.to_string(), content="6.1700")
}
```

```moonbit check
///|
test "interval and decorated semantics" {
  let interval = @ball_float.BallFloat::from_bounds(
    @bin_float.BinFloat::from_int(1),
    @bin_float.BinFloat::from_int(2),
  )
  inspect(interval.contains(@bin_float.BinFloat::from_int(1)), content="true")
  let decorated = @ball_float.BallFloatDecorated::new(interval)
  inspect(decorated.is_nai(), content="false")
}
```

```moonbit check
///|
test "checked pipelines preserve their domain state" {
  let binary = @bin_float_checked.BinFloatResult::from_int(9).sqrt()
  inspect(binary.result().unwrap().to_string(), content="3p0")
  let decimal = @decimal_checked.DecimalChecked::parse(
    "9",
    @decimal.DecimalContext::decimal64(),
  ).sqrt()
  inspect(decimal.value().to_string(), content="3")
  inspect(decimal.flags().has_error(), content="false")
  let gda = @decimal_gda_checked.GdaDecimalChecked::parse(
    "9",
    @decimal_gda.GdaContext::decimal64(),
  ).sqrt()
  inspect(gda.value().to_string(), content="3")
  inspect(gda.is_trapped(), content="false")
  let interval = @ball_float_checked.BallFloatResult::from_int(4).pow_int(-1)
  inspect(interval.result() is Ok(_), content="true")
}
```

```moonbit check
///|
test "semantic projection compares mathematical values" {
  let binary = @bin_float.BinFloat::from_int(3, precision=32)
  let decimal = @decimal.Decimal::from_int(3, precision=32)
  inspect(
    @semantic.SemanticScalar::from_bin_float(binary) ==
    @semantic.SemanticScalar::from_decimal(decimal),
    content="true",
  )
}
```

```moonbit check
///|
test "numeric expression delegates semantics to callbacks" {
  let expression = @numeric_expr.Expr::invoke(
    @numeric_expr.Operation::new("add"),
    [
      @numeric_expr.Expr::literal(@numeric_expr.Literal::new("2")),
      @numeric_expr.Expr::literal(@numeric_expr.Literal::new("3")),
    ],
  )
  let result = @numeric_expr.evaluate(
    expression,
    fn(literal) {
      match literal.raw() {
        "2" => Ok(2)
        "3" => Ok(3)
        _ => Err("unexpected literal")
      }
    },
    fn(operation, arguments) {
      match (operation.name(), arguments) {
        ("add", [left, right]) => Ok(left + right)
        _ => Err("unexpected operation")
      }
    },
  )
  match result {
    Ok(value) => inspect(value, content="5")
    Err(_) => fail("expected callback evaluation to succeed")
  }
}
```

```moonbit check
///|
test "GDA frontend executes an inline document" {
  let source =
    #|precision: 9
    #|a1 add 1.20 2 -> 3.20
    #|
  let document = @gda_expr.parse_dectest("inline.decTest", source).unwrap()
  let summary = @gda_expr.execute_documents([document])
  assert_eq(summary.executable_cases(), 1)
  assert_eq(summary.passed_cases(), 1)
}
```

```moonbit check
///|
test "ITL frontend preserves set semantics" {
  let source =
    #|testcase minimal {
    #|  intersection [1.0,3.0] [2.0,4.0] = [2.0,3.0];
    #|}
  let cases = @itl_expr.parse_itl(source).unwrap()
  let result = @itl_expr.execute_case(cases[0])
  inspect(result.passed(), content="true")
}
```

```moonbit check
///|
test "MPFR frontend checks a pinned sqrt row" {
  let source = "53 53 n 0x0p0 0x0p0\n"
  let document = @mpfr_expr.parse_sqrt_data("inline.sqrt", source).unwrap()
  let summary = @mpfr_expr.execute_sqrt_data(document)
  assert_eq(summary.total_cases(), 1)
  assert_eq(summary.passed_cases(), 1)
}
```

```moonbit check
///|
test "TestFloat frontend checks value and flags" {
  let spec = @testfloat_expr.TestFloatSpec::parse("f16_mul", "rnear_even").unwrap()
  let document = @testfloat_expr.parse_testfloat(
    "inline.testfloat", "3C00 3C00 3C00 00\n", spec,
  ).unwrap()
  let summary = @testfloat_expr.execute_document(document)
  assert_eq(summary.total_cases(), 1)
  assert_eq(summary.passed_cases(), 1)
}
```
