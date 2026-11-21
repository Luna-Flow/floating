///|
/// Division of wide operands: the divisor has at least 800 limbs, above the
/// threshold of the recursive division on every tier, so that
/// `bin_coeff_short_div_rem` takes the Burnikel-Ziegler route. The expected
/// results are constructed (`N = q d + r`, so the quotient, the round bit and
/// the sticky bit are known) or checked by the exact rounding interval.
struct DivLongRandom {
  mut div_long_state : UInt64
}

///|
fn DivLongRandom::next(self : DivLongRandom) -> UInt64 {
  self.div_long_state = self.div_long_state * 6364136223846793005UL +
    1442695040888963407UL
  (self.div_long_state >> 17) | (self.div_long_state << 47)
}

///|
/// A coefficient of exactly `bits` bits.
fn div_long_coeff(random : DivLongRandom, bits : Int32) -> Coeff {
  let mut value = Coeff::one()
  while value.bit_length() < bits {
    value = value.shift_left(32).add(Coeff::from_uint64(random.next() >> 32))
  }
  let trimmed = value.shift_right(value.bit_length() - bits)
  if trimmed.bit_length() < bits {
    Coeff::one().shift_left(bits - 1).add(trimmed)
  } else {
    trimmed
  }
}

///|
fn div_long_modes() -> Array[BinaryRoundingMode] {
  [
    BinaryRoundingMode::RoundTiesToEven,
    BinaryRoundingMode::RoundTiesToAway,
    BinaryRoundingMode::RoundTowardZero,
    BinaryRoundingMode::RoundTowardPositive,
    BinaryRoundingMode::RoundTowardNegative,
  ]
}

///|
/// `x / y` for `x = N` and `y = d` rounded to `precision` bits, with
/// `N = q d + r`, `q` of `precision + 1` bits, `0 <= r < d`: the round bit is
/// the low bit of `q`, the sticky bit is `r != 0`.
fn div_long_check_constructed(
  q : Coeff,
  d : Coeff,
  r : Coeff,
  precision : Int32,
  mode : BinaryRoundingMode,
  negative : Bool,
) -> Unit raise {
  let numerator = q.mul(d).add(r)
  let x = finite_from_parts(negative, numerator, 0, numerator.bit_length())
  let y = finite_from_parts(false, d, 0, d.bit_length())
  let context = BinaryContext::new(precision~, rounding=mode)
  let (actual, flags) = x.div_ctx(y, context)
  let round_bit = q.test_bit(0)
  let sticky = !r.is_zero()
  let retained = binary_apply_round_bits(
    q.shift_right(1),
    round_bit,
    sticky,
    negative,
    mode,
  )
  // value = retained * 2^1 (the quotient N / d lies in [q, q + 1))
  let expected = finite_from_parts(negative, retained, 1, precision)
  assert_identical(actual, expected)
  assert_eq(flags.inexact(), round_bit || sticky)
  assert_eq(flags.overflow(), false)
  assert_eq(flags.underflow(), false)
}

///|
test "div_ctx of wide operands: rounding bits all zero, all one, exactly half, in five directions" {
  let random = { div_long_state: 0x4D49_5353_494E_4721UL, }
  for divisor_bits in [51200, 51264, 53000, 60001] {
    let d = div_long_coeff(random, divisor_bits).add(Coeff::one())
    let d = if d.is_odd() { d } else { d.add(Coeff::one()) }
    for precision in [53, 700, 3000] {
      let q_odd = div_long_coeff(random, precision + 1)
      let q_odd = if q_odd.is_odd() { q_odd } else { q_odd.add(Coeff::one()) }
      let q_even = q_odd.add(Coeff::one())
      let d_minus_1 = d.sub_checked(Coeff::one()).unwrap()
      for mode in div_long_modes() {
        for negative in [false, true] {
          // round bit 0, sticky 0: an exact quotient with an even last bit
          div_long_check_constructed(
            q_even,
            d,
            Coeff::zero(),
            precision,
            mode,
            negative,
          )
          // round bit 1, sticky 0: exactly half
          div_long_check_constructed(
            q_odd,
            d,
            Coeff::zero(),
            precision,
            mode,
            negative,
          )
          // round bit 1, sticky 1 (all ones: remainder d - 1)
          div_long_check_constructed(
            q_odd, d, d_minus_1, precision, mode, negative,
          )
          // round bit 0, sticky 1
          div_long_check_constructed(
            q_even, d, d_minus_1, precision, mode, negative,
          )
          // round bit 1, remainder 1 and d / 2
          div_long_check_constructed(
            q_odd,
            d,
            Coeff::one(),
            precision,
            mode,
            negative,
          )
          div_long_check_constructed(
            q_even,
            d,
            d.shift_right(1),
            precision,
            mode,
            negative,
          )
        }
      }
    }
  }
}

///|
/// `|m 2^e_result * y - x| <= 2^(e_result - 1) |y|` in exact arithmetic: the
/// result is within half a unit of the last place of the exact quotient.
fn div_long_within_half_ulp(x : Binary, y : Binary, result : Binary) -> Bool {
  // x = n 2^ex, y = d 2^ey, result = m 2^er; the quotient in units of d / n:
  // (2 m - 1) 2^(u - 1) d <= n <= (2 m + 1) 2^(u - 1) d with u = er - ex + ey
  let n = x.coefficient_()
  let d = y.coefficient_()
  let m = result.coefficient_()
  let s = result.exponent2_() - x.exponent2_() + y.exponent2_() - 1
  let lower = m.shift_left(1).sub_checked(Coeff::one()).unwrap().mul(d)
  let upper = m.shift_left(1).add(Coeff::one()).mul(d)
  let (left_low, right_low) = if s >= 0 {
    (lower.shift_left(s), n)
  } else {
    (lower, n.shift_left(-s))
  }
  let (left_high, right_high) = if s >= 0 {
    (upper.shift_left(s), n)
  } else {
    (upper, n.shift_left(-s))
  }
  left_low.compare(right_low) <= 0 && right_high.compare(left_high) <= 0
}

///|
test "div and div_ctx of full-width operands above the recursive-division threshold are correctly rounded" {
  let random = { div_long_state: 0x1357_9BDF_0246_8ACEUL, }
  for bits in [51200, 52000, 64000] {
    let a = finite_from_parts(false, div_long_coeff(random, bits), -bits, bits)
    let b = finite_from_parts(false, div_long_coeff(random, bits), -bits, bits)
    let quotient = a.div(b)
    assert_true(div_long_within_half_ulp(a, b, quotient))
    let (general, flags) = a.div_ctx(b, BinaryContext::new(precision=bits))
    assert_identical(general, quotient)
    assert_true(flags.inexact())
    // a divisor that is a multiple structure: a = q b exactly
    let q = div_long_coeff(random, 700)
    let exact_x = finite_from_parts(
      false,
      q.mul(b.coefficient_()),
      0,
      q.bit_length() + b.coefficient_().bit_length(),
    )
    let (exact, exact_flags) = exact_x.div_ctx(
      b,
      BinaryContext::new(precision=800),
    )
    assert_eq(exact_flags.inexact(), false)
    assert_identical(exact, finite_from_parts(false, q, -b.exponent2_(), 800))
  }
}
