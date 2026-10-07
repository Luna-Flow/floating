///|
fn to_integer_show(result : (Int64?, BinaryFlags)) -> String {
  let value = match result.0 {
    Some(value) => value.to_string()
    None => "none"
  }
  "\{value} flags=\{result.1.to_testfloat_bits()}"
}

///|
fn[T : Show] to_integer_any(result : (T?, BinaryFlags)) -> String {
  let value = match result.0 {
    Some(value) => value.to_string()
    None => "none"
  }
  "\{value} flags=\{result.1.to_testfloat_bits()}"
}

///|
test "convertToInteger rounds, checks the range, and reports flags" {
  let nearest = BinaryContext::binary64()
  let toward_zero = BinaryContext::binary64(
    rounding=BinaryRoundingMode::RoundTowardZero,
  )
  let lines = StringBuilder()
  for
    number in [
      2.5, -2.5, 3.7, -0.3, 9.2233720368547758e18, -9.2233720368547758e18,
    ] {
    let value = BinFloat::from_double(number)
    lines.write_string(
      "\{number}: \{to_integer_show(value.to_int64_ctx(nearest))} \{to_integer_show(value.to_int64_ctx(nearest, exact=true))} \{to_integer_show(value.to_int64_ctx(toward_zero))}\n",
    )
  }
  inspect(
    lines.to_string(),
    content=(
      #|2.5: 2 flags=0 2 flags=1 2 flags=0
      #|-2.5: -2 flags=0 -2 flags=1 -2 flags=0
      #|3.7: 4 flags=0 4 flags=1 3 flags=0
      #|-0.3: 0 flags=0 0 flags=1 0 flags=0
      #|9223372036854776000: none flags=16 none flags=16 none flags=16
      #|-9223372036854776000: -9223372036854775808 flags=0 -9223372036854775808 flags=0 -9223372036854775808 flags=0
      #|
    ),
  )
}

///|
test "convertToInteger handles every width and special value" {
  let context = BinaryContext::binary64()
  let big = BinFloat::from_double(2147483648.0)
  inspect(
    to_integer_any(big.to_int_ctx(context)),
    content=(
      #|none flags=16
    ),
  )
  inspect(
    to_integer_any(big.neg().to_int_ctx(context)),
    content=(
      #|-2147483648 flags=0
    ),
  )
  inspect(
    to_integer_any(BinFloat::from_double(4294967295.0).to_uint_ctx(context)),
    content=(
      #|4294967295 flags=0
    ),
  )
  inspect(
    to_integer_any(BinFloat::from_double(-0.4).to_uint_ctx(context)),
    content=(
      #|0 flags=0
    ),
  )
  inspect(
    to_integer_any(BinFloat::from_double(-1.0).to_uint64_ctx(context)),
    content=(
      #|none flags=16
    ),
  )
  inspect(
    to_integer_any(BinFloat::nan().to_int_ctx(context)),
    content=(
      #|none flags=16
    ),
  )
  inspect(
    to_integer_any(BinFloat::inf(Sign::Positive).to_uint64_ctx(context)),
    content=(
      #|none flags=16
    ),
  )
  let huge = BinFloat::make(BinCoeff::one(), 1000000000, 53)
  inspect(
    to_integer_any(huge.to_int64_ctx(context)),
    content=(
      #|none flags=16
    ),
  )
}
