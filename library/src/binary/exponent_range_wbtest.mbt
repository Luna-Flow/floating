///|
fn exponent_range_power(exponent : Int32) -> Binary {
  Binary::make(BinCoeff::one(), exponent, 53)
}

///|
fn exponent_range_flags(flags : BinaryFlags) -> String {
  "inexact=\{flags.inexact()} underflow=\{flags.underflow()} overflow=\{flags.overflow()}"
}

///|
// oracle: A
// source: written out: 2^1000000000 * 2^-999999999 = 2^1 (1p1), the largest exponent 1p1073741823 and the smallest subnormal 1p-1073741874 stay exact; the implementation limits written in the expected strings: e_max = 2^30 - 1 = 1073741823 and e_min = -1073741822 (the limits of the rows of arith_rows_wbtest.mbt and round_rows_wbtest.mbt), the smallest subnormal 2^(e_min - 52) = 1p-1073741874
// shares: Binary::make builds the operands; Binary::to_string and the flag accessors print the result; binary_value_e_max and binary_value_e_min are inputs, exponent_range_power builds 2^e with Binary::make
test "exact results inside the implementation range are unchanged" {
  let big = exponent_range_power(1000000000)
  inspect(
    big.mul(exponent_range_power(-999999999)).to_string(),
    content=(
      #|1p1
    ),
  )
  inspect(
    exponent_range_power(binary_value_e_max).to_string(),
    content=(
      #|1p1073741823
    ),
  )
  inspect(
    exponent_range_power(binary_value_e_min - 52).to_string(),
    content=(
      #|1p-1073741874
    ),
  )
}

///|
// oracle: A
// source: written out from IEEE Std 754-2019 7.4 (a result beyond the largest finite value of the format becomes infinity in round to nearest): 2^2000000000, (2^500000000)^3 and 2^500000000 / (2^-500000000)^2 exceed 2^1073741823, the sign follows the operands; the implementation limits written in the expected strings: e_max = 2^30 - 1 = 1073741823 and e_min = -1073741822 (the limits of the rows of arith_rows_wbtest.mbt and round_rows_wbtest.mbt), the smallest subnormal 2^(e_min - 52) = 1p-1073741874
// shares: Binary::make builds the operands; Binary::to_string and the flag accessors print the result; mul, div and neg are the code under test; exponent_range_power builds 2^e
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
// oracle: A
// source: written out from IEEE Std 754-2019 7.4 and 4.3 (a result below half of the smallest subnormal rounds to zero of the sign of the result): (2^-500000000)^2 = 1p-1000000000 is exact, (2^-500000000)^3 and 2^-2000000000 round to 0, with the sign of the product for the negative case; the implementation limits written in the expected strings: e_max = 2^30 - 1 = 1073741823 and e_min = -1073741822 (the limits of the rows of arith_rows_wbtest.mbt and round_rows_wbtest.mbt), the smallest subnormal 2^(e_min - 52) = 1p-1073741874
// shares: Binary::make builds the operands; Binary::to_string and the flag accessors print the result; mul and neg are the code under test; exponent_range_power builds 2^e
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
// oracle: A
// source: written out from IEEE Std 754-2019 7.4 and 4.3: 2^2000000000 rounded toward zero is the largest finite value (2^53 - 1) * 2^1073741771 at precision 53, 2^-2000000000 rounded toward positive infinity is the smallest subnormal 1p-1073741874, half of the smallest subnormal ties to even (0) and three quarters round up to it; the implementation limits written in the expected strings: e_max = 2^30 - 1 = 1073741823 and e_min = -1073741822 (the limits of the rows of arith_rows_wbtest.mbt and round_rows_wbtest.mbt), the smallest subnormal 2^(e_min - 52) = 1p-1073741874
// shares: Binary::make with the rounding mode is the code under test; Binary::to_string prints the result; BinCoeff::from_uint64 and binary_value_e_min build the operands
test "plain construction honours the rounding mode at the range limits" {
  let one = BinCoeff::one()
  inspect(
    Binary::make(one, 2000000000, 53, mode=BinaryRoundingMode::RoundTowardZero).to_string(),
    content=(
      #|9007199254740991p1073741771
    ),
  )
  inspect(
    Binary::make(
      one,
      -2000000000,
      53,
      mode=BinaryRoundingMode::RoundTowardPositive,
    ).to_string(),
    content=(
      #|1p-1073741874
    ),
  )
  // Exactly half of the smallest subnormal ties to zero; three quarters rounds up.
  let half_exponent = binary_value_e_min - 53
  inspect(
    Binary::make(one, half_exponent, 53).to_string(),
    content=(
      #|0
    ),
  )
  inspect(
    Binary::make(BinCoeff::from_uint64(3UL), half_exponent - 1, 53).to_string(),
    content=(
      #|1p-1073741874
    ),
  )
}

///|
// oracle: A
// source: written out from IEEE Std 754-2019 7.4 and 7.5: overflow (inexact and overflow flags, infinity in nearest, the largest finite value 9007199254740991p1073741771 toward zero), underflow of a tiny result to 0 (inexact and underflow flags) and the overflow of 2^500000000 / 2^-1000000000; the implementation limits written in the expected strings: e_max = 2^30 - 1 = 1073741823 and e_min = -1073741822 (the limits of the rows of arith_rows_wbtest.mbt and round_rows_wbtest.mbt), the smallest subnormal 2^(e_min - 52) = 1p-1073741874
// shares: Binary::make builds the operands; Binary::to_string and the flag accessors print the result; mul_ctx and div_ctx are the code under test (level A in the range limits through arith_rows_wbtest.mbt); exponent_range_flags prints the flags
test "unbounded contexts report overflow and underflow at the range limits" {
  let half_range = exponent_range_power(500000000)
  let square = half_range.mul(half_range)
  let nearest = BinaryContext::new(precision=53)
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
  let toward_zero = BinaryContext::new(
    precision=53,
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
// oracle: S
// source: the written contract of BinaryContext::try_new: the precision limit binary_precision_max is accepted and the next value is refused; the limit itself is the constant of the implementation, so only the two sides of the boundary are stated
// shares: BinaryContext::try_new (the code under test) and the constant binary_precision_max
test "context precision is limited" {
  inspect(
    BinaryContext::try_new(precision=binary_precision_max + 1) is Err(_),
    content="true",
  )
  inspect(
    BinaryContext::try_new(precision=binary_precision_max) is Ok(_),
    content="true",
  )
}
