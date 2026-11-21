// #445: the exponent gap of the two operands of `remainder` is computed without
// wrapping, so the residue 2^gap mod c is right when the gap exceeds 2^31 - 1
// (both operands are ordinary finite values: x = 2^ex with ex up to e_max,
// d = c * 2^ey with ey down to the smallest quantum).

///|
/// 2^n mod c for odd c by the multiplicative order of 2 (an independent oracle:
/// it never forms 2^n and does not use the square-and-multiply of the code).
fn r445_pow2_mod(n : Int64, c : Int64, order : Int64) -> Int64 {
  let mut r = 1L
  let steps = n % order
  let mut i = 0L
  while i < steps {
    r = r * 2L % c
    i += 1L
  }
  r
}

///|
test "remainder with an exponent gap above 2^31 - 1 (#445)" {
  let ey = binary_implementation_e_min - 52
  // (c, multiplicative order of 2 modulo c)
  let moduli = [(3L, 2L), (5L, 4L), (7L, 3L), (9L, 6L), (11L, 10L), (13L, 12L)]
  let gaps = [2147483646L, 2147483647L, 2147483648L, 2147483649L, 2147483697L]
  for modulus in moduli {
    let (c, order) = modulus
    for gap in gaps {
      let ex = (ey.to_int64() + gap).to_int()
      for negative in [false, true] {
        let x = Binary::make(BinCoeff::one(), ex, 53, negative~)
        let d = Binary::make(
          BinCoeff::from_uint64(c.reinterpret_as_uint64()),
          ey,
          53,
        )
        let r = x.remainder(d)
        let residue = r445_pow2_mod(gap, c, order)
        // nearest multiple: residue above half the modulus is rounded up, which
        // flips the sign and leaves c - residue.
        let (flip, magnitude) = if 2L * residue > c {
          (true, c - residue)
        } else {
          (false, residue)
        }
        let label = "c=\{c} gap=\{gap} neg=\{negative}"
        if magnitude == 0L {
          assert_true(r.is_zero(), msg=label)
        } else {
          let expected = Binary::make(
            BinCoeff::from_uint64(magnitude.reinterpret_as_uint64()),
            ey,
            53,
            negative=negative != flip,
          )
          assert_true(r.coefficient() == expected.coefficient(), msg=label)
          assert_eq(r.exponent2(), expected.exponent2(), msg=label)
          assert_eq(r.is_sign_minus(), expected.is_sign_minus(), msg=label)
        }
      }
    }
  }
}

///|
test "the example of #445" {
  let d = Binary::make(BinCoeff::from_uint64(3UL), -1073741874, 53)
  let x = Binary::make(BinCoeff::one(), 1073741823, 53)
  let r = x.remainder(d)
  // 2^2147483697 (the gap of the exponents) mod 3 = 2: the nearest multiple is one above, so -1 quantum.
  assert_true(r.is_sign_minus())
  assert_true(r.coefficient() == BinCoeff::one())
  assert_eq(r.exponent2(), -1073741874)
  let even = Binary::make(BinCoeff::one(), 1073741822, 53).remainder(d)
  assert_false(even.is_sign_minus())
  assert_true(even.coefficient() == BinCoeff::one())
}
