///|
// Differential test of the integer square root against the previous
// implementation (Newton from a power of ten, one full division per step,
// remainder by a squaring), kept here as private reference code. The results
// are the unique floor root and remainder, so they must agree bit for bit,
// representation included.

///|
let sqrt_diff_cases : Int32 = 300

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

///|
fn sqrt_diff_check(n : DecCoeff) -> Unit raise {
  let (root, remainder) = dec_coeff_integer_sqrt_rem_repr(n)
  let (reference_root, reference_remainder) = reference_integer_sqrt_rem_repr(n)
  if !sqrt_diff_same(root, reference_root) ||
    !sqrt_diff_same(remainder, reference_remainder) {
    fail("integer square root differs from the reference for \{n.to_string()}")
  }
}

///|
fn sqrt_diff_class(length : Int32, seed : UInt64) -> Unit raise {
  let state = Ref(seed)
  for _ in 0..<sqrt_diff_cases {
    let n = sqrt_diff_random_limbs(state, length)
    sqrt_diff_check(n)
    // a perfect square of about this size, one below and one above it
    let root = sqrt_diff_random_limbs(state, (length + 1) / 2)
    let square = dec_coeff_square_repr(root)
    sqrt_diff_check(square)
    sqrt_diff_check(dec_coeff_magnitude_add_unit(square, 1))
    if !square.is_zero() {
      sqrt_diff_check(dec_coeff_magnitude_sub_unit(square, 1))
    }
  }
}

///|
test "integer square root equals the reference, 1 limb" {
  sqrt_diff_class(1, 0x9E3779B97F4A7C15UL)
}

///|
test "integer square root equals the reference, 2 limbs" {
  sqrt_diff_class(2, 0xD1B54A32D192ED03UL)
}

///|
test "integer square root equals the reference, 3 limbs" {
  sqrt_diff_class(3, 0x2545F4914F6CDD1DUL)
}

///|
test "integer square root equals the reference, 6 limbs" {
  sqrt_diff_class(6, 0x94D049BB133111EBUL)
}

///|
test "integer square root equals the reference, 12 limbs" {
  sqrt_diff_class(12, 0xBF58476D1CE4E5B9UL)
}

///|
test "integer square root equals the reference, 56 limbs" {
  sqrt_diff_class(56, 0x6A09E667F3BCC909UL)
}

///|
test "integer square root equals the reference, 112 limbs" {
  sqrt_diff_class(112, 0xBB67AE8584CAA73BUL)
}

///|
test "integer square root equals the reference on powers of ten and nines" {
  for digits in 0..<1100 {
    let power = dec_coeff_power10_repr(digits)
    sqrt_diff_check(power)
    sqrt_diff_check(dec_coeff_magnitude_add_unit(power, 1))
    if digits > 0 {
      sqrt_diff_check(dec_coeff_magnitude_sub_unit(power, 1))
    }
    // both parities of the digit count around the perfect squares 10^(2k)
    // and 4 * 10^(2k)
    sqrt_diff_check(dec_coeff_multiply_by_unit_repr(power, 4))
    sqrt_diff_check(dec_coeff_multiply_by_unit_repr(power, 9))
    sqrt_diff_check(dec_coeff_multiply_by_unit_repr(power, 3))
  }
}

///|
test "integer square root of the small range" {
  for value in 0..<2000 {
    sqrt_diff_check(dec_coeff_from_int(value))
  }
  let state = Ref(0x123456789ABCDEF1UL)
  for _ in 0..<sqrt_diff_cases {
    let value = sqrt_diff_next(state) % dec_coeff_small_limit
    sqrt_diff_check(DecCoeff::Small(value))
    let root = sqrt_diff_next(state) % 1000000000UL
    sqrt_diff_check(DecCoeff::Small(root * root))
    if root > 0UL {
      sqrt_diff_check(DecCoeff::Small(root * root - 1UL))
    }
    sqrt_diff_check(DecCoeff::Small(root * root + 1UL))
  }
}
