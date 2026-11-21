///|
/// IEEE 754-2019 §5.12.2 and General Decimal Arithmetic to-engineering-string:
/// engineering exponent arithmetic must not wrap at the Int endpoints.
// oracle: A
// source: CPython to_eng_string of 0E+2147483647: 0.00E+2147483649
// shares: nothing (the input is built with finite_with_exponent_repr and the result is a literal)
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
// oracle: A
// source: CPython to_eng_string of 1E-2147483647: 100E-2147483649
// shares: nothing (the input is built with finite_with_exponent_repr and the result is a literal)
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
// oracle: A
// source: CPython to_eng_string of 12345E+2147483647: 123.45E+2147483649
// shares: Decimal::from_string and to_string (reading the inputs, printing the result)
test "engineering format extends adjusted exponent without wrapping" {
  let value = finite_with_exponent_repr(
    false,
    dec_coeff_from_int(12345),
    2_147_483_647,
    34,
  )
  inspect(format_eng_finite(value), content="123.45E+2147483649")
}
