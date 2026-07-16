# `decimal` Tutorial

Use `decimal` when decimal quantum, IEEE-style context/flags, or
decimal32/64/128 DPD/BID interchange is part of the application contract. This
page targets `floating` 0.7.1. Use [`decimal_gda`](../decimal_gda/tutorial.md)
instead when sticky GDA status and traps must be threaded through every step.

## Choose The Right Entry Point

| Need | Recommended API |
| --- | --- |
| parse while preserving decimal quantum | `Decimal::parse` / `from_string` |
| bounded context and operation flags | `from_string_ctx` and `*_ctx` |
| canonical cohort | `normalized()` or `reduce_ctx()` |
| decimal32/64/128 bits | `DecimalInterchange` or `*_interchange_hex` |
| observable elementary proof failure | `try_*_ctx` |
| accumulated IEEE pipeline state | `decimal_checked` |

## Parse Without Losing Quantum

Parsing preserves the input exponent when the coefficient fits the requested
precision. Trailing zeros can therefore carry application meaning.

```moonbit check
///|
test "decimal parsing preserves quantum" {
  let amount = @decimal.Decimal::from_string("12.3400", precision=10).unwrap()
  inspect(amount.to_string(), content="12.3400")
  inspect(amount.quantum(), content="-4")
  let reduced = amount.normalized()
  inspect(reduced.to_string(), content="12.34")
  inspect(reduced.quantum(), content="-2")
}
```

`normalized()` changes the cohort but not the mathematical value. Do not call
it automatically when scale is part of a monetary, measurement, or protocol
record.

Use `parse` when invalid text needs an `ArithmeticError`; use `from_string`
when `None` is sufficient.

## Calculate Exact Decimal Values

Ordinary operators are convenient for unconstrained calculations whose working
precision is already encoded in the operands.

```moonbit check
///|
test "exact decimal arithmetic" {
  let a = @decimal.Decimal::from_string("1.25", precision=20).unwrap()
  let b = @decimal.Decimal::from_string("2.5", precision=20).unwrap()
  inspect((a + b).to_string(), content="3.75")
  inspect((a * b).to_string(), content="3.125")
}
```

For externally specified precision, rounding, or exponent bounds, use context
operations instead of relying on operand precision.

## Use A Context And Preserve Flags

`DecimalContext` is immutable. Each `*_ctx` operation returns a value and flags
raised by that operation.

```moonbit check
///|
test "decimal64 parse and divide" {
  let context = @decimal.DecimalContext::decimal64()
  let (value, parse_flags) = @decimal.Decimal::from_string_ctx(
    "1.234567890123456789",
    context,
  )
  let three = @decimal.Decimal::from_int(3, precision=context.precision())
  let (quotient, divide_flags) = value.div_ctx(three, context)
  let flags = parse_flags.combine(divide_flags)
  inspect(quotient.is_finite(), content="true")
  inspect(flags.contains(@decimal.DecimalSignal::Rounded), content="true")
}
```

Keep combined flags next to the value for the lifetime of the calculation.
`has_error()` is a convenience policy, but applications should inspect
individual signals when inexact, rounded, subnormal, overflow, or clamped
behavior matters.

## Quantize Deliberately

Use `quantize` when the output exponent is part of the contract. The target
quantum is supplied as a `Decimal` value.

```moonbit nocheck
let context = @decimal.DecimalContext::decimal64()
let value = @decimal.Decimal::from_string("12.3456").unwrap()
let cents = @decimal.Decimal::from_string("0.00").unwrap()
let (rounded, flags) = value.quantize(cents, context)
// rounded has quantum -2; inspect Rounded/Inexact before accepting it.
```

`quantize` reports invalid-operation when the requested exponent cannot fit
the context. It does not silently choose another scale.

## Encode Decimal Interchange

Select both format and encoding explicitly when exchanging bits with another
system.

```moonbit check
///|
test "decimal64 DPD round trip" {
  let value = @decimal.Decimal::from_string("1.25").unwrap()
  let (encoded, encode_flags) =
    @decimal.DecimalInterchange::from_decimal_with_encoding(
      value,
      @decimal.DecimalInterchangeFormat::Decimal64,
      @decimal.DecimalInterchangeEncoding::DPD,
    )
  let (decoded, decode_flags) = encoded.to_decimal_ctx()
  inspect(decoded.to_string(), content="1.25")
  inspect(encode_flags.combine(decode_flags).has_error(), content="false")
}
```

Use `BID` only when the external protocol requires it. GDA concrete
interchange lives in `decimal_gda` and is DPD-only; do not move encoded values
between the packages by assuming their contexts are interchangeable.

## Call Certified Elementary Functions

Use `try_*_ctx` at a boundary where certification failure must remain
observable.

```moonbit check
///|
test "certified decimal logarithm" {
  let context = @decimal.DecimalContext::decimal64()
  let ten = @decimal.Decimal::from_int(10, precision=context.precision())
  match ten.try_log10_ctx(context) {
    Ok((value, flags)) => {
      inspect(value.to_string(), content="1")
      inspect(flags.has_error(), content="false")
    }
    Err(_) => abort("decimal log10 could not be certified"),
  }
}
```

The implementation converts the exact decimal to directed dyadic bounds and
accepts a result only when both bounds round to the same decimal value and
flags. Convenience methods such as `log10_ctx` use the same proof path but treat
proof failure as unrecoverable.

## Convert Between Decimal And Binary Carefully

Dyadic values convert exactly to decimal when enough decimal precision is
available. Most finite decimal fractions do not convert exactly to binary.

```moonbit check
///|
test "binary decimal boundary" {
  let exact_binary = @bin_float.BinFloat::make(
    @bin_float.BinCoeff::from_uint64(3UL),
    -2,
    32,
  )
  let exact_decimal = @decimal.Decimal::from_bin_float(exact_binary, precision=20)
  inspect(exact_decimal.to_string(), content="0.75")

  let tenth = @decimal.Decimal::from_string("0.1", precision=20).unwrap()
  let approximate_binary = tenth.to_bin_float(precision=24)
  let back = @decimal.Decimal::from_bin_float(approximate_binary, precision=10)
  inspect(back.to_string(), content="0.09999999404")
}
```

When building an interval around a decimal real value, convert twice with
`TowardNegative` and `TowardPositive` and use both bounds. A nearest-rounded
binary point embedded with `BallFloat::exact` encloses only that binary point,
not necessarily the original decimal.

## Special Values And Ordering

- Signed zero, infinities, quiet/signaling NaNs, and payloads are explicit.
- `compare` is numerical and is not a total representation order over NaNs.
- `compare_total` orders representations, including cohorts and NaNs, for
  deterministic storage/protocol use.
- `same_quantum` tests exponent/cohort compatibility, not numerical equality.
- Classification under a context (`is_normal`/`is_subnormal`) may differ from a
  context-free finite/special classification.

## Recommended Practice

1. Preserve parsed quantum until the application has explicitly chosen to
   normalize or quantize.
2. Use one context through a calculation and combine every returned flag.
3. Treat interchange encoding as an IO boundary; do arithmetic on `Decimal`.
4. Use `try_*_ctx` for elementary functions on untrusted inputs.
5. Use `decimal_checked` for a closed IEEE pipeline; use `decimal_gda` or
   `decimal_gda_checked` for sticky GDA status and traps.

## Next Reading

- [Design](./design.md) explains coefficient dispatch, finalization, and
  certified decimal rounding.
- [Conformance](./conformance.md) defines the IEEE evidence boundary.
- [Performance](./performance.md) records target-specific crossover policy.
- [`decimal_checked` tutorial](../decimal_checked/tutorial.md) shows automatic
  flag accumulation.
