///|
// Differential test of the integer square root against the previous
// implementation (Newton from a power of ten, one full division per step,
// remainder by a squaring), kept here as private reference code. The results
// are the unique floor root and remainder, so they must agree bit for bit,
// representation included.

///|
fn reference_integer_sqrt_rem_repr(n : DecCoeff) -> (DecCoeff, DecCoeff) {
  if dec_coeff_small_value(n) is Some(small) {
    if small <= 1UL {
      return (n, dec_coeff_zero())
    }
    let mut approximation = dec_coeff_small_powers10[(n.digits10() + 1) / 2]
    while true {
      let next = (approximation + small / approximation) / 2UL
      if next >= approximation {
        let square = approximation * approximation
        return (DecCoeff::Small(approximation), DecCoeff::Small(small - square))
      }
      approximation = next
    } nobreak {
      abort("small coefficient square-root iteration must terminate")
    }
  }
  if dec_coeff_compare_repr(n, dec_coeff_from_int(1)) <= 0 {
    return (n, dec_coeff_zero())
  }
  let mut approximation = dec_coeff_power10_repr((n.digits10() + 1) / 2)
  while true {
    let (quotient, _) = dec_coeff_div_rem_repr(n, approximation)
    let sum = dec_coeff_magnitude_add_repr(approximation, quotient)
    let next = dec_coeff_div_rem_by_unit_repr(sum, 2).0
    if dec_coeff_compare_repr(next, approximation) >= 0 {
      let square = dec_coeff_square_repr(approximation)
      return (approximation, dec_coeff_magnitude_sub_repr(n, square))
    }
    approximation = next
  } nobreak {
    (approximation, dec_coeff_zero())
  }
}

///|
fn sqrt_diff_next(state : Ref[UInt64]) -> UInt64 {
  let mut x = state.val
  x = x ^ (x << 13)
  x = x ^ (x >> 7)
  x = x ^ (x << 17)
  state.val = x
  x
}

///|
fn sqrt_diff_random_limbs(state : Ref[UInt64], length : Int32) -> DecCoeff {
  let limbs = Array::make(length, 0U)
  for index in 0..<length {
    // a random number of digits per limb, so that runs of zeros and nines
    // and short top limbs appear
    let width = (sqrt_diff_next(state) % 9UL).to_int() + 1
    let mut value = (sqrt_diff_next(state) % dec_coeff_small_powers10[width]).to_int()
    if sqrt_diff_next(state) % 7UL == 0UL {
      value = 0
    } else if sqrt_diff_next(state) % 7UL == 0UL {
      value = dec_coeff_base - 1
    }
    limbs[index] = value.reinterpret_as_uint()
  }
  if limbs[length - 1] == 0U {
    limbs[length - 1] = (sqrt_diff_next(state) % 999999999UL + 1UL).to_uint()
  }
  dec_coeff_from_unit_accumulator(limbs, length)
}

///|
fn sqrt_diff_same(a : DecCoeff, b : DecCoeff) -> Bool {
  match (a, b) {
    (Small(x), Small(y)) => x == y
    (Limbs(x, dx), Limbs(y, dy)) => dx == dy && x == y
    _ => false
  }
}
