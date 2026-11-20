///|
fn elementary_range_show(result : (BinFloat, BinaryFlags)) -> String {
  let (value, flags) = result
  "\{value} inexact=\{flags.inexact()} underflow=\{flags.underflow()} overflow=\{flags.overflow()} invalid=\{flags.invalid_operation()}"
}

///|
test "exponential functions overflow instead of failing certification" {
  let huge = BinFloat::from_int(1000000000, precision=53)
  let unbounded = BinaryContext::unbounded(53)
  let binary64 = BinaryContext::binary64()
  inspect(
    elementary_range_show(huge.try_exp_ctx(unbounded).unwrap()),
    content=(
      #|inf inexact=true underflow=false overflow=true invalid=false
    ),
  )
  inspect(
    elementary_range_show(huge.try_exp_ctx(binary64).unwrap()),
    content=(
      #|inf inexact=true underflow=false overflow=true invalid=false
    ),
  )
  inspect(
    elementary_range_show(huge.try_exp2_ctx(binary64).unwrap()),
    content=(
      #|inf inexact=true underflow=false overflow=true invalid=false
    ),
  )
  inspect(
    elementary_range_show(huge.try_exp10_ctx(unbounded).unwrap()),
    content=(
      #|inf inexact=true underflow=false overflow=true invalid=false
    ),
  )
  inspect(
    elementary_range_show(huge.try_expm1_ctx(unbounded).unwrap()),
    content=(
      #|inf inexact=true underflow=false overflow=true invalid=false
    ),
  )
  inspect(
    elementary_range_show(huge.try_cosh_ctx(unbounded).unwrap()),
    content=(
      #|inf inexact=true underflow=false overflow=true invalid=false
    ),
  )
  inspect(
    elementary_range_show(huge.neg().try_sinh_ctx(unbounded).unwrap()),
    content=(
      #|-inf inexact=true underflow=false overflow=true invalid=false
    ),
  )
  let toward_zero = BinaryContext::binary64(
    rounding=BinaryRoundingMode::RoundTowardZero,
  )
  inspect(
    elementary_range_show(huge.try_exp_ctx(toward_zero).unwrap()),
    content=(
      #|9007199254740991p971 inexact=true underflow=false overflow=true invalid=false
    ),
  )
}

///|
test "exponential functions underflow instead of failing certification" {
  let huge = BinFloat::from_int(-1000000000, precision=53)
  let unbounded = BinaryContext::unbounded(53)
  inspect(
    elementary_range_show(huge.try_exp_ctx(unbounded).unwrap()),
    content=(
      #|0 inexact=true underflow=true overflow=false invalid=false
    ),
  )
  inspect(
    elementary_range_show(huge.try_exp2_ctx(BinaryContext::binary64()).unwrap()),
    content=(
      #|0 inexact=true underflow=true overflow=false invalid=false
    ),
  )
  inspect(
    elementary_range_show(huge.try_exp10_ctx(unbounded).unwrap()),
    content=(
      #|0 inexact=true underflow=true overflow=false invalid=false
    ),
  )
  inspect(
    elementary_range_show(huge.try_expm1_ctx(unbounded).unwrap()),
    content=(
      #|-1p0 inexact=true underflow=false overflow=false invalid=false
    ),
  )
  let upward = BinaryContext::binary64(
    rounding=BinaryRoundingMode::RoundTowardPositive,
  )
  inspect(
    elementary_range_show(huge.try_exp_ctx(upward).unwrap()),
    content=(
      #|1p-1074 inexact=true underflow=true overflow=false invalid=false
    ),
  )
}

///|
test "binary64 exp keeps its exact overflow threshold" {
  let binary64 = BinaryContext::binary64()
  let below = BinFloat::from_double(709.78)
  let above = BinFloat::from_double(709.79)
  inspect(
    elementary_range_show(below.exp_ctx(binary64)),
    content=(
      #|2245699199767725p973 inexact=true underflow=false overflow=false invalid=false
    ),
  )
  inspect(
    elementary_range_show(above.exp_ctx(binary64)),
    content=(
      #|inf inexact=true underflow=false overflow=true invalid=false
    ),
  )
  let tiny = BinFloat::from_double(-745.2)
  inspect(
    elementary_range_show(tiny.exp_ctx(binary64)),
    content=(
      #|0 inexact=true underflow=true overflow=false invalid=false
    ),
  )
}

///|
test "non-try elementary APIs return NaN with invalid on failure" {
  let failure : Result[(BinFloat, BinaryFlags), @def.ArithmeticError] = Err(
    binary_refinement_failure_state("exp", BinaryContext::binary64(), 64, 12),
  )
  inspect(
    elementary_range_show(
      binary_defined_or_nan(failure, BinaryContext::binary64()),
    ),
    content=(
      #|nan inexact=false underflow=false overflow=false invalid=true
    ),
  )
}

///|
test "expm1 saturation agrees with the general path at its threshold" {
  // The shortcut starts at -(53 + 3) ln 2 ~= -38.8 for binary64.
  let toward_zero = BinaryContext::binary64(
    rounding=BinaryRoundingMode::RoundTowardZero,
  )
  let nearest = BinaryContext::binary64()
  let lines = StringBuilder()
  for value in [-38, -39, -40] {
    let x = BinFloat::from_int(value, precision=53)
    let near = x.try_expm1_ctx(nearest).unwrap()
    let zero = x.try_expm1_ctx(toward_zero).unwrap()
    lines.write_string("\{value}: \{near.0} \{zero.0} \{near.1.inexact()}\n")
  }
  inspect(
    lines.to_string(),
    content=(
      #|-38: -1p0 -9007199254740991p-53 true
      #|-39: -1p0 -9007199254740991p-53 true
      #|-40: -1p0 -9007199254740991p-53 true
      #|
    ),
  )
}
