///|
fn elementary_range_show(result : (Decimal, DecimalFlags)) -> String {
  let (value, flags) = result
  "\{value} overflow=\{flags.contains(Overflow)} underflow=\{flags.contains(Underflow)} invalid=\{flags.contains(InvalidOperation)}"
}

///|
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
test "hyperbolic functions overflow without expanding huge endpoints" {
  let ctx = DecimalContext::decimal64()
  let huge = Decimal::from_string_ctx("1E300", ctx).0
  inspect(
    elementary_range_show(huge.sinh_ctx(ctx)),
    content=(
      #|inf overflow=true underflow=false invalid=false
    ),
  )
  inspect(
    elementary_range_show(huge.neg().sinh_ctx(ctx)),
    content=(
      #|-inf overflow=true underflow=false invalid=false
    ),
  )
  inspect(
    elementary_range_show(huge.cosh_ctx(ctx)),
    content=(
      #|inf overflow=true underflow=false invalid=false
    ),
  )
  inspect(
    elementary_range_show(huge.exp2_ctx(ctx)),
    content=(
      #|inf overflow=true underflow=false invalid=false
    ),
  )
  inspect(
    elementary_range_show(huge.neg().exp2_ctx(ctx)),
    content=(
      #|0E-398 overflow=false underflow=true invalid=false
    ),
  )
  let two = Decimal::from_int(2, precision=16)
  inspect(
    elementary_range_show(two.power_ctx(huge, ctx)),
    content=(
      #|inf overflow=true underflow=false invalid=false
    ),
  )
}
