///|
fn elementary_range_show(result : (Decimal, DecimalFlags)) -> String {
  let (value, flags) = result
  "\{value} overflow=\{flags.overflow} underflow=\{flags.underflow} invalid=\{flags.invalid_operation}"
}

///|
// oracle: A
// source: literal text of the results: exp(+-1E300), exp(+-1E9) at decimal64 -> inf overflow / 0E-398
//   underflow; CPython agrees on all four values and flags (Overflow; Underflow Subnormal Inexact Rounded
//   Clamped)
// shares: Decimal::from_string and to_string (reading the inputs, printing the result)
test "certified results far outside the decimal range stay bounded" {
  let ctx = DecimalContext::decimal64()
  let huge = Decimal::from_string_ctx("1E300", ctx).0
  inspect(
    elementary_range_show(huge.exp_ctx(ctx)),
    content=(
      #|inf overflow=true underflow=false invalid=false
    ),
  )
  inspect(
    elementary_range_show(huge.neg().exp_ctx(ctx)),
    content=(
      #|0E-398 overflow=false underflow=true invalid=false
    ),
  )
  let big = Decimal::from_string_ctx("1E9", ctx).0
  inspect(
    elementary_range_show(big.exp_ctx(ctx)),
    content=(
      #|inf overflow=true underflow=false invalid=false
    ),
  )
  inspect(
    elementary_range_show(big.neg().exp_ctx(ctx)),
    content=(
      #|0E-398 overflow=false underflow=true invalid=false
    ),
  )
}

///|
// oracle: A
// source: literal text: 2**1E300 -> inf overflow, 2**-1E300 and 0.5**1E300 -> 0E-398 underflow; CPython agrees
//   on all three
// shares: Decimal::from_string (reading the inputs)
test "power far outside the decimal range stays bounded" {
  let ctx = DecimalContext::decimal64()
  let huge = Decimal::from_string_ctx("1E300", ctx).0
  let two = Decimal::from_int(2, precision=16)
  let half = Decimal::from_string_ctx("0.5", ctx).0
  inspect(
    elementary_range_show(two.power_ctx(huge, ctx)),
    content=(
      #|inf overflow=true underflow=false invalid=false
    ),
  )
  inspect(
    elementary_range_show(two.power_ctx(huge.neg(), ctx)),
    content=(
      #|0E-398 overflow=false underflow=true invalid=false
    ),
  )
  inspect(
    elementary_range_show(half.power_ctx(huge, ctx)),
    content=(
      #|0E-398 overflow=false underflow=true invalid=false
    ),
  )
}
