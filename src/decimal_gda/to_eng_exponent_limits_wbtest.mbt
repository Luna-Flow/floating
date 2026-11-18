///|
/// IEEE 754-2019 §5.12.2 and General Decimal Arithmetic to-engineering-string:
/// engineering exponent arithmetic must not wrap at the Int endpoints.
test "engineering format preserves maximum zero exponent" {
  let value = finite_with_exponent_repr(
    false,
    dec_coeff_zero(),
    2_147_483_647,
    34,
  )
  inspect(format_eng_finite(value), content="0.00E+2147483649")
}

///|
test "engineering format preserves minimum finite exponent" {
  let value = finite_with_exponent_repr(
    false,
    dec_coeff_from_int(1),
    -2_147_483_647,
    34,
  )
  inspect(format_eng_finite(value), content="100E-2147483649")
}

///|
test "engineering format extends adjusted exponent without wrapping" {
  let value = finite_with_exponent_repr(
    false,
    dec_coeff_from_int(12345),
    2_147_483_647,
    34,
  )
  inspect(format_eng_finite(value), content="123.45E+2147483649")
}
