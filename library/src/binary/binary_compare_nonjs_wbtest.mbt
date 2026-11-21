///|
fn cmp_next(state : Ref[UInt64]) -> UInt64 {
  let mut x = state.val
  x = x ^ (x << 13)
  x = x ^ (x >> 7)
  x = x ^ (x << 17)
  state.val = x
  x
}

///|
/// An odd coefficient of exactly `bits` bits (1 to 128) as `Coeff`.
fn cmp_coefficient(state : Ref[UInt64], bits : Int32) -> Coeff {
  let mut high = 0UL
  let mut low = cmp_next(state)
  if bits <= 64 {
    low = if bits == 64 { low } else { low & ((1UL << bits) - 1UL) }
  } else {
    let extra = bits - 64
    high = cmp_next(state)
    high = if extra == 64 { high } else { high & ((1UL << extra) - 1UL) }
  }
  // top bit and the odd low bit
  if bits <= 64 {
    low = low | (1UL << (bits - 1)) | 1UL
  } else {
    high = high | (1UL << (bits - 65))
    low = low | 1UL
  }
  bin_coeff_inline(high, low)
}

///|
fn cmp_value(negative : Bool, coefficient : Coeff, exponent : Int32) -> Binary {
  finite_normalized(negative, coefficient, exponent, 128)
}

///|
fn cmp_reference(a : Binary, b : Binary) -> Int32 {
  binary_compare_shifted(
    a.coefficient_(),
    a.exponent2_(),
    b.coefficient_(),
    b.exponent2_(),
  )
}

///|
// oracle: B
// source: binary_compare_shifted on the coefficients and exponents (Coeff shift and compare: the general comparison, a different algorithm from the word comparison under test); random lengths of 1 to 128 bits, equal, adjacent and far leading-bit exponents
// shares: binary_compare_shifted, Coeff shift_left and compare; the word comparison is binary_compare_pair_magnitude and binary_compare_magnitude
// primitives: Coeff::shift_left and Coeff::compare on coefficients of up to 128 bits plus a shift: level A in the bin_kernel tests (shifts and comparison against Python integers)
test "word comparison of magnitudes equals the general path" {
  let state = Ref(0x9e3779b97f4a7c15UL)
  let mut checked = 0
  let mut equal = 0
  // random lengths and exponent differences, including the neighbourhood of 64
  // and 128 and equal leading-bit exponents (adjacent tops)
  for _ in 0..<20000 {
    let bits_left = (cmp_next(state) % 128UL).to_int() + 1
    let bits_right = (cmp_next(state) % 128UL).to_int() + 1
    let mode = (cmp_next(state) % 4UL).to_int()
    let base = (cmp_next(state) % 2001UL).to_int() - 1000
    // exponents chosen so that the leading bits are equal, adjacent or far apart
    let left_exponent = base
    let right_exponent = match mode {
      0 => base + bits_left - bits_right
      1 => base + bits_left - bits_right + 1
      2 => base + bits_left - bits_right - 1
      _ => base + (cmp_next(state) % 301UL).to_int() - 150
    }
    let a = cmp_value(
      cmp_next(state) % 2UL == 0UL,
      cmp_coefficient(state, bits_left),
      left_exponent,
    )
    let b = cmp_value(
      cmp_next(state) % 2UL == 0UL,
      cmp_coefficient(state, bits_right),
      right_exponent,
    )
    let expected = cmp_reference(a, b)
    assert_eq(binary_compare_pair_magnitude(a, b), expected)
    assert_eq(binary_compare_magnitude(a, b), expected)
    if expected == 0 {
      equal += 1
    }
    checked += 1
  }
  assert_eq(checked, 20000)
  ignore(equal)
}

///|
// oracle: A, B
// source: equal values compare 0 and the same coefficient one exponent higher compares -1 and 1: written out; the neighbours (coefficient plus 2) are compared with binary_compare_shifted (B)
// shares: binary_compare_shifted for the neighbours
// primitives: Coeff::add, Coeff::shift_left, Coeff::compare: level A in the bin_kernel tests
test "word comparison: equal values, neighbours and the exponent differences around 64" {
  let state = Ref(0x2545f4914f6cdd1dUL)
  for bits in [1, 2, 3, 53, 63, 64, 65, 66, 127, 128] {
    let coefficient = cmp_coefficient(state, bits)
    for exponent in [-70, -65, -64, -63, -1, 0, 1, 63, 64, 65, 70] {
      let a = cmp_value(false, coefficient, exponent)
      // the same value: equal
      let same = cmp_value(true, coefficient, exponent)
      assert_eq(binary_compare_pair_magnitude(a, same), 0)
      // the odd neighbour above and below (coefficient + 2, coefficient - 2)
      let above = cmp_value(
        false,
        coefficient.add(Coeff::from_uint64(2UL)),
        exponent,
      )
      assert_eq(
        binary_compare_pair_magnitude(a, above),
        cmp_reference(a, above),
      )
      assert_eq(
        binary_compare_pair_magnitude(above, a),
        cmp_reference(above, a),
      )
      // the doubled coefficient is the same number only at the other exponent:
      // not a representation (the coefficient is odd), so compare the value
      // 2c * 2^(e - 1) = c * 2^e through its odd form
      let shifted = cmp_value(false, coefficient, exponent + 1)
      assert_eq(binary_compare_pair_magnitude(a, shifted), -1)
      assert_eq(binary_compare_pair_magnitude(shifted, a), 1)
    }
  }
}

///|
// oracle: A
// source: the return code 2 (declined) of binary_compare_pair_magnitude and the orders 1 and -1 for 5 * 2^200 + 1 against 3 are written out
// shares: nothing
test "word comparison leaves a wider operand to the general path" {
  let wide = finite_normalized(
    false,
    Coeff::from_uint64(5UL).shift_left(200).add(Coeff::one()),
    0,
    300,
  )
  let small = Binary::from_int(3)
  assert_eq(binary_compare_pair_magnitude(wide, small), 2)
  assert_eq(binary_compare_magnitude(wide, small), 1)
  assert_eq(binary_compare_magnitude(small, wide), -1)
}

///|
fn cmp_signed_reference(a : Binary, b : Binary) -> Int32 {
  let a_zero = a.coefficient_is_zero()
  let b_zero = b.coefficient_is_zero()
  if a_zero && b_zero {
    return 0
  }
  if a.negative() != b.negative() {
    return if a.negative() { -1 } else { 1 }
  }
  let m = if a_zero { -1 } else if b_zero { 1 } else { cmp_reference(a, b) }
  if a.negative() {
    -m
  } else {
    m
  }
}

///|
// oracle: B
// source: cmp_signed_reference: the sign and zero rules written out in the test (zeros equal, a negative below a positive, negated order for two negatives) on top of binary_compare_shifted for the magnitudes (B)
// shares: binary_compare_shifted for the magnitudes
// primitives: Coeff::shift_left and Coeff::compare: level A in the bin_kernel tests
test "word compare with signs and zeros equals the general path" {
  let state = Ref(0x2545f4914f6cdd1dUL)
  let values : Array[Binary] = []
  for _ in 0..<60 {
    let bits = (cmp_next(state) % 128UL).to_int() + 1
    let exponent = (cmp_next(state) % 200UL).to_int() - 100
    let c = cmp_coefficient(state, bits)
    values.push(cmp_value(cmp_next(state) % 2UL == 0UL, c, exponent))
  }
  values.push(cmp_value(false, bin_coeff_inline(0UL, 0UL), 0))
  values.push(cmp_value(true, bin_coeff_inline(0UL, 0UL), 0))
  for a in values {
    for b in values {
      assert_eq(binary_compare_pair(a, b), cmp_signed_reference(a, b))
    }
  }
}
