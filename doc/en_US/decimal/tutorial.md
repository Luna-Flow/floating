# `decimal` Tutorial

This page tracks the current repository implementation and is written as the `0.4.0` tutorial baseline.

## Parsing Decimal Strings

`Decimal` is the right package when the source of truth is textual decimal data.

```moonbit
let amount = @decimal.Decimal::from_string("12.3400", precision=32).unwrap()
inspect(amount.to_string(), content="12.34")
```

The stored value is normalized, so trailing decimal zeros are removed from the canonical representation.

## Exact Decimal Arithmetic

```moonbit
let a = @decimal.Decimal::from_string("1.25", precision=20).unwrap()
let b = @decimal.Decimal::from_string("2.5", precision=20).unwrap()
inspect((a + b).to_string(), content="3.75")
inspect((a * b).to_string(), content="3.125")
```

## Retuning Precision

Like `BinFloat`, each `Decimal` stores a working precision:

```moonbit
let x = @decimal.Decimal::from_string("12345.6789", precision=20).unwrap()
let short = x.with_precision(5, @def.RoundingMode::ToNearestEven)
```

Use this when you want the decimal representation itself to be rounded to a smaller working precision.

## Converting to Binary

```moonbit
let d = @decimal.Decimal::from_string("0.1", precision=20).unwrap()
let x = d.to_bin_float(precision=24)
let back = @decimal.Decimal::from_bin_float(x, precision=10)
inspect(back.to_string(), content="0.09999999404")
```

This demonstrates an important current semantic point: non-dyadic decimals are only approximated when converted to binary.

## Converting from Binary

```moonbit
let x = @bin_float.BinFloat::make(3N, -2, 32)
let d = @decimal.Decimal::from_bin_float(x, precision=20)
inspect(d.to_string(), content="0.75")
```
