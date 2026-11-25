///|
// `decimal_bounded_binary_interval` and the binary coefficient of a decimal
// coefficient against the previous implementation (a host big integer).

///|
// The bounded binary interval of a decimal value is checked by exact integer arithmetic
// (core BigInt, not this library): the lower bound is at most and the upper bound at
// least the value `n * 10^exponent10`, and the interval is narrow. This replaces a
// comparison with the previous implementation, which used `decimal_power10_bounds` and
// `Binary::mul_ctx` like the code under test.

///|
fn interval_signed(b : @binary.Binary) -> (BigInt, Int32) {
  if b.is_zero() {
    return (BigInt::from_int(0), 0)
  }
  let magnitude = BigInt::from_octets(b.coefficient().to_bytes_be())
  (if b.is_sign_minus() { -magnitude } else { magnitude }, b.exponent2())
}

///|
fn interval_scale(k2 : Int32, k10 : Int32) -> BigInt {
  (BigInt::from_int(1) << k2) * BigInt::from_int(10).pow(BigInt::from_int(k10))
}

///|
/// Compares a * 2^a2 * 10^a10 with b * 2^b2 * 10^b10 exactly.
fn interval_compare(
  a : BigInt,
  a2 : Int32,
  a10 : Int32,
  b : BigInt,
  b2 : Int32,
  b10 : Int32,
) -> Int32 {
  let lhs = a *
    interval_scale(
      Int32::max(a2, 0) + Int32::max(-b2, 0),
      Int32::max(a10, 0) + Int32::max(-b10, 0),
    )
  let rhs = b *
    interval_scale(
      Int32::max(b2, 0) + Int32::max(-a2, 0),
      Int32::max(b10, 0) + Int32::max(-a10, 0),
    )
  lhs.compare(rhs)
}

///|
fn interval_check(n : BigInt, exponent10 : Int32) -> Unit raise {
  let coefficient = dec_coeff_from_bigint_repr(n)
  for negative in [false, true] {
    let value = finite_with_exponent_repr(
      negative,
      coefficient,
      exponent10,
      coefficient.digits10(),
    )
    let signed = if negative { -n } else { n }
    for precision in [10, 64, 120] {
      match decimal_bounded_binary_interval(value, precision) {
        Some((lower, upper)) => {
          let (lc, l2) = interval_signed(lower)
          let (uc, u2) = interval_signed(upper)
          // lower <= value <= upper
          assert_true(interval_compare(lc, l2, 0, signed, 0, exponent10) <= 0)
          assert_true(interval_compare(uc, u2, 0, signed, 0, exponent10) >= 0)
          // narrow: (upper - lower) * 2^(precision - 4) <= |value|, the relative width of a few units of the last place (the widest case of the rows needs precision - 3)
          let low2 = Int32::min(l2, u2)
          let diff = (uc << (u2 - low2)) - (lc << (l2 - low2))
          assert_true(diff.compare(BigInt::from_int(0)) >= 0)
          assert_true(
            interval_compare(
              diff,
              low2 + precision - 4,
              0,
              abs_bigint(n),
              0,
              exponent10,
            ) <=
            0,
          )
        }
        None => fail("no interval")
      }
    }
  }
}

///|
// oracle: B
// source: core `BigInt::to_octets` of the same integer (MoonBit core), for random byte strings of 1 to 20,000 bytes, 2^k +- 1 and 10^k +- 1 up to 420
// shares: dec_coeff_from_bigint_repr builds the coefficient from the integer
// primitives: dec_coeff_from_bigint_repr: a wrong coefficient gives other bytes and fails the equality; core BigInt::to_octets and from_octets
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
// oracle: B
// source: exact integer arithmetic of core BigInt: lower <= n * 10^e <= upper by cross multiplication, and (upper - lower) * 2^(precision - 4) <= |n * 10^e| (the widest case of the rows needs precision - 3); replaces a comparison with the previous implementation, which called decimal_power10_bounds and Binary::mul_ctx like the code under test
// shares: the result is read through Binary::coefficient, exponent2 and is_sign_minus
// primitives: Binary::coefficient, exponent2, is_sign_minus (accessors of a stored value)
test "bounded binary interval encloses the exact value tightly" {
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
      interval_check(n, exponent10)
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
          interval_check(n, exponent10)
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
// oracle: B
// source: the bytes of 10^9 - 1 .. 10^45 and 2^63 .. 2^120 against core BigInt::to_octets, and the interval of each by the exact containment and width check `interval_check` (core BigInt arithmetic)
// shares: dec_coeff_from_bigint_repr builds the coefficient
// primitives: dec_coeff_from_bigint_repr, finite_with_exponent_repr; core BigInt arithmetic
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
      interval_check(n, exponent10)
    }
  }
}
