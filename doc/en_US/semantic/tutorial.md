# `semantic` Tutorial

## Compare Representations At A Common Boundary

```moonbit check
///|
test "semantic scalar projection" {
  let binary = @bin_float.BinFloat::from_int(3, precision=32)
  let decimal = @decimal.Decimal::from_int(3, precision=32)
  inspect(
    @semantic.SemanticScalar::from_bin_float(binary) ==
      @semantic.SemanticScalar::from_decimal(decimal),
    content="true",
  )
}
```

Use semantic values in cross-representation tests, protocol boundaries, or
diagnostics. Keep representation-specific precision and formatting behavior on
the original concrete value.
