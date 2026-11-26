///|
fn elementary_range_show(result : (Binary, BinaryFlags)) -> String {
  let (value, flags) = result
  "\{value} inexact=\{flags.inexact()} underflow=\{flags.underflow()} overflow=\{flags.overflow()} invalid=\{flags.invalid_operation()}"
}

///|
// oracle: A
// source: written out from IEEE Std 754-2019 7.4 and the mathematics: exp(10^9) = 2^(1.44 * 10^9), exp2, exp10, expm1, cosh and sinh(-10^9) are beyond 2^1073741823 and beyond the binary64 range, so the result is an infinity of the sign of the function (inexact and overflow) in round to nearest and (2^53 - 1) 2^971 (the largest finite binary64 value) toward zero
// shares: elementary_range_show prints value and flags (Display of Binary and the flag accessors); the try_*_ctx functions are the code under test; Binary::from_int builds the operands
test "exponential functions overflow instead of failing certification" {
  let huge = Binary::from_int(1000000000, precision=53)
  let unbounded = BinaryContext::new(precision=53)
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
// oracle: A
// source: written out from IEEE Std 754-2019 7.4 and 7.5 and the mathematics: exp(-10^9), exp2 and exp10 of -10^9 are below half of the smallest subnormal, so they round to 0 with inexact and underflow; expm1(-10^9) = -1 + 2^-(1.44 * 10^9) rounds to -1 (inexact, no underflow); exp(-10^9) toward positive infinity in binary64 is the smallest subnormal 1p-1074 with underflow
// shares: elementary_range_show prints value and flags; the try_*_ctx functions are the code under test; Binary::from_int builds the operands
test "exponential functions underflow instead of failing certification" {
  let huge = Binary::from_int(-1000000000, precision=53)
  let unbounded = BinaryContext::new(precision=53)
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
// oracle: A
// source: Python decimal at 80 digits on the exact binary64 values of the arguments (library-ran: no): exp(709.78) = 1.79282279439451562e308 whose nearest binary64 value is 2245699199767725 * 2^973 (0.104 of a unit away), exp(709.79) = 1.8108e308 is above the largest finite value plus half a unit (ln of it is 709.78271), exp(-745.2) = 2.31e-324 is below half of the smallest subnormal 2^-1075 = 2.47e-324; the flags follow IEEE Std 754-2019 7.4 and 7.5
// shares: Binary::from_double builds the arguments; exp_ctx is the code under test; elementary_range_show prints value and flags
test "binary64 exp keeps its exact overflow threshold" {
  let binary64 = BinaryContext::binary64()
  let below = Binary::from_double(709.78)
  let above = Binary::from_double(709.79)
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
  let tiny = Binary::from_double(-745.2)
  inspect(
    elementary_range_show(tiny.exp_ctx(binary64)),
    content=(
      #|0 inexact=true underflow=true overflow=false invalid=false
    ),
  )
}

///|
// oracle: A
// source: the written rule of the library for a failed certification (a rule of this library, not of the standard): the non-try form returns a quiet NaN with not_computed and no other flag, and in particular not invalid_operation; the failure is an injected Err value, so no computed value is involved
// shares: binary_defined_or_nan (the code under test) and binary_refinement_failure_state (builds the Err); elementary_range_show prints the result
test "non-try elementary APIs return NaN with not_computed on failure" {
  let failure : Result[(Binary, BinaryFlags), @def.ArithmeticError] = Err(
    binary_refinement_failure_state("exp", BinaryContext::binary64(), 64, 12),
  )
  let result = binary_defined_or_nan(failure, BinaryContext::binary64())
  // S4: a certification failure is not an invalid operation
  inspect(
    elementary_range_show(result),
    content=(
      #|nan inexact=false underflow=false overflow=false invalid=false
    ),
  )
  assert_true(result.1.not_computed())
}

///|
// oracle: A
// source: Python decimal at 80 digits: 1 - exp(-38) = 3.1e-17, 1 - exp(-39) = 1.2e-17 and 1 - exp(-40) = 4.2e-18 are all below half of the spacing below 1 in binary64 (2^-54 = 5.55e-17), so expm1 rounds to -1 to nearest and to -(1 - 2^-53) = -9007199254740991p-53 toward zero, inexact (library-ran: no); the two sides of the saturation threshold -(53 + 3) ln 2 = -38.8 are the arguments -38 and -39
// shares: try_expm1_ctx is the code under test; Binary::from_int builds the arguments; the lines are written by the test from Display of Binary and the inexact accessor
test "expm1 saturation agrees with the general path at its threshold" {
  // The shortcut starts at -(53 + 3) ln 2 ~= -38.8 for binary64.
  let toward_zero = BinaryContext::binary64(
    rounding=BinaryRoundingMode::RoundTowardZero,
  )
  let nearest = BinaryContext::binary64()
  let lines = StringBuilder()
  for value in [-38, -39, -40] {
    let x = Binary::from_int(value, precision=53)
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
