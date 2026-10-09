///|
test "operand exponents beyond the decTest range saturate at 2e9" {
  inspect(saturate_operand_exponent("1e3000000000"), content="1E+2000000000")
  inspect(
    saturate_operand_exponent("-12.5e-12345678903"),
    content="-12.5E-2000000000",
  )
  inspect(
    saturate_operand_exponent("1e-000000000001000000007"),
    content="1e-000000000001000000007",
  )
  inspect(saturate_operand_exponent("1e2000000000"), content="1e2000000000")
  inspect(saturate_operand_exponent("1e-1000000008"), content="1e-1000000008")
  inspect(
    saturate_operand_exponent("#A2300000000003D0"),
    content="#A2300000000003D0",
  )
}
