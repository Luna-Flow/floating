///|
// oracle: A
// source: exponent written minus the fraction digits, by hand: 1e1600000000 is (1, 1600000000); -2.5e-3000000000 is (25, -3000000000 - 1); the third literal is past the documented cap 10^18 of the written exponent, so it saturates there (contract in the doc comment of the function); 1e has no exponent digit
// shares: nothing
test "split_decimal_string_wide keeps exponents beyond Int" {
  debug_inspect(
    split_decimal_string_wide("1e1600000000"),
    content="Some((false, \"1\", 1600000000))",
  )
  debug_inspect(
    split_decimal_string_wide("-2.5e-3000000000"),
    content="Some((true, \"25\", -3000000001))",
  )
  debug_inspect(
    split_decimal_string_wide("1e99999999999999999999999"),
    content="Some((false, \"1\", 1000000000000000000))",
  )
  debug_inspect(split_decimal_string_wide("1e"), content="None")
}

///|
// oracle: A
// source: by hand: 1.0e2147483648 has digits 10 and exponent 2147483648 - 1 = 2147483647 = Int max, so it is accepted; 1e2147483648 and 1e-3000000000 are outside Int and give None by the documented contract
// shares: nothing
test "split_decimal_string rejects exponents outside Int" {
  debug_inspect(
    split_decimal_string("1e1600000000"),
    content="Some((false, \"1\", 1600000000))",
  )
  debug_inspect(
    split_decimal_string("1.0e2147483648"),
    content="Some((false, \"10\", 2147483647))",
  )
  debug_inspect(split_decimal_string("1e2147483648"), content="None")
  debug_inspect(split_decimal_string("1e-3000000000"), content="None")
}
