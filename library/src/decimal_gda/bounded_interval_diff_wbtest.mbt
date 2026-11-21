///|
// `decimal_bounded_binary_interval` and the binary coefficient of a decimal
// coefficient against the previous implementation (a host big integer).

///|
fn interval_reference(
  value : Decimal,
  precision : Int32,
) -> (@bin_float.BinFloat, @bin_float.BinFloat)? {
  guard value.class == FpClass::Finite else { return None }
  if value.coefficient.is_zero() {
    let zero = @bin_float.BinFloat::zero(precision~)
    return Some((zero, zero))
  }
  let coefficient = @bin_float.BinCoeff::from_bytes_be(
    value.coefficient.to_bigint().to_octets(),
  )
  let binary_precision = Int32::max(precision, coefficient.bit_length() + 8)
  let downward = @bin_float.BinaryContext::new(
    precision=binary_precision,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardNegative,
  )
  let upward = @bin_float.BinaryContext::new(
    precision=binary_precision,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardPositive,
  )
  let coefficient_value = @bin_float.BinFloat::make(
    coefficient, 0, binary_precision,
  )
  let (power_lower, power_upper) = decimal_power10_bounds(
    binary_precision,
    value.exponent10,
  )
  let positive_lower = coefficient_value.mul_ctx(power_lower, downward).0
  let positive_upper = coefficient_value.mul_ctx(power_upper, upward).0
  if value.negative {
    Some((positive_upper.neg(), positive_lower.neg()))
  } else {
    Some((positive_lower, positive_upper))
  }
}

///|
fn interval_same_bin(a : @bin_float.BinFloat, b : @bin_float.BinFloat) -> Bool {
  a.compare(b) == 0 &&
  a.precision() == b.precision() &&
  a.is_negative() == b.is_negative() &&
  a.exponent2() == b.exponent2() &&
  a.coefficient().to_bytes_be() == b.coefficient().to_bytes_be()
}

///|
fn interval_check(coefficient : DecCoeff, exponent10 : Int32) -> Unit raise {
  for negative in [false, true] {
    let value = finite_with_exponent_repr(
      negative,
      coefficient,
      exponent10,
      coefficient.digits10(),
    )
    for precision in [10, 64, 120] {
      match
        (
          decimal_bounded_binary_interval(value, precision),
          interval_reference(value, precision),
        ) {
        (Some((a, b)), Some((c, d))) =>
          assert_true(interval_same_bin(a, c) && interval_same_bin(b, d))
        _ => fail("interval differs")
      }
    }
  }
}

///|
test "decimal coefficient bytes equal the big integer octets" {
  let state = Ref(0x1B873593CC9E2D51UL)
  for length in 1..<200 {
    let n = BigInt::from_octets(endpoint_random_bytes(state, length))
    if n == BigInt::from_int(0) {
      continue
    }
    let coeff = dec_coeff_from_bigint_repr(n)
    if coeff is Limbs(_, _) {
      assert_true(decimal_coeff_to_be_bytes(coeff) == n.to_octets())
    }
  }
  for length in [250, 511, 512, 1000, 2047, 4999, 5000, 8918, 20000] {
    let n = BigInt::from_octets(endpoint_random_bytes(state, length))
    let coeff = dec_coeff_from_bigint_repr(n)
    if coeff is Limbs(_, _) {
      assert_true(decimal_coeff_to_be_bytes(coeff) == n.to_octets())
    }
  }
  // powers of two and of ten with their neighbours, and the limb boundaries
  for shift in 0..<420 {
    for
      base in [
        BigInt::from_int(1) << shift,
        BigInt::from_int(10).pow(BigInt::from_int(shift)),
      ] {
      for delta in [-1, 0, 1] {
        let n = base + BigInt::from_int(delta)
        if n <= BigInt::from_int(0) {
          continue
        }
        let coeff = dec_coeff_from_bigint_repr(n)
        if coeff is Limbs(_, _) {
          assert_true(decimal_coeff_to_be_bytes(coeff) == n.to_octets())
        }
      }
    }
  }
}

///|
test "bounded binary interval equals the big integer reference" {
  let state = Ref(0x6C62272E07BB0142UL)
  for iteration in 0..<400 {
    let bytes_len = match iteration % 8 {
      0 => 1 + (endpoint_next(state) % 5000UL).to_int()
      1 => 1 + (endpoint_next(state) % 200UL).to_int()
      _ => 1 + (endpoint_next(state) % 20UL).to_int()
    }
    let n = BigInt::from_octets(endpoint_random_bytes(state, bytes_len))
    if n == BigInt::from_int(0) {
      continue
    }
    let span = if bytes_len > 200 { 100 } else { 2000 }
    for
      exponent10 in [
        0,
        -1,
        1,
        (endpoint_next(state) % span.to_uint64()).to_int(),
        -(endpoint_next(state) % span.to_uint64()).to_int(),
      ] {
      interval_check(dec_coeff_from_bigint_repr(n), exponent10)
    }
  }
  // powers of ten and of two, with neighbours, at both signs of the exponent
  for shift in 0..<130 {
    for
      base in [
        BigInt::from_int(1) << shift,
        BigInt::from_int(10).pow(BigInt::from_int(shift / 2)),
      ] {
      for delta in [-1, 0, 1] {
        let n = base + BigInt::from_int(delta)
        if n <= BigInt::from_int(0) {
          continue
        }
        for exponent10 in [0, -shift, shift, -2000, 2000] {
          interval_check(dec_coeff_from_bigint_repr(n), exponent10)
        }
      }
    }
  }
  let zero = Decimal::zero_raw(precision=16)
  assert_true(decimal_bounded_binary_interval(zero, 20) is Some(_))
  assert_true(
    decimal_bounded_binary_interval(Decimal::nan_raw(precision=16), 20) is None,
  )
}

///|
test "binary coefficient at the word, four-limb and long-route boundaries" {
  let ten = BigInt::from_int(10)
  let two = BigInt::from_int(2)
  let one = BigInt::from_int(1)
  // 10^18 - 1 and 10^18 (a word, then the first limb pair), 2^64 - 1 and 2^64
  // (the word limit), 10^36 - 1 (four limbs, 36 digits: the largest the word
  // pair route would take) and 10^36 (five limbs: the first coefficient of the
  // long route), 10^45 - 1 and 10^45
  let values = [
    ten.pow(BigInt::from_int(9)) - one,
    ten.pow(BigInt::from_int(9)),
    ten.pow(BigInt::from_int(18)) - one,
    ten.pow(BigInt::from_int(18)),
    two.pow(BigInt::from_int(63)),
    two.pow(BigInt::from_int(64)) - one,
    two.pow(BigInt::from_int(64)),
    two.pow(BigInt::from_int(120)),
    ten.pow(BigInt::from_int(27)) - one,
    ten.pow(BigInt::from_int(36)) - one,
    ten.pow(BigInt::from_int(36)),
    ten.pow(BigInt::from_int(36)) + one,
    ten.pow(BigInt::from_int(45)) - one,
    ten.pow(BigInt::from_int(45)),
  ]
  for n in values {
    let coeff = dec_coeff_from_bigint_repr(n)
    if coeff is Limbs(_, _) {
      assert_true(decimal_coeff_to_be_bytes(coeff) == n.to_octets())
    }
    for exponent10 in [0, -36, 36, -2000, 2000] {
      interval_check(coeff, exponent10)
    }
  }
}
