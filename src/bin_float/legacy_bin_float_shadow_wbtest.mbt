///|
fn legacy_shadow_assert_equal(
  candidate : BinFloat,
  legacy : LegacyBigIntBinFloat,
  label? : String = "",
) -> Unit raise {
  if candidate.classify() != legacy.classify() ||
    candidate.sign() != legacy.sign() ||
    candidate.is_negative() != legacy.is_negative() ||
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
  assert_true(candidate.is_negative() == legacy.is_negative())
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
fn legacy_shadow_next(state : Int) -> Int {
  ((state.to_int64() * 1103515245L + 12345L) % 2147483648L).to_int()
}

///|
fn legacy_shadow_magnitude(seed : Int, bits : Int) -> (Int, BigInt) {
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
fn legacy_shadow_operand(seed : Int) -> (Int, BinFloat, LegacyBigIntBinFloat) {
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
    BinFloat::make(coefficient, exponent2, precision, negative~),
    LegacyBigIntBinFloat::make(
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
test "LegacyBigIntBinFloat make preserves ties-even normalization" {
  for item in [(9, 3), (11, 3), (13, 3), (15, 3), (31, 4), (33, 4)] {
    let (magnitude, precision) = item
    for negative in [false, true] {
      let coefficient = BinCoeff::from_uint64(magnitude.to_uint64())
      let candidate = BinFloat::make(coefficient, -7, precision, negative~)
      let legacy = LegacyBigIntBinFloat::make(
        if negative {
          -BigInt::from_int(magnitude)
        } else {
          BigInt::from_int(magnitude)
        },
        -7,
        precision,
      )
      legacy_shadow_assert_equal(candidate, legacy)
      let wide_candidate = BinFloat::make(coefficient, -7, 256, negative~)
      let wide_legacy = LegacyBigIntBinFloat::make(
        if negative {
          -BigInt::from_int(magnitude)
        } else {
          BigInt::from_int(magnitude)
        },
        -7,
        256,
      )
      legacy_shadow_assert_equal(
        wide_candidate.with_precision(precision, RoundingMode::ToNearestEven),
        wide_legacy.with_precision(precision, RoundingMode::ToNearestEven),
        label="round",
      )
    }
  }
}

///|
test "LegacyBigIntBinFloat fixed-seed finite shadow" {
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
    let legacy_positive_left = legacy_bin_float_from_candidate(positive_left)
    legacy_shadow_assert_equal(
      positive_left.sqrt().unwrap(),
      legacy_positive_left.sqrt().unwrap(),
      label="sqrt",
    )
    legacy_shadow_assert_equal(
      left.pow_int_ctx(7, BinaryContext::unbounded(left.precision())).0,
      legacy_left.pow_positive(7),
      label="pow_positive",
    )
  }
}

///|
test "BinFloat long cancellation normalizes heap subtraction exactly" {
  let common = (1N << 4096) + (1N << 3072) + 1N
  let delta = 1N << 2048
  let left = BinFloat::make(
    BinCoeff::parse((common + delta).to_string()).unwrap(),
    0,
    5000,
  )
  let right = BinFloat::make(
    BinCoeff::parse(common.to_string()).unwrap(),
    0,
    5000,
  )
  let legacy_left = LegacyBigIntBinFloat::make(common + delta, 0, 5000)
  let legacy_right = LegacyBigIntBinFloat::make(common, 0, 5000)
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
test "LegacyBigIntBinFloat adapts signed zero and NaN metadata" {
  let positive_zero = BinFloat::zero(precision=17)
  let negative_zero = BinFloat::negative_zero(precision=17)
  let positive_infinity = BinFloat::inf(Sign::Positive, precision=17)
  let negative_infinity = BinFloat::inf(Sign::Negative, precision=17)
  let quiet_nan = BinFloat::quiet_nan(
    payload=BinCoeff::from_uint64(37UL),
    negative=true,
    precision=17,
  )
  let signaling_nan = BinFloat::signaling_nan(
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
      legacy_bin_float_from_candidate(candidate),
    )
  }

  let legacy_positive_zero = legacy_bin_float_from_candidate(positive_zero)
  let legacy_negative_zero = legacy_bin_float_from_candidate(negative_zero)
  let legacy_positive_infinity = legacy_bin_float_from_candidate(
    positive_infinity,
  )
  let legacy_negative_infinity = legacy_bin_float_from_candidate(
    negative_infinity,
  )
  let legacy_quiet_nan = legacy_bin_float_from_candidate(quiet_nan)
  let legacy_signaling_nan = legacy_bin_float_from_candidate(signaling_nan)
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
  legacy_shadow_assert_equal(
    signaling_nan.sqrt().unwrap(),
    legacy_signaling_nan.sqrt().unwrap(),
  )
  legacy_shadow_assert_equal(
    negative_zero.sqrt().unwrap(),
    legacy_negative_zero.sqrt().unwrap(),
  )
  match
    (
      BinFloat::from_int(-1, precision=17).sqrt(),
      LegacyBigIntBinFloat::make(-legacy_bin_one(), 0, 17).sqrt(),
    ) {
    (Err(_), Err(_)) => ()
    _ => abort("candidate and legacy sqrt domain results differ")
  }
}
