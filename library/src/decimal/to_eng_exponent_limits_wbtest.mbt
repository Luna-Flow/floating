///|
/// IEEE 754-2019 §5.12.2 and General Decimal Arithmetic to-engineering-string:
/// engineering exponent arithmetic must not wrap at the Int endpoints.
// oracle: A
// source: CPython decimal to_eng_string (re-run 2026-11-26) and IEEE 754-2019 5.12.2: 0E+2147483647 is 0.00E+2147483649 (the engineering exponent is the next multiple of three, 2147483649)
// shares: finite_with_exponent_repr and dec_coeff_zero and dec_coeff_from_int (build the operands), format_eng_finite (the code under test); also read through to_string and inspect (print the result) (they read the operands and results, not the code under test)
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
// source: CPython decimal to_eng_string (re-run 2026-11-26): 1E-2147483647 is 100E-2147483649 (the exponent a multiple of three)
// shares: finite_with_exponent_repr and dec_coeff_zero and dec_coeff_from_int (build the operands), format_eng_finite (the code under test); also read through to_string and inspect (print the result) (they read the operands and results, not the code under test)
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
// source: CPython decimal to_eng_string (re-run 2026-11-26): 12345E+2147483647 is 123.45E+2147483649
// shares: finite_with_exponent_repr and dec_coeff_zero and dec_coeff_from_int (build the operands), format_eng_finite (the code under test); also read through to_string and inspect (print the result) (they read the operands and results, not the code under test)
test "engineering format extends adjusted exponent without wrapping" {
  let value = finite_with_exponent_repr(
    false,
    dec_coeff_from_int(12345),
    2_147_483_647,
    34,
  )
  inspect(format_eng_finite(value), content="123.45E+2147483649")
}
