///|
fn ilogb_reference(x : Binary) -> Int32? {
  if x.is_nan() || x.is_infinite() || x.is_zero() {
    None
  } else {
    Some(x.exponent2() + x.coefficient().bit_length() - 1)
  }
}

///|
/// An odd coefficient of exactly `bits` bits as a `Coeff`.
fn ilogb_coefficient(bits : Int32) -> Coeff {
  if bits == 1 {
    Coeff::one()
  } else {
    Coeff::one().shift_left(bits - 1).add(Coeff::one())
  }
}

///|
test "ilogb equals exponent2 plus the bit length minus one on every width class" {
  let lengths = [
    1, 2, 3, 24, 53, 63, 64, 65, 66, 113, 127, 128, 129, 130, 256, 700,
  ]
  // exponents that keep the leading bit inside the stored range, both ends
  let tops = [
    binary_value_e_min - 1,
    binary_value_e_min,
    -1000,
    -1,
    0,
    1,
    1000,
    binary_value_e_max - 1,
    binary_value_e_max,
  ]
  let mut checked = 0
  for bits in lengths {
    for top in tops {
      // the exponent of the lowest bit that puts the leading bit at `top`
      let exponent = top - (bits - 1)
      if exponent < binary_value_e_min - 800 {
        continue
      }
      let precision = Int32::max(bits, 24)
      let x = finite_normalized(
        bits % 2 == 0,
        ilogb_coefficient(bits),
        exponent,
        precision,
      )
      if x.is_finite() && !x.is_zero() {
        assert_eq(x.ilogb(), ilogb_reference(x))
        checked += 1
      }
    }
  }
  assert_true(checked > 80)
}

///|
test "ilogb of the special values and of the stored range" {
  assert_eq(Binary::one().ilogb(), Some(0))
  assert_eq(Binary::from_int(8).ilogb(), Some(3))
  assert_eq(Binary::from_int(-5).ilogb(), Some(2))
  assert_eq(Binary::zero().ilogb(), None)
  assert_eq(Binary::negative_zero().ilogb(), None)
  assert_eq(Binary::inf().ilogb(), None)
  assert_eq(Binary::inf(negative=true).ilogb(), None)
  assert_eq(Binary::nan().ilogb(), None)
  // the largest and the smallest stored magnitudes of a 53-bit format
  let largest = Binary::make(BinCoeff::one(), binary_value_e_max, 53)
  assert_eq(largest.ilogb(), Some(binary_value_e_max))
  let smallest = Binary::make(BinCoeff::one(), binary_value_e_min - 52, 53)
  assert_eq(smallest.ilogb(), Some(binary_value_e_min - 52))
  // a subnormal: the leading bit of 3 * 2^(e_min - 52) is e_min - 51
  let subnormal = Binary::make(
    BinCoeff::from_uint64(3UL),
    binary_value_e_min - 52,
    53,
  )
  assert_eq(subnormal.ilogb(), Some(binary_value_e_min - 51))
}
