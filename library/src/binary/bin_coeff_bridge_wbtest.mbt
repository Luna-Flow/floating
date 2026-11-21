///|
// oracle: A
// source: expected values written out (the integer 5 has the bit length 3, 0 has the bit length 0, 2^70 has 71)
// shares: nothing
test "the kernel bridge of BinCoeff keeps the integer" {
  let five = BinCoeff::from_kernel(@bin_kernel.Coeff::from_uint64(5UL))
  assert_eq(five.to_uint64(), Some(5UL))
  assert_eq(five.bit_length(), 3)
  assert_true(five == BinCoeff::from_uint64(5UL))
  assert_true(BinCoeff::from_kernel(@bin_kernel.Coeff::zero()).is_zero())
  let wide = BinCoeff::from_kernel(@bin_kernel.Coeff::one().shift_left(70))
  assert_eq(wide.bit_length(), 71)
  assert_eq(wide.to_kernel().bit_length(), 71)
  assert_eq(wide.to_string(), "1180591620717411303424")
}
