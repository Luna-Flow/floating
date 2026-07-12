///|
fn binary_test_coefficient(value : BigInt) -> @bin_float.BinCoeff {
  let magnitude = if value < 0N { -value } else { value }
  @bin_float.BinCoeff::parse(magnitude.to_string()).unwrap()
}

///|
fn binary_test_make(
  value : BigInt,
  exponent2 : Int,
  precision : Int,
) -> @bin_float.BinFloat {
  @bin_float.BinFloat::make(
    binary_test_coefficient(value),
    exponent2,
    precision,
    negative=value < 0N,
  )
}

///|
fn binary_test_signed_bigint(value : @bin_float.BinFloat) -> BigInt {
  let magnitude = BigInt::from_string(value.coefficient().to_string())
  if value.is_negative() {
    -magnitude
  } else {
    magnitude
  }
}
