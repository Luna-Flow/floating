///|
fn exponent_range_power(exponent : Int) -> BinFloat {
  BinFloat::make(BinCoeff::one(), exponent, 53)
}

///|
fn exponent_range_flags(flags : BinaryFlags) -> String {
  "inexact=\{flags.inexact()} underflow=\{flags.underflow()} overflow=\{flags.overflow()}"
}

///|
test "exact results inside the implementation range are unchanged" {
  let big = exponent_range_power(1000000000)
  inspect(
    big.mul(exponent_range_power(-999999999)).to_string(),
    content=(
      #|1p1
    ),
  )
  inspect(
    exponent_range_power(binary_implementation_e_max).to_string(),
    content=(
      #|1p1073741823
    ),
  )
  inspect(
    exponent_range_power(binary_implementation_e_min - 52).to_string(),
    content=(
      #|1p-1073741875
    ),
  )
}

///|
test "plain operations overflow to infinity instead of saturating" {
  let big = exponent_range_power(2000000000)
  inspect(
    big.to_string(),
    content=(
      #|inf
    ),
  )
  let half_range = exponent_range_power(500000000)
  inspect(
    half_range.mul(half_range).mul(half_range).to_string(),
    content=(
      #|inf
    ),
  )
  let tiny = exponent_range_power(-500000000)
  inspect(
    half_range.div(tiny).div(tiny).to_string(),
    content=(
      #|inf
    ),
  )
  inspect(
    half_range.neg().mul(half_range).mul(half_range).to_string(),
    content=(
      #|-inf
    ),
  )
}

///|
test "plain operations underflow to zero instead of saturating" {
  let tiny = exponent_range_power(-500000000)
  inspect(
    tiny.mul(tiny).to_string(),
    content=(
      #|1p-1000000000
    ),
  )
  inspect(
    tiny.mul(tiny).mul(tiny).to_string(),
    content=(
      #|0
    ),
  )
  inspect(
    tiny.neg().mul(tiny).mul(tiny).to_string(),
    content=(
      #|-0
    ),
  )
  inspect(
    exponent_range_power(-2000000000).to_string(),
    content=(
      #|0
    ),
  )
}

///|
test "plain construction honours the rounding mode at the range limits" {
  let one = BinCoeff::one()
  inspect(
    BinFloat::make(one, 2000000000, 53, mode=RoundingMode::TowardZero).to_string(),
    content=(
      #|9007199254740991p1073741771
    ),
  )
  inspect(
    BinFloat::make(one, -2000000000, 53, mode=RoundingMode::TowardPositive).to_string(),
    content=(
      #|1p-1073741875
    ),
  )
  // Exactly half of the smallest subnormal ties to zero; three quarters rounds up.
  let half_exponent = binary_implementation_e_min - 53
  inspect(
    BinFloat::make(one, half_exponent, 53).to_string(),
    content=(
      #|0
    ),
  )
  inspect(
    BinFloat::make(BinCoeff::from_uint64(3UL), half_exponent - 1, 53).to_string(),
    content=(
      #|1p-1073741875
    ),
  )
}

///|
test "unbounded contexts report overflow and underflow at the range limits" {
  let half_range = exponent_range_power(500000000)
  let square = half_range.mul(half_range)
  let nearest = BinaryContext::unbounded(53)
  let (value, flags) = square.mul_ctx(half_range, nearest)
  inspect(
    value.to_string(),
    content=(
      #|inf
    ),
  )
  inspect(
    exponent_range_flags(flags),
    content=(
      #|inexact=true underflow=false overflow=true
    ),
  )
  let toward_zero = BinaryContext::unbounded(
    53,
    rounding=BinaryRoundingMode::RoundTowardZero,
  )
  let (value, flags) = square.mul_ctx(half_range, toward_zero)
  inspect(
    value.to_string(),
    content=(
      #|9007199254740991p1073741771
    ),
  )
  inspect(
    exponent_range_flags(flags),
    content=(
      #|inexact=true underflow=false overflow=true
    ),
  )
  let tiny = exponent_range_power(-500000000)
  let (value, flags) = tiny.mul(tiny).mul_ctx(tiny, nearest)
  inspect(
    value.to_string(),
    content=(
      #|0
    ),
  )
  inspect(
    exponent_range_flags(flags),
    content=(
      #|inexact=true underflow=true overflow=false
    ),
  )
  let (value, flags) = half_range.div_ctx(tiny.mul(tiny), nearest)
  inspect(
    value.to_string(),
    content=(
      #|inf
    ),
  )
  inspect(
    exponent_range_flags(flags),
    content=(
      #|inexact=true underflow=false overflow=true
    ),
  )
}

///|
test "context precision is limited" {
  inspect(
    BinaryContext::try_new(binary_precision_max + 1) is Err(_),
    content="true",
  )
  inspect(BinaryContext::try_new(binary_precision_max) is Ok(_), content="true")
}
