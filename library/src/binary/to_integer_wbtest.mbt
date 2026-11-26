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
// oracle: A
// source: written out from IEEE Std 754-2019 5.8 (convertToInteger rounds in the direction of the context and raises invalid when the result is out of range, convertToIntegerExact also raises inexact when the value changes): 2.5 gives 2 (nearest even), -2.5 gives -2, 3.7 gives 4 and 3 toward zero, -0.3 gives 0, 2^63 is out of range (invalid, no value) and -2^63 fits exactly
// shares: Binary::from_double builds the operands; to_int64_ctx is the code under test; to_integer_show prints the value and flag bits
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
    let value = Binary::from_double(number)
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
// oracle: A
// source: written out from IEEE Std 754-2019 5.8: 2^31 does not fit a 32-bit integer (invalid, no value) while -2^31 does, 4294967295 fits an unsigned 32-bit integer, -0.4 rounds to 0 for the unsigned type, -1 does not fit an unsigned 64-bit integer, a NaN, an infinity and 2^1000000000 are invalid
// shares: Binary::from_double, nan, inf and make build the operands; to_int_ctx, to_uint_ctx and to_uint64_ctx are the code under test; to_integer_any prints the value and flag bits
test "convertToInteger handles every width and special value" {
  let context = BinaryContext::binary64()
  let big = Binary::from_double(2147483648.0)
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
    to_integer_any(Binary::from_double(4294967295.0).to_uint_ctx(context)),
    content=(
      #|4294967295 flags=0
    ),
  )
  inspect(
    to_integer_any(Binary::from_double(-0.4).to_uint_ctx(context)),
    content=(
      #|0 flags=0
    ),
  )
  inspect(
    to_integer_any(Binary::from_double(-1.0).to_uint64_ctx(context)),
    content=(
      #|none flags=16
    ),
  )
  inspect(
    to_integer_any(Binary::nan().to_int_ctx(context)),
    content=(
      #|none flags=16
    ),
  )
  inspect(
    to_integer_any(Binary::inf().to_uint64_ctx(context)),
    content=(
      #|none flags=16
    ),
  )
  let huge = Binary::make(BinCoeff::one(), 1000000000, 53)
  inspect(
    to_integer_any(huge.to_int64_ctx(context)),
    content=(
      #|none flags=16
    ),
  )
}
