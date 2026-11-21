///|
fn binary_test_coefficient(value : BigInt) -> @binary.BinCoeff {
  let magnitude = if value < 0N { -value } else { value }
  @binary.BinCoeff::parse(magnitude.to_string()).unwrap()
}

///|
fn binary_test_make(
  value : BigInt,
  exponent2 : Int32,
  precision : Int32,
) -> @binary.Binary {
  @binary.Binary::make(
    binary_test_coefficient(value),
    exponent2,
    precision,
    negative=value < 0N,
  )
}

///|
fn binary_test_signed_bigint(value : @binary.Binary) -> BigInt {
  let magnitude = bigint_from_text(value.coefficient().to_string())
  if value.is_sign_minus() {
    -magnitude
  } else {
    magnitude
  }
}

///|
/// Parses `text` as a BigInt; malformed text aborts, as the deprecated
/// `BigInt::from_string` did.
fn bigint_from_text(text : StringView, radix~ : Int32 = 10) -> BigInt {
  @string.parse_bigint(text, radix~) catch {
    _ => abort("invalid BigInt text")
  }
}
