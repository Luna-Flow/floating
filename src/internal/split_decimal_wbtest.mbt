///|
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
