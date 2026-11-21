///|
fn exact_root_contexts(precision : Int32) -> Array[BinaryContext] {
  [RoundTiesToEven, RoundTowardNegative, RoundTowardPositive, RoundTowardZero].map(fn(
      mode,
    ) {
      BinaryContext::new(precision~, rounding=mode)
    },
  )
}

///|
/// An odd coefficient of `bits` bits with a varied bit pattern.
fn exact_root_odd_coefficient(bits : Int32, seed : UInt64) -> Coeff {
  let mut value = Coeff::one()
  let mut state = seed
  while value.bit_length() < bits {
    state = state * 6364136223846793005UL + 1442695040888963407UL
    value = value.shift_left(32).add(Coeff::from_uint64(state >> 32))
  }
  let trimmed = value.shift_right(value.bit_length() - bits)
  if trimmed.is_odd() {
    trimmed
  } else {
    trimmed.add(Coeff::one())
  }
}

///|
test "binary_floor_nth_root brackets the root" {
  for degree in [2, 3, 5, 7, 12, 64, 100] {
    for bits in [degree + 1, 200, 1000, 5000, 20000] {
      if bits <= degree {
        continue
      }
      let value = exact_root_odd_coefficient(bits, (bits + degree).to_uint64())
      let root = binary_floor_nth_root(value, degree)
      let exponent = degree.reinterpret_as_uint()
      assert_true(root.pow_nat(exponent).compare(value) <= 0)
      assert_true(root.add(Coeff::one()).pow_nat(exponent).compare(value) > 0)
    }
  }
}

///|
test "binary_exact_nth_root_coefficient detects wide perfect powers" {
  let one = Coeff::one()
  for degree in [2, 3, 4, 5, 6, 8, 9, 16] {
    for bits in [10, 300, 2049, 5000, 9000] {
      let root = exact_root_odd_coefficient(bits, (bits * degree).to_uint64())
      let power = root.pow_nat(degree.reinterpret_as_uint())
      assert_eq(
        binary_exact_nth_root_coefficient(power, degree),
        Some(root),
        msg="degree " + degree.to_string() + ", root bits " + bits.to_string(),
      )
      assert_eq(
        binary_exact_nth_root_coefficient(power.add(one).add(one), degree),
        None,
      )
      assert_eq(
        binary_exact_nth_root_coefficient(
          power.sub_checked(one).unwrap().sub_checked(one).unwrap(),
          degree,
        ),
        None,
      )
    }
  }
}

///|
test "Binary rootn and pow return exact roots of coefficients over 4096 bits" {
  let root = Coeff::one().shift_left(3000).add(Coeff::one())
  let expected = Binary::make_coeff(root, 0, 3001)
  let square = Binary::make_coeff(root.square(), 0, 6002)
  let cube = Binary::make_coeff(root.pow_nat(3U), 0, 9003)
  let fourth = Binary::make_coeff(root.pow_nat(4U), 0, 12004)
  for context in exact_root_contexts(3001) {
    assert_exact_result(
      square.try_rootn_ctx(2, context),
      expected,
      "rootn(r^2, 2)",
    )
    assert_exact_result(
      cube.try_rootn_ctx(3, context),
      expected,
      "rootn(r^3, 3)",
    )
    assert_exact_result(
      square.try_pow_ctx(Binary::make_coeff(Coeff::one(), -1, 53), context),
      expected,
      "pow(r^2, 1/2)",
    )
    assert_exact_result(
      fourth.try_pow_ctx(Binary::make_coeff(Coeff::one(), -2, 53), context),
      expected,
      "pow(r^4, 1/4)",
    )
    // A negative degree divides once with the context rounding.
    let (reciprocal, flags) = square.rootn_ctx(-2, context)
    assert_identical(reciprocal, Binary::one().div_ctx(expected, context).0)
    assert_true(flags.inexact())
  }
  for context in exact_root_contexts(9003) {
    assert_exact_result(
      square.try_pow_ctx(
        Binary::make_coeff(Coeff::from_uint64(3), -1, 53),
        context,
      ),
      Binary::make_coeff(root.pow_nat(3U), 0, 9003),
      "pow(r^2, 3/2)",
    )
  }
}
