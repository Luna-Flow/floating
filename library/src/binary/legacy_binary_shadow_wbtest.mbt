///|
fn legacy_shadow_assert_equal(
  candidate : Binary,
  legacy : LegacyBigIntBinary,
  label~ : String = "",
) -> Unit raise {
  if candidate.classify() != legacy.classify() ||
    candidate.sign() != legacy.sign() ||
    candidate.is_sign_minus() != legacy.is_negative() ||
    candidate.precision() != legacy.precision() ||
    candidate.exponent2() != legacy.exponent2() ||
    candidate.coefficient().to_string() != legacy.coefficient().to_string() {
    println(
      "shadow mismatch label=" +
      label +
      " candidate=" +
      candidate.to_string() +
      " legacy_coeff=" +
      legacy.coefficient().to_string() +
      " legacy_exp=" +
      legacy.exponent2().to_string() +
      " legacy_neg=" +
      legacy.is_negative().to_string(),
    )
  }
  assert_true(candidate.classify() == legacy.classify())
  assert_true(candidate.sign() == legacy.sign())
  assert_true(candidate.is_sign_minus() == legacy.is_negative())
  assert_true(candidate.precision() == legacy.precision())
  assert_true(candidate.exponent2() == legacy.exponent2())
  assert_eq(
    candidate.coefficient().to_string(),
    legacy.coefficient().to_string(),
  )
  assert_true(candidate.is_signaling_nan() == legacy.is_signaling_nan())
  assert_eq(
    candidate.nan_payload().to_string(),
    legacy.nan_payload().to_string(),
  )
}

///|
fn legacy_shadow_next(state : Int32) -> Int32 {
  ((state.to_int64() * 1103515245L + 12345L) % 2147483648L).to_int()
}

///|
fn legacy_shadow_magnitude(seed : Int32, bits : Int32) -> (Int32, BigInt) {
  let mut state = seed
  let mut magnitude = legacy_bin_zero()
  let chunks = (bits + 29) / 30
  for _ in 0..<chunks {
    state = legacy_shadow_next(state)
    magnitude = (magnitude << 30) + BigInt::from_int(state & 0x3fff_ffff)
  }
  let excess = chunks * 30 - bits
  if excess > 0 {
    magnitude = magnitude >> excess
  }
  let top = legacy_bin_one() << (bits - 1)
  if magnitude < top {
    magnitude = magnitude + top
  }
  (state, magnitude)
}

///|
fn legacy_shadow_operand(seed : Int32) -> (Int32, Binary, LegacyBigIntBinary) {
  let mut state = legacy_shadow_next(seed)
  let bits = state % 192 + 1
  let (next_state, magnitude) = legacy_shadow_magnitude(state, bits)
  state = legacy_shadow_next(next_state)
  let exponent2 = state % 97 - 48
  state = legacy_shadow_next(state)
  let precision = state % 128 + 1
  state = legacy_shadow_next(state)
  let negative = (state & 1) != 0
  let coefficient = BinCoeff::parse(magnitude.to_string()).unwrap()
  (
    state,
    Binary::make(coefficient, exponent2, precision, negative~),
    LegacyBigIntBinary::make(
      if negative {
        -magnitude
      } else {
        magnitude
      },
      exponent2,
      precision,
    ),
  )
}

///|
test "LegacyBigIntBinary make preserves ties-even normalization" {
  for item in [(9, 3), (11, 3), (13, 3), (15, 3), (31, 4), (33, 4)] {
    let (magnitude, precision) = item
    for negative in [false, true] {
      let coefficient = BinCoeff::from_uint64(magnitude.to_uint64())
      let candidate = Binary::make(coefficient, -7, precision, negative~)
      let legacy = LegacyBigIntBinary::make(
        if negative {
          -BigInt::from_int(magnitude)
        } else {
          BigInt::from_int(magnitude)
        },
        -7,
        precision,
      )
      legacy_shadow_assert_equal(candidate, legacy)
      let wide_candidate = Binary::make(coefficient, -7, 256, negative~)
      let wide_legacy = LegacyBigIntBinary::make(
        if negative {
          -BigInt::from_int(magnitude)
        } else {
          BigInt::from_int(magnitude)
        },
        -7,
        256,
      )
      legacy_shadow_assert_equal(
        wide_candidate.with_precision(
          precision,
          BinaryRoundingMode::RoundTiesToEven,
        ),
        wide_legacy.with_precision(
          precision,
          BinaryRoundingMode::RoundTiesToEven,
        ),
        label="round",
      )
    }
  }
}

///|
test "LegacyBigIntBinary fixed-seed finite shadow" {
  let mut state = 0x1357_2468
  for _ in 0..<320 {
    let (left_state, left, legacy_left) = legacy_shadow_operand(state)
    let (right_state, right, legacy_right) = legacy_shadow_operand(left_state)
    state = right_state
    legacy_shadow_assert_equal(left, legacy_left, label="left")
    legacy_shadow_assert_equal(right, legacy_right, label="right")
    legacy_shadow_assert_equal(
      left.add(right),
      legacy_left.add(legacy_right),
      label="add",
    )
    legacy_shadow_assert_equal(
      left.sub(right),
      legacy_left.sub(legacy_right),
      label="sub",
    )
    legacy_shadow_assert_equal(
      left.mul(right),
      legacy_left.mul(legacy_right),
      label="mul",
    )
    legacy_shadow_assert_equal(
      left.div(right),
      legacy_left.div(legacy_right),
      label="div",
    )
    let positive_left = left.abs()
    let legacy_positive_left = legacy_binary_from_candidate(positive_left)
    legacy_shadow_assert_equal(
      positive_left.sqrt(),
      legacy_positive_left.sqrt().unwrap(),
      label="sqrt",
    )
    legacy_shadow_assert_equal(
      left.pown_ctx(7, BinaryContext::new(precision=left.precision())).0,
      legacy_left.pow_positive(7),
      label="pow_positive",
    )
  }
}

///|
test "Binary long cancellation normalizes heap subtraction exactly" {
  let common = (1N << 4096) + (1N << 3072) + 1N
  let delta = 1N << 2048
  let left = Binary::make(
    BinCoeff::parse((common + delta).to_string()).unwrap(),
    0,
    5000,
  )
  let right = Binary::make(
    BinCoeff::parse(common.to_string()).unwrap(),
    0,
    5000,
  )
  let legacy_left = LegacyBigIntBinary::make(common + delta, 0, 5000)
  let legacy_right = LegacyBigIntBinary::make(common, 0, 5000)
  legacy_shadow_assert_equal(
    left.sub(right),
    legacy_left.sub(legacy_right),
    label="long positive cancellation",
  )
  legacy_shadow_assert_equal(
    right.sub(left),
    legacy_right.sub(legacy_left),
    label="long negative cancellation",
  )
  let positive = left.sub(right)
  assert_eq(positive.coefficient(), BinCoeff::one())
  assert_eq(positive.exponent2(), 2048)
}

///|
test "LegacyBigIntBinary adapts signed zero and NaN metadata" {
  let positive_zero = Binary::zero(precision=17)
  let negative_zero = Binary::negative_zero(precision=17)
  let positive_infinity = Binary::inf(precision=17)
  let negative_infinity = Binary::inf(negative=true, precision=17)
  let quiet_nan = Binary::quiet_nan(
    payload=BinCoeff::from_uint64(37UL),
    negative=true,
    precision=17,
  )
  let signaling_nan = Binary::signaling_nan(
    payload=BinCoeff::from_uint64(19UL),
    negative=false,
    precision=17,
  )
  for
    candidate in [
      positive_zero, negative_zero, positive_infinity, negative_infinity, quiet_nan,
      signaling_nan,
    ] {
    legacy_shadow_assert_equal(
      candidate,
      legacy_binary_from_candidate(candidate),
    )
  }

  let legacy_positive_zero = legacy_binary_from_candidate(positive_zero)
  let legacy_negative_zero = legacy_binary_from_candidate(negative_zero)
  let legacy_positive_infinity = legacy_binary_from_candidate(positive_infinity)
  let legacy_negative_infinity = legacy_binary_from_candidate(negative_infinity)
  let legacy_quiet_nan = legacy_binary_from_candidate(quiet_nan)
  let legacy_signaling_nan = legacy_binary_from_candidate(signaling_nan)
  legacy_shadow_assert_equal(
    negative_zero.add(negative_zero),
    legacy_negative_zero.add(legacy_negative_zero),
  )
  legacy_shadow_assert_equal(
    negative_zero.sub(positive_zero),
    legacy_negative_zero.sub(legacy_positive_zero),
  )
  legacy_shadow_assert_equal(
    negative_zero.mul(negative_infinity),
    legacy_negative_zero.mul(legacy_negative_infinity),
  )
  legacy_shadow_assert_equal(
    negative_zero.div(positive_infinity),
    legacy_negative_zero.div(legacy_positive_infinity),
  )
  legacy_shadow_assert_equal(
    quiet_nan.add(positive_infinity),
    legacy_quiet_nan.add(legacy_positive_infinity),
  )
  legacy_shadow_assert_equal(
    positive_infinity.sub(signaling_nan),
    legacy_positive_infinity.sub(legacy_signaling_nan),
  )
  // The quiet NaN result is the same; the checked `sqrt` reports the invalid
  // operation of a signaling NaN (IEEE 754-2019 section 7.2 a), #262).
  legacy_shadow_assert_equal(
    signaling_nan.sqrt_ctx(BinaryContext::new(precision=17)).0,
    legacy_signaling_nan.sqrt().unwrap(),
  )
  // S4: the candidate's `sqrt` is a value, the invalid operation is its flag
  assert_true(signaling_nan.sqrt().is_quiet_nan())
  assert_true(
    signaling_nan.sqrt_ctx(BinaryContext::new(precision=17)).1.invalid_operation(),
  )
  legacy_shadow_assert_equal(
    negative_zero.sqrt(),
    legacy_negative_zero.sqrt().unwrap(),
  )
  // the candidate's domain result is a NaN with invalid_operation, the legacy type
  // still reports an `Err`
  assert_true(Binary::from_int(-1, precision=17).sqrt().is_nan())
  assert_true(
    Binary::from_int(-1, precision=17).sqrt_ctx(
      BinaryContext::new(precision=17),
    ).1.invalid_operation(),
  )
  match LegacyBigIntBinary::make(-legacy_bin_one(), 0, 17).sqrt() {
    Err(_) => ()
    Ok(_) => abort("the legacy sqrt of a negative value must be an Err")
  }
}
