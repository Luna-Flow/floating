///|
fn elementary_range_show(result : (Decimal, DecimalFlags)) -> String {
  let (value, flags) = result
  "\{value} overflow=\{flags.overflow()} underflow=\{flags.underflow()} invalid=\{flags.invalid_operation()}"
}

///|
// oracle: A
// source: arithmetic and IEEE 754-2019 7.4, 7.5: e^(1E300) and e^(1E9) exceed the largest decimal64 number (9.99E+384), so the result is infinity with overflow (to nearest); e^(-1E300) and e^(-1E9) are below half of the least subnormal 1E-398, so 0E-398 with underflow; written out
// shares: Decimal::from_string_ctx (builds the operand), elementary_range_show (prints value and flags: Decimal::to_string), exp_ctx, sinh_ctx, cosh_ctx, exp2_ctx and pow_ctx (the code under test)
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
// source: arithmetic and IEEE 754-2019 7.4, 7.5: sinh(+-1E300) is +-infinity and cosh(1E300), exp2(1E300) and 2^(1E300) are +infinity, each with overflow (to nearest); exp2(-1E300) is below half of the least subnormal and gives 0E-398 with underflow; written out
// shares: Decimal::from_string_ctx (builds the operand), elementary_range_show (prints value and flags: Decimal::to_string), exp_ctx, sinh_ctx, cosh_ctx, exp2_ctx and pow_ctx (the code under test)
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
    elementary_range_show(two.pow_ctx(huge, ctx)),
    content=(
      #|inf overflow=true underflow=false invalid=false
    ),
  )
}
