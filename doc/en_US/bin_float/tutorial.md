# `bin_float` Tutorial

Use `bin_float` when values are naturally dyadic, when precision must exceed a
host `Float`/`Double`, or when binary16/32/64/128 rounding and status are part of
the result. This tutorial targets `floating` 0.7.0; see [API](./api.md) for the
complete inventory and [Conformance](./conformance.md) for the verified IEEE
boundary.

## Choose The Right Entry Point

| Need | Recommended API |
| --- | --- |
| exact arbitrary-precision dyadic work | ordinary `BinFloat` constructors and methods |
| fixed precision/exponent/rounding with flags | `*_ctx` + `BinaryContext` |
| binary16/32/64/128 bits | `BinaryInterchange` |
| observable elementary certification failure | `try_*_ctx` |
| short-circuit checked composition | `bin_float_checked` |

## Construct Exact Dyadic Values

`BinFloat::make` receives a non-negative coefficient, a power-of-two exponent,
and a working precision. The sign is a separate argument.

```moonbit check
///|
test "construct an exact dyadic" {
  let x = @bin_float.BinFloat::make(
    @bin_float.BinCoeff::from_uint64(3UL),
    -1,
    32,
  )
  inspect(x.to_string(), content="3p-1")
  inspect(x.to_double(), content="1.5")
}
```

Normalization removes powers of two from a nonzero coefficient:

```moonbit check
///|
test "binary normalization" {
  let x = @bin_float.BinFloat::make(
    @bin_float.BinCoeff::from_uint64(12UL),
    0,
    32,
  )
  inspect(x.coefficient().to_string(), content="3")
  inspect(x.exponent2(), content="2")
}
```

Use `from_int`/`from_bigint` for integers. Use `from_double` only when the host
binary64 value itself is the source of truth; it cannot recover a decimal value
that was rounded before the call.

## Use A Binary Context

Ordinary operators use the values' working precision. Use a `BinaryContext`
when a specific interchange-style format, rounding direction, exponent range,
or tininess rule is required.

```moonbit check
///|
test "binary16 contextual addition" {
  let format = @bin_float.BinaryInterchangeFormat::Binary16
  let context = @bin_float.BinaryContext::binary16(
    rounding=@bin_float.BinaryRoundingMode::RoundTiesToEven,
    tininess=@bin_float.TininessDetection::AfterRounding,
  )
  let x = @bin_float.BinaryInterchange::from_hex("3C00", format)
    .unwrap()
    .to_bin_float()
  let y = @bin_float.BinaryInterchange::from_hex("4000", format)
    .unwrap()
    .to_bin_float()
  let (sum, arithmetic_flags) = x.add_ctx(y, context)
  let (bits, encoding_flags) = sum.to_interchange(format)
  inspect(bits.to_hex(), content="4200")
  inspect(
    arithmetic_flags.combine(encoding_flags).to_testfloat_bits(),
    content="0",
  )
}
```

Keep the value and flags together until the application has applied its status
policy. For a multi-step calculation, combine flags explicitly:

```moonbit nocheck
let (product, mul_flags) = x.mul_ctx(y, context)
let (quotient, div_flags) = product.div_ctx(z, context)
let all_flags = mul_flags.combine(div_flags)
```

Do not assume that an infinity or NaN means there is no result. IEEE operations
often return a defined special value and a flag such as division-by-zero or
invalid-operation.

## Decode And Encode Interchange Bits

Use `BinaryInterchange` for protocol or file bits. Do not decode binary16,
binary32, or binary128 through a host `Double`.

```moonbit check
///|
test "binary32 round trip" {
  let format = @bin_float.BinaryInterchangeFormat::Binary32
  let encoded = @bin_float.BinaryInterchange::from_hex("3F800000", format)
    .unwrap()
  let value = encoded.to_bin_float()
  let (round_trip, flags) = value.to_interchange(format)
  inspect(round_trip.to_hex(), content="3F800000")
  inspect(flags.to_testfloat_bits(), content="0")
}
```

For NaNs, inspect class, signaling state, sign, and payload according to the
application's protocol. Ordinary `compare` is not a total order over NaNs.

## Call Certified Elementary Functions

The `try_*_ctx` family exposes certification failure instead of aborting. This
is the recommended boundary when input size or range is untrusted.

```moonbit check
///|
test "certified binary exponential" {
  let context = @bin_float.BinaryContext::binary64()
  let one = @bin_float.BinFloat::one(precision=53)
  match one.try_exp_ctx(context) {
    Ok((value, flags)) => {
      inspect(value.is_finite(), content="true")
      inspect(flags.invalid_operation(), content="false")
    }
    Err(error) => {
      // A caller can inspect error.certification_failure_detail() here.
      ignore(error)
      abort("binary exp could not be certified")
    }
  }
}
```

Use `exp_ctx`, `sin_ctx`, and similar convenience methods only when a
certification failure is considered unrecoverable. Both families execute the
same certified enclosure/refinement algorithm; the difference is error policy.

## Retune Working Precision Deliberately

`with_precision` changes the represented value if discarded bits are nonzero.
Always state the rounding direction at this boundary.

```moonbit check
///|
test "retune binary precision" {
  let x = @bin_float.BinFloat::make(
    @bin_float.BinCoeff::from_uint64(7UL),
    -2,
    32,
  )
  let short = x.with_precision(2, @arithmetic.RoundingMode::ToNearestEven)
  inspect(short.to_string(), content="7p-2")
}
```

`ulp()` reports spacing for the current finite representation. It is useful for
representation analysis, but it is not a certified error bound for a sequence
of operations.

## Handle Special Values Explicitly

- Construct signed zero with `zero` / `negative_zero`.
- Construct NaNs with `quiet_nan` / `signaling_nan` and inspect `nan_payload`.
- Use `classify()` before an ordered comparison when NaN is possible.
- Use contextual operations when invalid, overflow, underflow, or inexact status
  affects control flow.
- Preserve interchange bits when a protocol distinguishes NaN payloads or
  signed zero.

## Recommended Practice

1. Pick one working precision at the algorithm boundary; avoid repeatedly
   shrinking and expanding values.
2. Decode fixed formats with `BinaryInterchange`, calculate with one explicit
   `BinaryContext`, and encode once at the output boundary.
3. Accumulate flags beside the value rather than discarding them after each
   operation.
4. Prefer `try_*_ctx` for elementary functions over untrusted or very large
   inputs.
5. Do not depend on coefficient limb layout, NTT thresholds, or target-specific
   dispatch; those are intentionally private.

## Next Reading

- [Design](./design.md) explains exact kernels, certified rounding, and tuning
  boundaries.
- [Conformance](./conformance.md) lists the exact TestFloat/MPFR evidence.
- [`bin_float_checked` tutorial](../bin_float_checked/tutorial.md) shows a
  closed `Result` pipeline when first-error short-circuiting is desired.
