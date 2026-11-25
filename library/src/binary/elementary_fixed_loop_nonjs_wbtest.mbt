// The limb-array loop of the fixed-point `ln` series against the `Coeff` form it
// replaces, which is kept here as the reference: the same sum and the same term
// count, for every alignment of the shift `F` and every limb count, and the same
// bounds through `binary_ln_unit_fixed_bounds`.

///|
/// The loop as it was before the limb arrays (also the JS form). `top_zero`
/// counts the terms whose product has a zero top limb.
fn binary_ln_artanh_loop_reference(
  z : Coeff,
  square : Coeff,
  fractional : Int32,
  top_zero : Ref[Int32],
) -> (Coeff, Int32)? {
  let stop = Coeff::one().shift_left(6)
  let mut power = z
  let mut sum = z
  let mut index = 0
  while index < 10000 {
    index += 1
    let product = power.mul(square)
    let power_limbs = (power.bit_length() + 63) / 64
    let square_limbs = (square.bit_length() + 63) / 64
    if product.bit_length() <= 64 * (power_limbs + square_limbs - 1) {
      top_zero.val += 1
    }
    power = product.shift_right(fractional)
    if power.compare(stop) < 0 {
      return Some((sum, index))
    }
    let divisor = Coeff::from_uint64((2 * index + 1).to_uint64())
    sum = sum.add(power.div_rem_checked(divisor).unwrap().0)
  }
  None
}

///|
fn fixed_loop_random(seed : Ref[UInt64]) -> UInt64 {
  seed.val = seed.val ^ (seed.val << 13)
  seed.val = seed.val ^ (seed.val >> 7)
  seed.val = seed.val ^ (seed.val << 17)
  seed.val
}

///|
fn fixed_loop_coeff(bits : Int32, seed : Ref[UInt64]) -> Coeff {
  let mut value = Coeff::one()
  for _ in 1..<bits {
    value = value.shift_left(1)
    if fixed_loop_random(seed) % 2UL == 1UL {
      value = value.add(Coeff::one())
    }
  }
  value
}

///|
fn fixed_loop_same(left : (Coeff, Int32)?, right : (Coeff, Int32)?) -> Bool {
  match (left, right) {
    (Some((a, i)), Some((b, j))) => a == b && i == j
    (None, None) => true
    _ => false
  }
}

///|
test "limb loop equals the Coeff loop for every shift alignment and limb count" {
  let seed = Ref(0x9E3779B97F4A7C15UL)
  let top_zero = Ref(0)
  let reference_zero = Ref(0)
  let mut cases = 0
  // F from 60 to 700: every residue of F mod 64 at one to eleven limbs, in
  // particular F + 1 a multiple of 64 and one below and one above it.
  for fractional in 60..<701 {
    for
      bits in [
        fractional - 2,
        fractional - 5,
        fractional - 20,
        fractional / 2,
        70,
        3,
      ] {
      if bits < 2 || bits >= fractional {
        continue
      }
      let z = fixed_loop_coeff(bits, seed)
      let square = z.mul(z).shift_right(fractional)
      assert_true(
        fixed_loop_same(
          binary_ln_artanh_loop(z, square, fractional),
          binary_ln_artanh_loop_reference(z, square, fractional, top_zero),
        ),
      )
      cases += 1
    }
  }
  // Every value of z whose square is zero or one word, and Z = 1.
  for fractional in [64, 65, 127, 128, 129, 191, 192, 193] {
    for
      z in [
        Coeff::one(),
        Coeff::from_uint64(3UL),
        Coeff::from_uint64(0xFFFFFFFFFFFFFFFFUL),
        Coeff::one().shift_left(fractional - 2),
        Coeff::one()
        .shift_left(fractional - 2)
        .sub_checked(Coeff::one())
        .unwrap(),
      ] {
      let square = z.mul(z).shift_right(fractional)
      assert_true(
        fixed_loop_same(
          binary_ln_artanh_loop(z, square, fractional),
          binary_ln_artanh_loop_reference(z, square, fractional, reference_zero),
        ),
      )
      cases += 1
    }
  }
  assert_true(cases > 3000)
  // The corpus has terms whose product has a zero top limb.
  assert_true(top_zero.val > 100)
}

///|
/// The inputs `(Z, Q, F)` of `binary_ln_unit_fixed_bounds` for an exact value
/// in `(1, 2]` (the code before the loop), to compare the whole function.
fn fixed_ln_inputs(
  value : Binary,
  work_precision : Int32,
) -> (Coeff, Coeff, Int32)? {
  let coefficient = value.coefficient_()
  let exponent = value.exponent2()
  let (scaled_value, unit_shift) = if exponent >= 0 {
    (coefficient.shift_left(exponent), 0)
  } else {
    (coefficient, -exponent)
  }
  let unit = Coeff::one().shift_left(unit_shift)
  let numerator = scaled_value.sub_checked(unit).unwrap()
  let denominator = scaled_value.add(unit)
  let lz = denominator.bit_length() - numerator.bit_length() + 1
  if lz > 4 * work_precision + 64 {
    return None
  }
  let fractional = work_precision + 16 + lz
  let z = numerator.shift_left(fractional).div_rem_checked(denominator).unwrap().0
  Some((z, z.mul(z).shift_right(fractional), fractional))
}

///|
// oracle: S
// source: binary_ln_artanh_loop_reference, the earlier Coeff loop kept in this file, on the same exact values; agreement of two implementations of one recurrence
// shares: the artanh recurrence and Coeff arithmetic (both loops)
test "fixed ln bounds equal the Coeff loop on exact values" {
  let seed = Ref(0x2545F4914F6CDD1DUL)
  let top_zero = Ref(0)
  let mut cases = 0
  for work in 20..<400 {
    let values : Array[Binary] = []
    for m in [1, 2, 3, 5, 8, 13, 40, 63, 64, 65, 100] {
      let x = Binary::make_coeff(Coeff::one(), -m, work + 1).add(
        Binary::one(precision=work + 1),
      )
      values.push(x)
    }
    // all ones: 2 - 2^-(work - 1), and a random coefficient of the full width
    values.push(
      Binary::make_coeff(
        Coeff::one().shift_left(work).sub_checked(Coeff::one()).unwrap(),
        -(work - 1),
        work,
      ),
    )
    values.push(
      Binary::make_coeff(
        fixed_loop_coeff(work, seed).add(Coeff::one()).bit_or(Coeff::one()),
        -(work - 1),
        work,
      ),
    )
    for value in values {
      let exact = value.with_precision(
        work,
        BinaryRoundingMode::RoundTowardNegative,
      )
      if exact.compare(value) != 0 ||
        value.compare(Binary::one()) <= 0 ||
        value.compare(Binary::from_int(2)) > 0 {
        continue
      }
      match
        (fixed_ln_inputs(value, work), binary_ln_unit_fixed_bounds(value, work)) {
        (Some((z, square, fractional)), Some((lower, upper))) => {
          let (sum, index) = binary_ln_artanh_loop_reference(
            z, square, fractional, top_zero,
          ).unwrap()
          let slack = Coeff::from_uint64((2 * index + 70).to_uint64())
          let expected_lower = Binary::make_coeff(
            sum.shift_left(1),
            -fractional,
            work,
            mode=BinaryRoundingMode::RoundTowardNegative,
          )
          let expected_upper = Binary::make_coeff(
            sum.add(slack).shift_left(1),
            -fractional,
            work,
            mode=BinaryRoundingMode::RoundTowardPositive,
          )
          assert_true(
            lower.identical(expected_lower) && upper.identical(expected_upper),
          )
          assert_true(
            lower.precision() == expected_lower.precision() &&
            upper.precision() == expected_upper.precision(),
          )
          cases += 1
        }
        _ => ()
      }
    }
  }
  assert_true(cases > 2000)
}
