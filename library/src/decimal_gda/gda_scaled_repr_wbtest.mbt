///|
// oracle: A
// source: floor(987654321 * 10^(scale - 20)) for eight scales, written out with Python integers; the tiny value
//   123456789E-2000000 scaled by 10 is zero (its quotient by 10^1999990 is below one)
// shares: to_string of the scaled magnitude (printing the result)
test "scaled representation of a tiny value is zero without a power of ten" {
  // exponent -2_000_000: the divisor 10^1_999_990 would have two million digits
  let tiny = finite_with_exponent_repr(
    false,
    dec_coeff_from_int(123456789),
    -2_000_000,
    9,
  )
  let (negative, magnitude) = decimal_finite_to_scaled_repr(tiny, 10)
  assert_true(!negative && magnitude.is_zero())
  let (negative, magnitude) = decimal_finite_to_scaled_repr(
    { ..tiny, negative: true, },
    10,
  )
  assert_true(!negative && magnitude.is_zero())
  // both sides of the boundary: digits == -shift (quotient 0), digits < -shift,
  // and digits > -shift (quotient nonzero)
  let value = finite_with_exponent_repr(
    true,
    dec_coeff_from_int(987654321),
    -20,
    9,
  )
  // (scale, magnitude): floor(987654321 * 10^(scale - 20)), written out with Python integers
  let rows : Array[(Int32, String)] = [
    (8, "0"),
    (11, "0"),
    (12, "9"),
    (13, "98"),
    (15, "9876"),
    (19, "98765432"),
    (20, "987654321"),
    (25, "98765432100000"),
  ]
  for row in rows {
    let (scale, expected) = row
    let (negative, magnitude) = decimal_finite_to_scaled_repr(value, scale)
    assert_eq(magnitude.to_string(), expected)
    assert_eq(negative, expected != "0")
  }
}
